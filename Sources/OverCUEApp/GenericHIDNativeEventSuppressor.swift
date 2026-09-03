import AppKit
import ApplicationServices
import Dispatch
import Foundation
import IOKit.hid
import OverCUECore

/// Suppresses the ordinary macOS keyboard / media-key event emitted by a bound
/// Generic HID while leaving the device itself open in shared mode.
///
/// Raw IOHID observation and CGEvent filtering intentionally run on separate
/// dedicated run loops. The event-tap callback may wait briefly for matching raw
/// HID evidence, so it must neither share the IOHID run loop nor block the app's
/// main run loop / SwiftUI event processing.
final class GenericHIDNativeEventSuppressor: @unchecked Sendable {
    private enum Phase: Equatable {
        case pressed
        case released
        case either
    }

    private enum NativeInput: Equatable {
        case keyboard(CGKeyCode)
        case media(Int)
    }

    private struct PendingEvent {
        let input: NativeInput
        let phase: Phase
        let expiresAt: TimeInterval
    }

    private final class ObserverToken: @unchecked Sendable {
        let value: any NSObjectProtocol
        init(_ value: any NSObjectProtocol) { self.value = value }
    }

    private let manager: IOHIDManager
    private let pendingCondition = NSCondition()
    private let lifecycleLock = NSLock()
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var eventTapThread: Thread?
    private var eventTapRunLoop: CFRunLoop?
    private var eventTapThreadExit: DispatchSemaphore?
    private var configurationObserver: ObserverToken?
    private var pendingEvents: [PendingEvent] = []
    private var isOpen = false
    private var hidThread: Thread?
    private var hidRunLoop: CFRunLoop?
    private var hidThreadExit: DispatchSemaphore?
    private let diagnosticsEnabled = ProcessInfo.processInfo.environment[
        "OVERCUE_HID_SUPPRESSION_DIAGNOSTICS"
    ] == "1"

    var isRunning: Bool { isOpen && eventTap != nil }

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(
            manager,
            genericHIDNativeSuppressionValueReceived,
            context
        )
    }

    deinit {
        stop()
    }

    func start() throws {
        diagnosticLog(
            "start requested listenAccess=\(CGPreflightListenEventAccess()) "
                + "accessibility=\(AXIsProcessTrusted())"
        )
        guard !isRunning else { return }
        try configureDeviceMatching()
        startHIDRunLoopIfNeeded()

        if !isOpen {
            let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard result == kIOReturnSuccess else {
                stopHIDRunLoop()
                throw GenericHIDDeviceIdentifierMonitorError.openFailed(result)
            }
            isOpen = true
            let matchedCount = IOHIDManagerCopyDevices(manager).map(CFSetGetCount) ?? 0
            lifecycleLock.lock()
            let hidThreadActive = hidThread != nil && hidRunLoop != nil
            lifecycleLock.unlock()
            diagnosticLog(
                "IOHID shared open success matchedDevices=\(matchedCount) "
                    + "hidThreadActive=\(hidThreadActive)"
            )
        }

        do {
            try startEventTapRunLoopIfNeeded()
            lifecycleLock.lock()
            let eventTapEnabled = eventTap.map(CGEvent.tapIsEnabled) ?? false
            let eventTapThreadActive = eventTapThread != nil && eventTapRunLoop != nil
            lifecycleLock.unlock()
            diagnosticLog(
                "event tap started enabled=\(eventTapEnabled) "
                    + "eventTapThreadActive=\(eventTapThreadActive)"
            )
        } catch {
            if isOpen {
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
                isOpen = false
            }
            stopHIDRunLoop()
            throw error
        }

        if configurationObserver == nil {
            configurationObserver = ObserverToken(
                DistributedNotificationCenter.default().addObserver(
                    forName: OverCUEConfigurationChangedNotification.name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    try? self?.configureDeviceMatching()
                }
            )
        }
    }

    func stop() {
        diagnosticLog("stop requested")
        clearPendingEvents()

        if let configurationObserver {
            DistributedNotificationCenter.default().removeObserver(configurationObserver.value)
            self.configurationObserver = nil
        }

        stopEventTapRunLoop()

        if isOpen {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            isOpen = false
        }
        stopHIDRunLoop()
    }

    fileprivate func didReceiveValue(result: IOReturn, value: IOHIDValue) {
        guard result == kIOReturnSuccess else {
            diagnosticLog(String(format: "IOHID callback error=0x%08X", result))
            return
        }
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        guard usage != 0, usage != UInt32.max else { return }

        let integerValue = IOHIDValueGetIntegerValue(value)
        let phase: Phase = integerValue == 0 ? .released : .pressed
        diagnosticLog(
            String(
                format: "IOHID page=0x%04X usage=0x%04X report=%u value=%lld phase=%@",
                usagePage,
                usage,
                IOHIDElementGetReportID(element),
                integerValue,
                String(describing: phase)
            )
        )
        let nativeInput: NativeInput?

        switch usagePage {
        case 0x0007:
            nativeInput = Self.keyboardKeyCode(for: usage).map(NativeInput.keyboard)
        case 0x000C:
            nativeInput = Self.mediaKeyType(for: usage).map(NativeInput.media)
        default:
            nativeInput = nil
        }

        guard let nativeInput else { return }
        let now = ProcessInfo.processInfo.systemUptime
        pendingCondition.lock()
        pendingEvents.removeAll { $0.expiresAt < now }
        pendingEvents.append(
            PendingEvent(
                input: nativeInput,
                phase: phase,
                expiresAt: now + 0.12
            )
        )
        if pendingEvents.count > 16 {
            pendingEvents.removeFirst(pendingEvents.count - 16)
        }
        pendingCondition.broadcast()
        pendingCondition.unlock()
    }

    fileprivate func filter(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            diagnosticLog("CGEvent tap disabled type=\(type.rawValue); re-enabling")
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
        if sourcePID == Int64(ProcessInfo.processInfo.processIdentifier) {
            diagnosticLog(
                "CGEvent type=\(type.rawValue) sourcePID=\(sourcePID) action=pass-self"
            )
            return Unmanaged.passUnretained(event)
        }

        guard let observed = nativeEvent(type: type, event: event) else {
            diagnosticLog("CGEvent type=\(type.rawValue) not recognized")
            return Unmanaged.passUnretained(event)
        }

        let dropped = consumeMatchingPhysicalEvent(observed)
        diagnosticLog(
            "CGEvent type=\(type.rawValue) input=\(observed.input) "
                + "phase=\(observed.phase) action=\(dropped ? "drop" : "pass")"
        )
        if dropped {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    /// Wait only long enough for the independent IOHID run loop to deliver the
    /// raw event that produced this CGEvent. Eight milliseconds is below the
    /// interaction budget for a controller input and now runs entirely off the
    /// app's main run loop.
    private func consumeMatchingPhysicalEvent(
        _ observed: (input: NativeInput, phase: Phase)
    ) -> Bool {
        let deadline = Date(timeIntervalSinceNow: 0.008)
        pendingCondition.lock()
        defer { pendingCondition.unlock() }

        while true {
            let now = ProcessInfo.processInfo.systemUptime
            pendingEvents.removeAll { $0.expiresAt < now }
            if let index = pendingEvents.firstIndex(where: { pending in
                pending.input == observed.input
                    && (pending.phase == .either
                        || observed.phase == .either
                        || pending.phase == observed.phase)
            }) {
                pendingEvents.remove(at: index)
                return true
            }

            if !pendingCondition.wait(until: deadline) {
                return false
            }
        }
    }

    private func clearPendingEvents() {
        pendingCondition.lock()
        pendingEvents = []
        pendingCondition.broadcast()
        pendingCondition.unlock()
    }

    private func startHIDRunLoopIfNeeded() {
        lifecycleLock.lock()
        if hidThread != nil {
            lifecycleLock.unlock()
            return
        }

        let ready = DispatchSemaphore(value: 0)
        let exit = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else {
                ready.signal()
                exit.signal()
                return
            }

            guard let runLoop = CFRunLoopGetCurrent() else {
                self.lifecycleLock.lock()
                self.hidThread = nil
                self.hidThreadExit = nil
                self.lifecycleLock.unlock()
                ready.signal()
                exit.signal()
                return
            }
            self.lifecycleLock.lock()
            self.hidRunLoop = runLoop
            self.lifecycleLock.unlock()
            self.diagnosticLog("IOHID run loop ready")

            IOHIDManagerScheduleWithRunLoop(
                self.manager,
                runLoop,
                CFRunLoopMode.defaultMode.rawValue
            )
            ready.signal()
            CFRunLoopRun()
            self.diagnosticLog("IOHID run loop returned")
            IOHIDManagerUnscheduleFromRunLoop(
                self.manager,
                runLoop,
                CFRunLoopMode.defaultMode.rawValue
            )

            self.lifecycleLock.lock()
            self.hidRunLoop = nil
            self.hidThread = nil
            self.hidThreadExit = nil
            self.lifecycleLock.unlock()
            exit.signal()
        }
        thread.name = "OverCUE Generic HID Suppression"
        hidThread = thread
        hidThreadExit = exit
        lifecycleLock.unlock()

        thread.start()
        ready.wait()
    }

    private func stopHIDRunLoop() {
        lifecycleLock.lock()
        let runLoop = hidRunLoop
        let exit = hidThreadExit
        lifecycleLock.unlock()

        guard let runLoop else { return }
        CFRunLoopStop(runLoop)
        CFRunLoopWakeUp(runLoop)
        _ = exit?.wait(timeout: .now() + 1.0)
    }

    private func startEventTapRunLoopIfNeeded() throws {
        lifecycleLock.lock()
        if eventTapThread != nil {
            lifecycleLock.unlock()
            return
        }

        let ready = DispatchSemaphore(value: 0)
        let exit = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else {
                ready.signal()
                exit.signal()
                return
            }

            guard let runLoop = CFRunLoopGetCurrent() else {
                self.lifecycleLock.lock()
                self.eventTapThread = nil
                self.eventTapThreadExit = nil
                self.lifecycleLock.unlock()
                ready.signal()
                exit.signal()
                return
            }

            let eventMask = CGEventMask(1) << CGEventType.keyDown.rawValue
                | CGEventMask(1) << CGEventType.keyUp.rawValue
                | CGEventMask(1) << CGEventType.flagsChanged.rawValue
                | CGEventMask(1) << CGEventType.systemDefined.rawValue
            let context = Unmanaged.passUnretained(self).toOpaque()
            guard let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: genericHIDNativeSuppressionEventTap,
                userInfo: context
            ) else {
                self.lifecycleLock.lock()
                self.eventTapThread = nil
                self.eventTapThreadExit = nil
                self.lifecycleLock.unlock()
                ready.signal()
                exit.signal()
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.lifecycleLock.lock()
            self.eventTap = tap
            self.eventTapSource = source
            self.eventTapRunLoop = runLoop
            self.lifecycleLock.unlock()

            CFRunLoopAddSource(runLoop, source, CFRunLoopMode.commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.diagnosticLog("CGEvent run loop ready")
            ready.signal()
            CFRunLoopRun()
            self.diagnosticLog("CGEvent run loop returned")

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, CFRunLoopMode.commonModes)
            self.lifecycleLock.lock()
            self.eventTap = nil
            self.eventTapSource = nil
            self.eventTapRunLoop = nil
            self.eventTapThread = nil
            self.eventTapThreadExit = nil
            self.lifecycleLock.unlock()
            exit.signal()
        }
        thread.name = "OverCUE Generic HID Event Tap"
        eventTapThread = thread
        eventTapThreadExit = exit
        lifecycleLock.unlock()

        thread.start()
        ready.wait()

        lifecycleLock.lock()
        let started = eventTap != nil && eventTapRunLoop != nil
        lifecycleLock.unlock()
        guard started else {
            throw NSError(
                domain: "OverCUE.GenericHIDNativeEventSuppressor",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Input Monitoring permission is required for Generic HID input filtering."
                ]
            )
        }
    }

    private func stopEventTapRunLoop() {
        lifecycleLock.lock()
        let tap = eventTap
        let runLoop = eventTapRunLoop
        let exit = eventTapThreadExit
        lifecycleLock.unlock()

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        guard let runLoop else { return }
        CFRunLoopStop(runLoop)
        CFRunLoopWakeUp(runLoop)
        _ = exit?.wait(timeout: .now() + 1.0)
    }

    private func configureDeviceMatching() throws {
        let configuration = try OverCUEConfigurationFileStore.readCurrent(
            at: OverCUEAppConfigurationLocation.url
        )
        let matches: [[String: Any]] = configuration.physicalDeviceBindings.compactMap { binding in
            guard binding.kind == .genericHID,
                  let serial = binding.serialNumber
            else { return nil }
            return [
                kIOHIDVendorIDKey as String: binding.vendorID,
                kIOHIDProductIDKey as String: binding.productID,
                kIOHIDSerialNumberKey as String: serial,
            ]
        }

        if matches.isEmpty {
            IOHIDManagerSetDeviceMatching(
                manager,
                [
                    kIOHIDVendorIDKey as String: Int.max,
                    kIOHIDProductIDKey as String: Int.max,
                ] as CFDictionary
            )
        } else {
            IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        }
        diagnosticLog("configured registered Generic HID matches=\(matches.count)")
    }

    private func nativeEvent(
        type: CGEventType,
        event: CGEvent
    ) -> (input: NativeInput, phase: Phase)? {
        switch type {
        case .keyDown:
            diagnosticLog(
                "CGEvent keyDown keyCode="
                    + "\(event.getIntegerValueField(.keyboardEventKeycode))"
            )
            return (
                .keyboard(CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))),
                .pressed
            )
        case .keyUp:
            diagnosticLog(
                "CGEvent keyUp keyCode="
                    + "\(event.getIntegerValueField(.keyboardEventKeycode))"
            )
            return (
                .keyboard(CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))),
                .released
            )
        case .flagsChanged:
            diagnosticLog(
                "CGEvent flagsChanged keyCode="
                    + "\(event.getIntegerValueField(.keyboardEventKeycode))"
            )
            return (
                .keyboard(CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))),
                .either
            )
        case .systemDefined:
            guard let nsEvent = NSEvent(cgEvent: event) else {
                diagnosticLog("CGEvent systemDefined could not convert to NSEvent")
                return nil
            }
            diagnosticLog(
                String(
                    format: "CGEvent systemDefined raw subtype=%d data1=0x%08X data2=0x%08X",
                    nsEvent.subtype.rawValue,
                    UInt32(bitPattern: Int32(nsEvent.data1)),
                    UInt32(bitPattern: Int32(nsEvent.data2))
                )
            )
            guard nsEvent.subtype.rawValue == 8 else {
                return nil
            }
            let data1 = UInt32(bitPattern: Int32(nsEvent.data1))
            let mediaKey = Int((data1 & 0xFFFF0000) >> 16)
            let state = data1 & 0x0000FF00
            diagnosticLog(
                String(
                    format: "CGEvent systemDefined subtype=%d data1=0x%08X mediaKey=%d state=0x%04X",
                    nsEvent.subtype.rawValue,
                    data1,
                    mediaKey,
                    state
                )
            )
            let phase: Phase
            switch state {
            case 0x0A00: phase = .pressed
            case 0x0B00: phase = .released
            default: phase = .either
            }
            return (.media(mediaKey), phase)
        default:
            return nil
        }
    }

    private static func mediaKeyType(for usage: UInt32) -> Int? {
        switch usage {
        case 0x00E9: 0   // Volume increment
        case 0x00EA: 1   // Volume decrement
        case 0x00E2: 7   // Mute
        case 0x00CD: 16  // Play / pause
        case 0x00B5: 17  // Scan next track
        case 0x00B6: 18  // Scan previous track
        default: nil
        }
    }

    /// USB HID keyboard-page usage -> macOS virtual key code.
    /// Unknown usages are intentionally not suppressed; fail-open is safer than
    /// swallowing an unrelated key from the user's primary keyboard.
    private static func keyboardKeyCode(for usage: UInt32) -> CGKeyCode? {
        let table: [UInt32: CGKeyCode] = [
            0x04: 0, 0x05: 11, 0x06: 8, 0x07: 2, 0x08: 14, 0x09: 3,
            0x0A: 5, 0x0B: 4, 0x0C: 34, 0x0D: 38, 0x0E: 40, 0x0F: 37,
            0x10: 46, 0x11: 45, 0x12: 31, 0x13: 35, 0x14: 12, 0x15: 15,
            0x16: 1, 0x17: 17, 0x18: 32, 0x19: 9, 0x1A: 13, 0x1B: 7,
            0x1C: 16, 0x1D: 6,
            0x1E: 18, 0x1F: 19, 0x20: 20, 0x21: 21, 0x22: 23,
            0x23: 22, 0x24: 26, 0x25: 28, 0x26: 25, 0x27: 29,
            0x28: 36, 0x29: 53, 0x2A: 51, 0x2B: 48, 0x2C: 49,
            0x2D: 27, 0x2E: 24, 0x2F: 33, 0x30: 30, 0x31: 42,
            0x33: 41, 0x34: 39, 0x35: 50, 0x36: 43, 0x37: 47, 0x38: 44,
            0x39: 57,
            0x3A: 122, 0x3B: 120, 0x3C: 99, 0x3D: 118, 0x3E: 96,
            0x3F: 97, 0x40: 98, 0x41: 100, 0x42: 101, 0x43: 109,
            0x44: 103, 0x45: 111,
            0x4F: 124, 0x50: 123, 0x51: 125, 0x52: 126,
            0x54: 75, 0x55: 67, 0x56: 78, 0x57: 69, 0x58: 76,
            0x59: 83, 0x5A: 84, 0x5B: 85, 0x5C: 86, 0x5D: 87,
            0x5E: 88, 0x5F: 89, 0x60: 91, 0x61: 92, 0x62: 82,
            0x63: 65, 0x67: 81,
            0xE0: 59, 0xE1: 56, 0xE2: 58, 0xE3: 55,
            0xE4: 62, 0xE5: 60, 0xE6: 61, 0xE7: 54,
        ]
        return table[usage]
    }

    private func diagnosticLog(_ message: @autoclosure () -> String) {
        guard diagnosticsEnabled else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        let thread = Thread.isMainThread ? "main" : (Thread.current.name ?? "background")
        fputs(
            String(format: "[HID-SUPPRESS %.6f %@] %@\n", uptime, thread, message()),
            stderr
        )
        fflush(stderr)
    }
}

private func genericHIDNativeSuppressionValueReceived(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard let context else { return }
    Unmanaged<GenericHIDNativeEventSuppressor>.fromOpaque(context).takeUnretainedValue()
        .didReceiveValue(result: result, value: value)
}

private func genericHIDNativeSuppressionEventTap(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<GenericHIDNativeEventSuppressor>.fromOpaque(userInfo).takeUnretainedValue()
        .filter(type: type, event: event)
}

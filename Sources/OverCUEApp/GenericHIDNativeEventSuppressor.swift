import AppKit
import ApplicationServices
import Foundation
import IOKit.hid
import OverCUECore

/// Suppresses the ordinary macOS keyboard / media-key event emitted by a bound
/// Generic HID while leaving the device itself open in shared mode.
///
/// Keyboard-class HID devices cannot be reliably seized by an ordinary
/// Developer ID application. Instead, observe only already-bound Generic HID
/// devices through IOHID, remember the concrete physical input that just fired,
/// and drop the matching downstream CGEvent. This keeps the user's normal
/// keyboard usable because an event is removed only when it correlates with a
/// physical event from a registered Generic HID.
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
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var configurationObserver: ObserverToken?
    private var pendingEvents: [PendingEvent] = []
    private var isOpen = false

    var isRunning: Bool { isOpen && eventTap != nil }

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(
            manager,
            genericHIDNativeSuppressionValueReceived,
            context
        )
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
    }

    deinit {
        stop()
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
    }

    func start() throws {
        guard !isRunning else { return }
        try configureDeviceMatching()

        if !isOpen {
            let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard result == kIOReturnSuccess else {
                throw GenericHIDDeviceIdentifierMonitorError.openFailed(result)
            }
            isOpen = true
        }

        do {
            try startEventTap()
        } catch {
            if isOpen {
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
                isOpen = false
            }
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
        pendingEvents = []

        if let configurationObserver {
            DistributedNotificationCenter.default().removeObserver(configurationObserver.value)
            self.configurationObserver = nil
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let eventTapSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                eventTapSource,
                CFRunLoopMode.commonModes
            )
        }
        eventTapSource = nil
        eventTap = nil

        if isOpen {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            isOpen = false
        }
    }

    fileprivate func didReceiveValue(result: IOReturn, value: IOHIDValue) {
        guard result == kIOReturnSuccess else { return }
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        guard usage != 0, usage != UInt32.max else { return }

        let integerValue = IOHIDValueGetIntegerValue(value)
        let phase: Phase = integerValue == 0 ? .released : .pressed
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
    }

    fileprivate func filter(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let observed = nativeEvent(type: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }

        let now = ProcessInfo.processInfo.systemUptime
        pendingEvents.removeAll { $0.expiresAt < now }
        guard let index = pendingEvents.firstIndex(where: { pending in
            pending.input == observed.input
                && (pending.phase == .either
                    || observed.phase == .either
                    || pending.phase == observed.phase)
        }) else {
            return Unmanaged.passUnretained(event)
        }

        pendingEvents.remove(at: index)
        return nil
    }

    private func startEventTap() throws {
        guard eventTap == nil else { return }
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
            throw NSError(
                domain: "OverCUE.GenericHIDNativeEventSuppressor",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Input Monitoring permission is required for Generic HID input filtering."
                ]
            )
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
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
    }

    private func nativeEvent(
        type: CGEventType,
        event: CGEvent
    ) -> (input: NativeInput, phase: Phase)? {
        switch type {
        case .keyDown:
            return (
                .keyboard(CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))),
                .pressed
            )
        case .keyUp:
            return (
                .keyboard(CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))),
                .released
            )
        case .flagsChanged:
            return (
                .keyboard(CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))),
                .either
            )
        case .systemDefined:
            guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
                return nil
            }
            let data1 = UInt32(bitPattern: Int32(nsEvent.data1))
            let mediaKey = Int((data1 & 0xFFFF0000) >> 16)
            let state = data1 & 0x0000FF00
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

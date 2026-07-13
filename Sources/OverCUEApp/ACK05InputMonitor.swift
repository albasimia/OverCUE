import Foundation
import IOKit.hid
import OverCUECore

private enum ACK05HardwareIdentity {
    static let vendorID = 0x28BD
    static let productID = 0x0202
}

enum ACK05InputMonitorError: LocalizedError {
    case openFailed(IOReturn)

    @MainActor var errorDescription: String? {
        switch self {
        case let .openFailed(status):
            let code = String(format: "0x%08X", UInt32(bitPattern: status))
            return L10n.text("input.openFailed", code)
        }
    }
}

final class ACK05InputMonitor {
    var onPressedKeysChanged: ((Set<ACK05Key>) -> Void)?
    var onDialTurned: ((DialDirection) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?

    private let manager: IOHIDManager
    private let decoder = ACK05ReportDecoder()
    private var previousKeys: Set<ACK05Key> = []
    private var isOpen = false

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(
            manager,
            [
                kIOHIDVendorIDKey as String: ACK05HardwareIdentity.vendorID,
                kIOHIDProductIDKey as String: ACK05HardwareIdentity.productID,
            ] as CFDictionary
        )

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, ack05DeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, ack05DeviceRemoved, context)
        IOHIDManagerRegisterInputReportCallback(manager, ack05InputReportReceived, context)
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
        guard !isOpen else { return }
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            throw ACK05InputMonitorError.openFailed(result)
        }
        isOpen = true
    }

    func stop() {
        guard isOpen else { return }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = false
        previousKeys = []
    }

    fileprivate func didMatch(result: IOReturn) {
        guard result == kIOReturnSuccess else { return }
        onConnectionChanged?(true)
    }

    fileprivate func didRemove(result: IOReturn) {
        guard result == kIOReturnSuccess else { return }
        previousKeys = []
        onConnectionChanged?(false)
    }

    fileprivate func didReceiveReport(
        result: IOReturn,
        reportID: UInt32,
        report: UnsafeMutablePointer<UInt8>,
        reportLength: CFIndex
    ) {
        guard result == kIOReturnSuccess else { return }
        let bytes = Array(UnsafeBufferPointer(start: report, count: max(0, Int(reportLength))))
        if case let .dial(direction) = decoder.decode(reportID: reportID, bytes: bytes) {
            onDialTurned?(direction)
            return
        }
        guard
            let keys = decoder.pressedKeys(
                reportID: reportID,
                bytes: bytes,
                previousKeys: previousKeys
            )
        else {
            return
        }
        previousKeys = keys
        onPressedKeysChanged?(keys)
    }
}

private func ack05DeviceMatched(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<ACK05InputMonitor>.fromOpaque(context).takeUnretainedValue().didMatch(result: result)
}

private func ack05DeviceRemoved(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<ACK05InputMonitor>.fromOpaque(context).takeUnretainedValue().didRemove(result: result)
}

private func ack05InputReportReceived(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context else { return }
    Unmanaged<ACK05InputMonitor>.fromOpaque(context).takeUnretainedValue().didReceiveReport(
        result: result,
        reportID: reportID,
        report: report,
        reportLength: reportLength
    )
}

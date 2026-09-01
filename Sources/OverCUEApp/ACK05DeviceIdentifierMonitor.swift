import Foundation
import IOKit.hid
import OverCUECore

private enum ACK05DeviceIdentifierHardware {
    static let vendorID = 0x28BD
    static let productID = 0x0202
}

enum ACK05DeviceIdentifierMonitorError: Error, LocalizedError {
    case openFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case let .openFailed(status):
            return L10n.text(
                "devices.identify.openFailed",
                String(format: "0x%08X", UInt32(bitPattern: status))
            )
        }
    }
}

final class ACK05DeviceIdentifierMonitor {
    var onDevicesChanged: (([HIDPhysicalDeviceDescriptor]) -> Void)?
    var onIdentified: ((HIDPhysicalDeviceDescriptor, [HIDPhysicalDeviceDescriptor]) -> Void)?

    private let manager: IOHIDManager
    private let decoder = ACK05ReportDecoder()
    private var devicesBySessionID: [String: HIDPhysicalDeviceDescriptor] = [:]
    private var previousKeysBySessionID: [String: Set<ACK05Key>] = [:]
    private var isOpen = false
    private var didIdentify = false

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(
            manager,
            [
                kIOHIDVendorIDKey as String: ACK05DeviceIdentifierHardware.vendorID,
                kIOHIDProductIDKey as String: ACK05DeviceIdentifierHardware.productID,
            ] as CFDictionary
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, identifyDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, identifyDeviceRemoved, context)
        IOHIDManagerRegisterInputReportCallback(manager, identifyInputReportReceived, context)
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
        didIdentify = false
        devicesBySessionID = [:]
        previousKeysBySessionID = [:]
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            throw ACK05DeviceIdentifierMonitorError.openFailed(result)
        }
        isOpen = true
    }

    func stop() {
        guard isOpen else { return }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = false
        devicesBySessionID = [:]
        previousKeysBySessionID = [:]
        didIdentify = false
    }

    fileprivate func didMatch(device: IOHIDDevice, result: IOReturn) {
        guard result == kIOReturnSuccess else { return }
        let descriptor = descriptor(for: device)
        devicesBySessionID[descriptor.sessionIdentifier] = descriptor
        publishDevices()
    }

    fileprivate func didRemove(device: IOHIDDevice, result: IOReturn) {
        guard result == kIOReturnSuccess else { return }
        let descriptor = descriptor(for: device)
        devicesBySessionID.removeValue(forKey: descriptor.sessionIdentifier)
        previousKeysBySessionID.removeValue(forKey: descriptor.sessionIdentifier)
        publishDevices()
    }

    fileprivate func didReceiveReport(
        result: IOReturn,
        device: IOHIDDevice?,
        reportID: UInt32,
        report: UnsafeMutablePointer<UInt8>,
        reportLength: CFIndex
    ) {
        guard result == kIOReturnSuccess, !didIdentify, let device else { return }
        let descriptor = descriptor(for: device)
        devicesBySessionID[descriptor.sessionIdentifier] = descriptor
        let bytes = Array(
            UnsafeBufferPointer(start: report, count: max(0, Int(reportLength)))
        )

        if case .dial = decoder.decode(reportID: reportID, bytes: bytes) {
            identify(descriptor)
            return
        }

        let previous = previousKeysBySessionID[descriptor.sessionIdentifier, default: []]
        guard let keys = decoder.pressedKeys(
            reportID: reportID,
            bytes: bytes,
            previousKeys: previous
        ) else { return }
        previousKeysBySessionID[descriptor.sessionIdentifier] = keys
        guard !keys.subtracting(previous).isEmpty else { return }
        identify(descriptor)
    }

    private func identify(_ descriptor: HIDPhysicalDeviceDescriptor) {
        guard !didIdentify else { return }
        didIdentify = true
        onIdentified?(descriptor, connectedDevices)
    }

    private func publishDevices() {
        onDevicesChanged?(connectedDevices)
    }

    private var connectedDevices: [HIDPhysicalDeviceDescriptor] {
        devicesBySessionID.values.sorted { $0.sessionIdentifier < $1.sessionIdentifier }
    }

    private func descriptor(for device: IOHIDDevice) -> HIDPhysicalDeviceDescriptor {
        let vendorID = propertyNumber(device, kIOHIDVendorIDKey)?.intValue
            ?? ACK05DeviceIdentifierHardware.vendorID
        let productID = propertyNumber(device, kIOHIDProductIDKey)?.intValue
            ?? ACK05DeviceIdentifierHardware.productID
        var legacyIdentifiers: Set<String> = []
        for key in ["PhysicalDeviceUniqueID", "DeviceAddress"] {
            if let value = property(device, key) as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                legacyIdentifiers.insert(value)
            }
        }
        let address = UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
        return HIDPhysicalDeviceDescriptor(
            kind: .ack05,
            vendorID: vendorID,
            productID: productID,
            serialNumber: property(device, kIOHIDSerialNumberKey) as? String,
            productName: property(device, kIOHIDProductKey) as? String,
            manufacturerName: property(device, kIOHIDManufacturerKey) as? String,
            transport: property(device, kIOHIDTransportKey) as? String,
            locationID: propertyNumber(device, kIOHIDLocationIDKey)?.uint32Value,
            transportIdentifier: String(address, radix: 16),
            legacyIdentifiers: legacyIdentifiers
        )
    }

    private func property(_ device: IOHIDDevice, _ key: String) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }

    private func propertyNumber(_ device: IOHIDDevice, _ key: String) -> NSNumber? {
        property(device, key) as? NSNumber
    }
}

private func identifyDeviceMatched(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<ACK05DeviceIdentifierMonitor>.fromOpaque(context).takeUnretainedValue()
        .didMatch(device: device, result: result)
}

private func identifyDeviceRemoved(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<ACK05DeviceIdentifierMonitor>.fromOpaque(context).takeUnretainedValue()
        .didRemove(device: device, result: result)
}

private func identifyInputReportReceived(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    reportType: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context else { return }
    let device = sender.map { Unmanaged<IOHIDDevice>.fromOpaque($0).takeUnretainedValue() }
    Unmanaged<ACK05DeviceIdentifierMonitor>.fromOpaque(context).takeUnretainedValue()
        .didReceiveReport(
            result: result,
            device: device,
            reportID: reportID,
            report: report,
            reportLength: reportLength
        )
}

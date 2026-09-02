import Foundation
import IOKit.hid
import OverCUECore

private enum GenericHIDDeviceIdentifierHardware {
    static let ack05VendorID = 0x28BD
    static let ack05ProductID = 0x0202
}

enum GenericHIDDeviceIdentifierMonitorError: @preconcurrency LocalizedError {
    case openFailed(IOReturn)

    @MainActor var errorDescription: String? {
        switch self {
        case let .openFailed(status):
            if status == kIOReturnNotPrivileged || status == kIOReturnNotPermitted {
                return L10n.text("cli.inputPermission")
            }
            return L10n.text(
                "devices.identify.openFailed",
                String(format: "0x%08X", UInt32(bitPattern: status))
            )
        }
    }
}

/// Generic HID Identify monitor.
///
/// Generic HID stays in shared mode so Identify never seizes the user's keyboard,
/// mouse, or other unrelated HID devices. Only devices with a verified serial
/// number are candidates for persistent binding. Composite HID interfaces are
/// grouped per live attachment by persistent identity + locationID. The group
/// keeps one runtime session token for the attachment while serial remains the
/// persistent identity stored in configuration.
final class GenericHIDDeviceIdentifierMonitor: @unchecked Sendable {
    var onDevicesChanged: (([HIDPhysicalDeviceDescriptor]) -> Void)?
    var onIdentified: ((HIDPhysicalDeviceDescriptor, [HIDPhysicalDeviceDescriptor]) -> Void)?

    private struct LiveGroupKey: Hashable {
        let persistentIdentifier: String
        let connectionQualifier: String
    }

    private struct LiveGroup {
        var representative: HIDPhysicalDeviceDescriptor
        var interfaceIDs: Set<UInt>
    }

    private let manager: IOHIDManager
    private var groups: [LiveGroupKey: LiveGroup] = [:]
    private var groupKeyByInterfaceID: [UInt: LiveGroupKey] = [:]
    private var isOpen = false
    private var didIdentify = false

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, genericIdentifyDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, genericIdentifyDeviceRemoved, context)
        IOHIDManagerRegisterInputValueCallback(manager, genericIdentifyInputValueReceived, context)
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
        groups = [:]
        groupKeyByInterfaceID = [:]
        didIdentify = false

        let result = HIDManagerOpenRetry.open(
            manager,
            options: IOOptionBits(kIOHIDOptionsTypeNone)
        )
        guard result == kIOReturnSuccess else {
            throw GenericHIDDeviceIdentifierMonitorError.openFailed(result)
        }
        isOpen = true
    }

    func stop() {
        guard isOpen else { return }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = false
        groups = [:]
        groupKeyByInterfaceID = [:]
        didIdentify = false
        publishDevices()
    }

    fileprivate func didMatch(device: IOHIDDevice, result: IOReturn) {
        guard result == kIOReturnSuccess else { return }
        _ = registerInterface(device)
        publishDevices()
    }

    fileprivate func didRemove(device: IOHIDDevice, result: IOReturn) {
        guard result == kIOReturnSuccess else { return }
        let interfaceID = interfaceIdentifier(device)
        guard let key = groupKeyByInterfaceID.removeValue(forKey: interfaceID),
              var group = groups[key]
        else { return }
        group.interfaceIDs.remove(interfaceID)
        if group.interfaceIDs.isEmpty {
            groups.removeValue(forKey: key)
        } else {
            groups[key] = group
        }
        publishDevices()
    }

    fileprivate func didReceiveValue(result: IOReturn, value: IOHIDValue) {
        guard result == kIOReturnSuccess, !didIdentify else { return }
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        guard let descriptor = registerInterface(device) else { return }
        let integerValue = IOHIDValueGetIntegerValue(value)
        guard shouldTreatAsIdentificationInput(element: element, value: integerValue) else { return }
        didIdentify = true
        onIdentified?(descriptor, connectedDevices)
    }

    private var connectedDevices: [HIDPhysicalDeviceDescriptor] {
        let representatives: [HIDPhysicalDeviceDescriptor] = groups.values.map(\.representative)
        return representatives.sorted(by: { lhs, rhs in
            lhs.sessionIdentifier < rhs.sessionIdentifier
        })
    }

    @discardableResult
    private func registerInterface(_ device: IOHIDDevice) -> HIDPhysicalDeviceDescriptor? {
        guard let descriptor = descriptor(for: device),
              let persistentIdentifier = descriptor.persistentIdentifier
        else { return nil }
        let key = LiveGroupKey(
            persistentIdentifier: persistentIdentifier,
            connectionQualifier: connectionQualifier(for: descriptor)
        )
        let interfaceID = interfaceIdentifier(device)
        if var group = groups[key] {
            group.interfaceIDs.insert(interfaceID)
            groups[key] = group
        } else {
            groups[key] = LiveGroup(
                representative: descriptor,
                interfaceIDs: [interfaceID]
            )
        }
        groupKeyByInterfaceID[interfaceID] = key
        return groups[key]?.representative
    }

    private func descriptor(for device: IOHIDDevice) -> HIDPhysicalDeviceDescriptor? {
        let vendorID = (IOHIDDeviceGetProperty(
            device,
            kIOHIDVendorIDKey as CFString
        ) as? NSNumber)?.intValue ?? 0
        let productID = (IOHIDDeviceGetProperty(
            device,
            kIOHIDProductIDKey as CFString
        ) as? NSNumber)?.intValue ?? 0
        guard vendorID > 0, productID > 0 else { return nil }
        if vendorID == GenericHIDDeviceIdentifierHardware.ack05VendorID,
           productID == GenericHIDDeviceIdentifierHardware.ack05ProductID {
            return nil
        }
        let serialNumber = (IOHIDDeviceGetProperty(
            device,
            kIOHIDSerialNumberKey as CFString
        ) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let serialNumber, !serialNumber.isEmpty else { return nil }
        let productName = IOHIDDeviceGetProperty(
            device,
            kIOHIDProductKey as CFString
        ) as? String
        let manufacturerName = IOHIDDeviceGetProperty(
            device,
            kIOHIDManufacturerKey as CFString
        ) as? String
        let transport = IOHIDDeviceGetProperty(
            device,
            kIOHIDTransportKey as CFString
        ) as? String
        let locationID = (IOHIDDeviceGetProperty(
            device,
            kIOHIDLocationIDKey as CFString
        ) as? NSNumber)?.uint32Value
        return HIDPhysicalDeviceDescriptor(
            kind: .genericHID,
            vendorID: vendorID,
            productID: productID,
            serialNumber: serialNumber,
            productName: productName,
            manufacturerName: manufacturerName,
            transport: transport,
            locationID: locationID,
            transportIdentifier: runtimeAttachmentIdentifier(
                vendorID: vendorID,
                productID: productID,
                serialNumber: serialNumber,
                locationID: locationID
            )
        )
    }

    private func runtimeAttachmentIdentifier(
        vendorID: Int,
        productID: Int,
        serialNumber: String,
        locationID: UInt32?
    ) -> String {
        let location = locationID.map { String(format: "%08X", $0) } ?? "unknown"
        return String(format: "%04X:%04X:%@:%@", vendorID, productID, serialNumber, location)
    }

    private func connectionQualifier(for descriptor: HIDPhysicalDeviceDescriptor) -> String {
        if let locationID = descriptor.locationID {
            return String(format: "location:%08X", locationID)
        }
        return "session:\(descriptor.transportIdentifier)"
    }

    private func interfaceIdentifier(_ device: IOHIDDevice) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    }

    private func publishDevices() {
        onDevicesChanged?(connectedDevices)
    }

    private func shouldTreatAsIdentificationInput(
        element: IOHIDElement,
        value: CFIndex
    ) -> Bool {
        let type = IOHIDElementGetType(element)
        switch type {
        case kIOHIDElementTypeInput_Button,
             kIOHIDElementTypeInput_Misc,
             kIOHIDElementTypeInput_Axis,
             kIOHIDElementTypeInput_ScanCodes:
            break
        default:
            return false
        }
        if IOHIDElementIsRelative(element) {
            return value != 0
        }
        return value != 0
    }
}

private func genericIdentifyDeviceMatched(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<GenericHIDDeviceIdentifierMonitor>.fromOpaque(context)
        .takeUnretainedValue()
        .didMatch(device: device, result: result)
}

private func genericIdentifyDeviceRemoved(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<GenericHIDDeviceIdentifierMonitor>.fromOpaque(context)
        .takeUnretainedValue()
        .didRemove(device: device, result: result)
}

private func genericIdentifyInputValueReceived(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard let context else { return }
    Unmanaged<GenericHIDDeviceIdentifierMonitor>.fromOpaque(context)
        .takeUnretainedValue()
        .didReceiveValue(result: result, value: value)
}

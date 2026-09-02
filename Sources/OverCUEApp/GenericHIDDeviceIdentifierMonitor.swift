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

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
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
    }

    fileprivate func didMatch(device: IOHIDDevice, result: IOReturn) {
        guard result == kIOReturnSuccess else { return }
        _ = registerInterface(device)
        publishDevices()
    }

    fileprivate func didRemove(device: IOHIDDevice, result: IOReturn) {
        guard result == kIOReturnSuccess else { return }
        let interfaceID = interfaceIdentifier(device)
        guard let groupKey = groupKeyByInterfaceID.removeValue(forKey: interfaceID),
              var group = groups[groupKey]
        else { return }

        group.interfaceIDs.remove(interfaceID)
        if group.interfaceIDs.isEmpty {
            groups.removeValue(forKey: groupKey)
        } else {
            groups[groupKey] = group
        }
        publishDevices()
    }

    fileprivate func didReceiveValue(result: IOReturn, value: IOHIDValue) {
        guard result == kIOReturnSuccess, !didIdentify else { return }

        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        guard let descriptor = registerInterface(device) else { return }

        let reportID = UInt32(IOHIDElementGetReportID(element))
        let input = GenericHIDInputDescriptor(
            usagePage: IOHIDElementGetUsagePage(element),
            usage: IOHIDElementGetUsage(element),
            reportID: reportID == 0 ? nil : reportID,
            collectionPath: collectionPath(for: element)
        )
        let runtimeElement = GenericHIDRuntimeElementDescriptor(
            input: input,
            cookie: UInt64(IOHIDElementGetCookie(element)),
            isRelative: IOHIDElementIsRelative(element),
            matchingElementCount: matchingElementCount(for: element, input: input)
        )
        guard runtimeElement.persistentInput != nil,
              let event = GenericHIDEventNormalizer.normalize(
                  GenericHIDRawValue(
                      sessionDeviceID: descriptor.sessionIdentifier,
                      element: runtimeElement,
                      value: IOHIDValueGetIntegerValue(value)
                  )
              )
        else { return }

        switch event.phase {
        case .pressed:
            identify(descriptor)
        case let .relative(delta) where delta != 0:
            identify(descriptor)
        case .relative, .released, .absolute:
            break
        }
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
        groups.values
            .map(\.representative)
            .sorted { $0.sessionIdentifier < $1.sessionIdentifier }
    }

    @discardableResult
    private func registerInterface(_ device: IOHIDDevice) -> HIDPhysicalDeviceDescriptor? {
        guard let rawDescriptor = candidateDescriptor(for: device),
              let persistentIdentifier = rawDescriptor.persistentIdentifier
        else { return nil }

        let interfaceID = interfaceIdentifier(device)
        if let existingKey = groupKeyByInterfaceID[interfaceID],
           let existing = groups[existingKey] {
            return existing.representative
        }

        let groupKey = LiveGroupKey(
            persistentIdentifier: persistentIdentifier,
            connectionQualifier: connectionQualifier(
                descriptor: rawDescriptor,
                interfaceID: interfaceID
            )
        )
        groupKeyByInterfaceID[interfaceID] = groupKey

        if var group = groups[groupKey] {
            group.interfaceIDs.insert(interfaceID)
            groups[groupKey] = group
            return group.representative
        }

        groups[groupKey] = LiveGroup(
            representative: rawDescriptor,
            interfaceIDs: [interfaceID]
        )
        return rawDescriptor
    }

    private func candidateDescriptor(for device: IOHIDDevice) -> HIDPhysicalDeviceDescriptor? {
        let vendorID = propertyNumber(device, kIOHIDVendorIDKey)?.intValue ?? 0
        let productID = propertyNumber(device, kIOHIDProductIDKey)?.intValue ?? 0
        guard vendorID != 0,
              productID != 0,
              !(vendorID == GenericHIDDeviceIdentifierHardware.ack05VendorID
                  && productID == GenericHIDDeviceIdentifierHardware.ack05ProductID),
              let serialNumber = (property(device, kIOHIDSerialNumberKey) as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !serialNumber.isEmpty
        else { return nil }

        return HIDPhysicalDeviceDescriptor(
            kind: .genericHID,
            vendorID: vendorID,
            productID: productID,
            serialNumber: serialNumber,
            productName: property(device, kIOHIDProductKey) as? String,
            manufacturerName: property(device, kIOHIDManufacturerKey) as? String,
            transport: property(device, kIOHIDTransportKey) as? String,
            locationID: propertyNumber(device, kIOHIDLocationIDKey)?.uint32Value,
            transportIdentifier: String(interfaceIdentifier(device), radix: 16)
        )
    }

    private func connectionQualifier(
        descriptor: HIDPhysicalDeviceDescriptor,
        interfaceID: UInt
    ) -> String {
        if let locationID = descriptor.locationID, locationID != 0 {
            return String(format: "location:%08X", locationID)
        }
        // Without topology evidence, do not collapse multiple IOHID interfaces
        // only because they report the same serial. Keeping them separate makes
        // duplicate persistent identities fail closed as ambiguous.
        return "interface:\(String(interfaceID, radix: 16))"
    }

    private func interfaceIdentifier(_ device: IOHIDDevice) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    }

    private func collectionPath(for element: IOHIDElement) -> [HIDUsage] {
        var path: [HIDUsage] = []
        var parent = IOHIDElementGetParent(element)
        while let current = parent {
            path.append(
                HIDUsage(
                    page: IOHIDElementGetUsagePage(current),
                    usage: IOHIDElementGetUsage(current)
                )
            )
            parent = IOHIDElementGetParent(current)
        }
        return path.reversed()
    }

    private func matchingElementCount(
        for element: IOHIDElement,
        input: GenericHIDInputDescriptor
    ) -> Int? {
        let device = IOHIDElementGetDevice(element)
        guard let elements = IOHIDDeviceCopyMatchingElements(
            device,
            nil,
            IOOptionBits(kIOHIDOptionsTypeNone)
        ) as? [IOHIDElement] else { return nil }

        return elements.filter { candidate in
            let reportID = UInt32(IOHIDElementGetReportID(candidate))
            return GenericHIDInputDescriptor(
                usagePage: IOHIDElementGetUsagePage(candidate),
                usage: IOHIDElementGetUsage(candidate),
                reportID: reportID == 0 ? nil : reportID,
                collectionPath: collectionPath(for: candidate)
            ) == input
        }.count
    }

    private func property(_ device: IOHIDDevice, _ key: String) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }

    private func propertyNumber(_ device: IOHIDDevice, _ key: String) -> NSNumber? {
        property(device, key) as? NSNumber
    }
}

private func genericIdentifyDeviceMatched(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<GenericHIDDeviceIdentifierMonitor>.fromOpaque(context).takeUnretainedValue()
        .didMatch(device: device, result: result)
}

private func genericIdentifyDeviceRemoved(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<GenericHIDDeviceIdentifierMonitor>.fromOpaque(context).takeUnretainedValue()
        .didRemove(device: device, result: result)
}

private func genericIdentifyInputValueReceived(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard let context else { return }
    Unmanaged<GenericHIDDeviceIdentifierMonitor>.fromOpaque(context).takeUnretainedValue()
        .didReceiveValue(result: result, value: value)
}

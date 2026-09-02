import Foundation

/// ACK05-specific binding path.
///
/// Verified BLE units expose no serial number, so PhysicalDeviceUniqueID is used
/// as a pairing identity. Verified USB units expose neither a useful serial nor
/// PhysicalDeviceUniqueID, so the stable USB topology location is used as a slot
/// identity. A USB slot identifies the hub/port position rather than the physical
/// ACK05 unit; moving the controller to another port intentionally requires a new
/// binding for that slot.
public enum ACK05PairedDeviceBindingManager {
    @discardableResult
    public static func rebind(
        logicalDeviceID: String,
        to device: HIDPhysicalDeviceDescriptor,
        among connectedDevices: [HIDPhysicalDeviceDescriptor],
        configuration: inout OverCUEConfiguration
    ) throws -> OverCUEPhysicalDeviceBinding {
        guard configuration.logicalDevices[logicalDeviceID] != nil else {
            throw HIDDeviceBindingManagementError.unknownLogicalDevice(logicalDeviceID)
        }
        guard device.kind == .ack05,
              let bindingIdentifier = device.ack05BindingIdentifier,
              let persistentIdentifier = device.persistentIdentifier
        else {
            throw HIDDeviceBindingManagementError.missingPersistentIdentity(
                device.sessionIdentifier
            )
        }
        guard connectedDevices.contains(where: {
            $0.sessionIdentifier == device.sessionIdentifier
        }) else {
            throw HIDDeviceBindingManagementError.deviceNotConnected(device.sessionIdentifier)
        }

        let matchingSessions = Set(connectedDevices.compactMap { candidate in
            candidate.persistentIdentifier == persistentIdentifier
                ? candidate.sessionIdentifier
                : nil
        })
        guard matchingSessions == Set([device.sessionIdentifier]) else {
            throw HIDDeviceBindingManagementError.ambiguousPersistentIdentity(
                persistentIdentifier
            )
        }

        let otherLogicalDeviceIDs = Array(Set(configuration.physicalDeviceBindings.compactMap {
            $0.matches(device) && $0.logicalDeviceID != logicalDeviceID
                ? $0.logicalDeviceID
                : nil
        })).sorted()
        guard otherLogicalDeviceIDs.isEmpty else {
            throw HIDDeviceBindingManagementError.alreadyBound(
                logicalDeviceIDs: otherLogicalDeviceIDs
            )
        }

        configuration.physicalDeviceBindings.removeAll {
            $0.logicalDeviceID == logicalDeviceID
        }
        let binding = OverCUEPhysicalDeviceBinding(
            logicalDeviceID: logicalDeviceID,
            kind: .ack05,
            vendorID: device.vendorID,
            productID: device.productID,
            serialNumber: device.serialNumber,
            lastKnownLocationID: device.locationID,
            legacyDeviceIdentifier: bindingIdentifier
        )
        configuration.physicalDeviceBindings.append(binding)
        return binding
    }
}

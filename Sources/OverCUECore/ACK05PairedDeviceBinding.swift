import Foundation

/// ACK05-specific binding path backed by macOS PhysicalDeviceUniqueID.
///
/// The verified ACK05 units expose no serial number. PhysicalDeviceUniqueID is
/// stable across controller power cycles and Mac restarts, but changes when the
/// Bluetooth pairing is removed and recreated. Therefore this manager treats
/// that value as a persistent pairing identity and intentionally requires
/// Identify/Rebind after re-pairing.
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
              let pairingIdentifier = device.ack05PairingIdentifier,
              let persistentIdentifier = device.persistentIdentifier
        else {
            throw HIDDeviceBindingManagementError.missingPersistentIdentity(
                device.sessionIdentifier
            )
        }
        guard let connectedDevice = connectedDevices.first(where: {
            $0.sessionIdentifier == device.sessionIdentifier
        }), connectedDevice == device else {
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
            legacyDeviceIdentifier: pairingIdentifier
        )
        configuration.physicalDeviceBindings.append(binding)
        return binding
    }
}

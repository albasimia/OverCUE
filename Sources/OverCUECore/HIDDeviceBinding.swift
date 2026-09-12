import Foundation

public enum HIDDeviceKind: String, Codable, Equatable, Sendable {
    case ack05
    case genericHID
}

public struct HIDPhysicalDeviceDescriptor: Equatable, Sendable {
    public let kind: HIDDeviceKind
    public let vendorID: Int
    public let productID: Int
    public let serialNumber: String?
    public let productName: String?
    public let manufacturerName: String?
    public let transport: String?
    public let locationID: UInt32?
    public let transportIdentifier: String
    public let legacyIdentifiers: Set<String>

    public init(
        kind: HIDDeviceKind,
        vendorID: Int,
        productID: Int,
        serialNumber: String? = nil,
        productName: String? = nil,
        manufacturerName: String? = nil,
        transport: String? = nil,
        locationID: UInt32? = nil,
        transportIdentifier: String,
        legacyIdentifiers: Set<String> = []
    ) {
        self.kind = kind
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber?.nilIfBlank
        self.productName = productName?.nilIfBlank
        self.manufacturerName = manufacturerName?.nilIfBlank
        self.transport = transport?.nilIfBlank
        self.locationID = locationID
        self.transportIdentifier = transportIdentifier
        self.legacyIdentifiers = legacyIdentifiers
    }

    /// ACK05 has no USB/BLE serial number on the verified hardware. macOS exposes
    /// PhysicalDeviceUniqueID as a UUID that survived ACK05 power cycles and a Mac
    /// restart, while changing after Bluetooth re-pairing. Treat it as a stable
    /// *pairing* identity, not an immutable physical-device serial.
    public var ack05PairingIdentifier: String? {
        guard kind == .ack05 else { return nil }
        return legacyIdentifiers
            .filter { UUID(uuidString: $0) != nil }
            .sorted()
            .first
    }

    /// The verified ACK05 USB descriptor exposes no useful serial number or
    /// PhysicalDeviceUniqueID. Its IOHID interfaces share a non-zero locationID,
    /// and that value survived disconnect/reconnect in the same hub port while
    /// changing when the ACK05 moved to another port. Treat this as a USB *slot*
    /// identity: it identifies the topology position, not the physical controller.
    public var ack05USBSlotIdentifier: String? {
        guard kind == .ack05,
              transport?.caseInsensitiveCompare("USB") == .orderedSame,
              let locationID,
              locationID != 0
        else { return nil }
        return String(format: "usb-slot:%08X", locationID)
    }

    public var ack05BindingIdentifier: String? {
        ack05PairingIdentifier ?? ack05USBSlotIdentifier
    }

    public var persistentIdentifier: String? {
        if let serialNumber {
            return String(
                format: "%@:%04X:%04X:serial:%@",
                kind.rawValue,
                vendorID,
                productID,
                serialNumber
            )
        }
        if let pairingIdentifier = ack05PairingIdentifier {
            return String(
                format: "%@:%04X:%04X:pairing:%@",
                kind.rawValue,
                vendorID,
                productID,
                pairingIdentifier
            )
        }
        if let usbSlotIdentifier = ack05USBSlotIdentifier {
            return String(
                format: "%@:%04X:%04X:%@",
                kind.rawValue,
                vendorID,
                productID,
                usbSlotIdentifier
            )
        }
        return nil
    }

    public var sessionIdentifier: String {
        let runtimeIdentifier = ack05USBSlotIdentifier ?? transportIdentifier
        return String(
            format: "%@:%04X:%04X:session:%@",
            kind.rawValue,
            vendorID,
            productID,
            runtimeIdentifier
        )
    }
}

public enum PhysicalDeviceBindingResolution: Equatable, Sendable {
    case unbound
    case bound(logicalDeviceID: String)
    case ambiguous(logicalDeviceIDs: [String])
}

/// Preset-independent OverCUE commands owned by one Logical Device.
/// rekordbox actions remain in the Profile/Preset mapping; only internal
/// OverCUE Control actions are persisted here.
public struct OverCUEControlMapping: Codable, Equatable, Sendable {
    public var keyMap: [String: String]
    public var chordMap: [String: String]
    public var dialMap: [String: String]
    public var dialChordMap: [String: String]

    public init(
        keyMap: [String: String] = [:],
        chordMap: [String: String] = [:],
        dialMap: [String: String] = [:],
        dialChordMap: [String: String] = [:]
    ) {
        self.keyMap = keyMap
        self.chordMap = chordMap
        self.dialMap = dialMap
        self.dialChordMap = dialChordMap
    }

    public var isEmpty: Bool {
        keyMap.isEmpty && chordMap.isEmpty && dialMap.isEmpty && dialChordMap.isEmpty
    }
}

public struct OverCUELogicalDevice: Codable, Equatable, Sendable {
    public var name: String
    public var profileName: String
    public var controlMapping: OverCUEControlMapping

    public init(
        name: String,
        profileName: String,
        controlMapping: OverCUEControlMapping = OverCUEControlMapping()
    ) {
        self.name = name
        self.profileName = profileName
        self.controlMapping = controlMapping
    }

    private enum CodingKeys: String, CodingKey {
        case name, profileName, controlMapping
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        profileName = try container.decode(String.self, forKey: .profileName)
        controlMapping = try container.decodeIfPresent(
            OverCUEControlMapping.self,
            forKey: .controlMapping
        ) ?? OverCUEControlMapping()
    }
}

public struct OverCUEPhysicalDeviceBinding: Codable, Equatable, Sendable {
    public var logicalDeviceID: String
    public var kind: HIDDeviceKind
    public var vendorID: Int
    public var productID: Int
    public var serialNumber: String?
    public var lastKnownLocationID: UInt32?
    public var legacyDeviceIdentifier: String?

    public init(
        logicalDeviceID: String,
        kind: HIDDeviceKind,
        vendorID: Int,
        productID: Int,
        serialNumber: String? = nil,
        lastKnownLocationID: UInt32? = nil,
        legacyDeviceIdentifier: String? = nil
    ) {
        self.logicalDeviceID = logicalDeviceID
        self.kind = kind
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber?.nilIfBlank
        self.lastKnownLocationID = lastKnownLocationID
        self.legacyDeviceIdentifier = legacyDeviceIdentifier?.nilIfBlank
    }

    public func matches(_ device: HIDPhysicalDeviceDescriptor) -> Bool {
        guard kind == device.kind,
              vendorID == device.vendorID,
              productID == device.productID
        else { return false }

        if let serialNumber {
            return serialNumber == device.serialNumber
        }
        if kind == .ack05,
           let legacyDeviceIdentifier,
           let bindingIdentifier = device.ack05BindingIdentifier {
            return legacyDeviceIdentifier == bindingIdentifier
        }
        if let legacyDeviceIdentifier {
            guard !legacyDeviceIdentifier.lowercased().hasPrefix("location:") else {
                return false
            }
            return device.legacyIdentifiers.contains(legacyDeviceIdentifier)
        }
        return false
    }

    public func isLocationHint(for device: HIDPhysicalDeviceDescriptor) -> Bool {
        guard kind == device.kind,
              vendorID == device.vendorID,
              productID == device.productID,
              let lastKnownLocationID,
              let locationID = device.locationID
        else { return false }
        return lastKnownLocationID == locationID
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

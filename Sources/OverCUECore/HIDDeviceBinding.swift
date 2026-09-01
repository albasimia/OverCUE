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
    public let locationID: UInt32?
    public let transportIdentifier: String
    public let legacyIdentifiers: Set<String>

    public init(
        kind: HIDDeviceKind,
        vendorID: Int,
        productID: Int,
        serialNumber: String? = nil,
        locationID: UInt32? = nil,
        transportIdentifier: String,
        legacyIdentifiers: Set<String> = []
    ) {
        self.kind = kind
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber?.nilIfBlank
        self.locationID = locationID
        self.transportIdentifier = transportIdentifier
        self.legacyIdentifiers = legacyIdentifiers
    }

    public var persistentIdentifier: String? {
        guard let serialNumber else { return nil }
        return String(format: "%@:%04X:%04X:serial:%@", kind.rawValue, vendorID, productID, serialNumber)
    }

    public var sessionIdentifier: String {
        persistentIdentifier ?? String(
            format: "%@:%04X:%04X:session:%@",
            kind.rawValue,
            vendorID,
            productID,
            transportIdentifier
        )
    }
}

public struct OverCUELogicalDevice: Codable, Equatable, Sendable {
    public var name: String
    public var profileName: String

    public init(name: String, profileName: String) {
        self.name = name
        self.profileName = profileName
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
        if let legacyDeviceIdentifier {
            return device.legacyIdentifiers.contains(legacyDeviceIdentifier)
        }
        return false
    }

    public func isLocationHint(for device: HIDPhysicalDeviceDescriptor) -> Bool {
        kind == device.kind
            && vendorID == device.vendorID
            && productID == device.productID
            && serialNumber == nil
            && lastKnownLocationID != nil
            && lastKnownLocationID == device.locationID
    }
}

public struct DeviceScopedStateStore<State> {
    private var states: [String: State] = [:]

    public init() {}

    public var count: Int { states.count }

    public mutating func state(
        for deviceID: String,
        create: () throws -> State
    ) rethrows -> State {
        if let state = states[deviceID] { return state }
        let state = try create()
        states[deviceID] = state
        return state
    }

    @discardableResult
    public mutating func removeState(for deviceID: String) -> State? {
        states.removeValue(forKey: deviceID)
    }

    public mutating func withState<Result>(
        for deviceID: String,
        create: () throws -> State,
        _ operation: (inout State) throws -> Result
    ) rethrows -> Result {
        var state = try self.state(for: deviceID, create: create)
        defer { states[deviceID] = state }
        return try operation(&state)
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

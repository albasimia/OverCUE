import Foundation

public struct HIDDeviceRegistryEntry: Equatable, Sendable {
    public let descriptor: HIDPhysicalDeviceDescriptor
    public let bindingResolution: PhysicalDeviceBindingResolution
    public let locationHintLogicalDeviceIDs: [String]
    public let profileName: String

    public init(
        descriptor: HIDPhysicalDeviceDescriptor,
        bindingResolution: PhysicalDeviceBindingResolution,
        locationHintLogicalDeviceIDs: [String],
        profileName: String
    ) {
        self.descriptor = descriptor
        self.bindingResolution = bindingResolution
        self.locationHintLogicalDeviceIDs = locationHintLogicalDeviceIDs
        self.profileName = profileName
    }
}

public struct HIDDeviceRegistry: Equatable, Sendable {
    private var devicesBySessionID: [String: HIDPhysicalDeviceDescriptor] = [:]

    public init() {}

    public var count: Int { devicesBySessionID.count }

    public var connectedDevices: [HIDPhysicalDeviceDescriptor] {
        devicesBySessionID.values.sorted { $0.sessionIdentifier < $1.sessionIdentifier }
    }

    @discardableResult
    public mutating func deviceConnected(_ device: HIDPhysicalDeviceDescriptor) -> Bool {
        let previous = devicesBySessionID.updateValue(device, forKey: device.sessionIdentifier)
        return previous != device
    }

    @discardableResult
    public mutating func deviceDisconnected(sessionIdentifier: String) -> HIDPhysicalDeviceDescriptor? {
        devicesBySessionID.removeValue(forKey: sessionIdentifier)
    }

    public func device(sessionIdentifier: String) -> HIDPhysicalDeviceDescriptor? {
        devicesBySessionID[sessionIdentifier]
    }

    public func entries(configuration: OverCUEConfiguration) -> [HIDDeviceRegistryEntry] {
        let connected = connectedDevices
        return connected.map { device in
            let resolution = configuration.bindingResolution(for: device, among: connected)
            let locationHints = Array(Set(configuration.physicalDeviceBindings.compactMap {
                $0.isLocationHint(for: device) ? $0.logicalDeviceID : nil
            })).sorted()
            let profileName: String
            if case let .bound(logicalDeviceID) = resolution,
               let logicalDevice = configuration.logicalDevices[logicalDeviceID],
               configuration.profiles[logicalDevice.profileName] != nil {
                profileName = logicalDevice.profileName
            } else {
                profileName = configuration.defaultProfile
            }
            return HIDDeviceRegistryEntry(
                descriptor: device,
                bindingResolution: resolution,
                locationHintLogicalDeviceIDs: locationHints,
                profileName: profileName
            )
        }
    }
}

public enum HIDIdentifyCancellationReason: Equatable, Sendable {
    case cancelled
    case sourceDisconnected
    case noCandidatesRemain
}

public enum HIDIdentifyState: Equatable, Sendable {
    case idle
    case listening(candidateSessionIDs: Set<String>?)
    case identified(sessionIdentifier: String)
    case cancelled(HIDIdentifyCancellationReason)
}

public enum HIDIdentifyObservation: Equatable, Sendable {
    case ignored
    case identified(sessionIdentifier: String)
}

public struct HIDIdentifySession: Equatable, Sendable {
    public private(set) var state: HIDIdentifyState = .idle

    public init() {}

    public mutating func begin(candidateSessionIDs: Set<String>? = nil) {
        state = .listening(candidateSessionIDs: candidateSessionIDs)
    }

    public mutating func observeInput(from sessionIdentifier: String) -> HIDIdentifyObservation {
        guard case let .listening(candidateSessionIDs) = state else { return .ignored }
        if let candidateSessionIDs, !candidateSessionIDs.contains(sessionIdentifier) {
            return .ignored
        }
        state = .identified(sessionIdentifier: sessionIdentifier)
        return .identified(sessionIdentifier: sessionIdentifier)
    }

    public mutating func deviceDisconnected(_ sessionIdentifier: String) {
        switch state {
        case let .identified(source) where source == sessionIdentifier:
            state = .cancelled(.sourceDisconnected)
        case let .listening(candidateSessionIDs?):
            var remaining = candidateSessionIDs
            remaining.remove(sessionIdentifier)
            state = remaining.isEmpty
                ? .cancelled(.noCandidatesRemain)
                : .listening(candidateSessionIDs: remaining)
        default:
            break
        }
    }

    public mutating func cancel() {
        state = .cancelled(.cancelled)
    }
}

public enum HIDDeviceBindingManagementError: Error, Equatable, LocalizedError, Sendable {
    case unknownLogicalDevice(String)
    case deviceNotConnected(String)
    case missingPersistentIdentity(String)
    case ambiguousPersistentIdentity(String)
    case alreadyBound(logicalDeviceIDs: [String])

    public var errorDescription: String? {
        switch self {
        case let .unknownLogicalDevice(identifier):
            return "Unknown Logical Device '\(identifier)'."
        case let .deviceNotConnected(sessionIdentifier):
            return "Physical Device session '\(sessionIdentifier)' is no longer connected. Identify it again."
        case let .missingPersistentIdentity(sessionIdentifier):
            return "Physical Device '\(sessionIdentifier)' has no verified persistent identity."
        case let .ambiguousPersistentIdentity(identifier):
            return "Persistent Physical Device identity '\(identifier)' is ambiguous."
        case let .alreadyBound(logicalDeviceIDs):
            return "Physical Device is already bound to: \(logicalDeviceIDs.joined(separator: ", "))."
        }
    }
}

public enum HIDDeviceBindingManager {
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
        guard let connectedDevice = connectedDevices.first(where: {
            $0.sessionIdentifier == device.sessionIdentifier
        }), connectedDevice == device else {
            throw HIDDeviceBindingManagementError.deviceNotConnected(device.sessionIdentifier)
        }
        guard let persistentIdentifier = device.persistentIdentifier,
              let serialNumber = device.serialNumber
        else {
            throw HIDDeviceBindingManagementError.missingPersistentIdentity(
                device.sessionIdentifier
            )
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
            kind: device.kind,
            vendorID: device.vendorID,
            productID: device.productID,
            serialNumber: serialNumber,
            lastKnownLocationID: device.locationID
        )
        configuration.physicalDeviceBindings.append(binding)
        return binding
    }

    @discardableResult
    public static func forgetBinding(
        logicalDeviceID: String,
        device: HIDPhysicalDeviceDescriptor,
        configuration: inout OverCUEConfiguration
    ) -> Int {
        let previousCount = configuration.physicalDeviceBindings.count
        configuration.physicalDeviceBindings.removeAll {
            $0.logicalDeviceID == logicalDeviceID && $0.matches(device)
        }
        return previousCount - configuration.physicalDeviceBindings.count
    }

    @discardableResult
    public static func forgetBindings(
        logicalDeviceID: String,
        configuration: inout OverCUEConfiguration
    ) -> Int {
        let previousCount = configuration.physicalDeviceBindings.count
        configuration.physicalDeviceBindings.removeAll {
            $0.logicalDeviceID == logicalDeviceID
        }
        return previousCount - configuration.physicalDeviceBindings.count
    }
}

public enum OverCUEConfigurationChangedNotification {
    public static let name = Notification.Name("com.overcue.configuration-changed")
    public static let sourceProcessIdentifierKey = "sourceProcessIdentifier"

    public static func post() {
        DistributedNotificationCenter.default().postNotificationName(
            name,
            object: nil,
            userInfo: [
                sourceProcessIdentifierKey: Int(ProcessInfo.processInfo.processIdentifier),
            ],
            deliverImmediately: true
        )
    }
}

public enum HIDDeviceManagementFileStore {
    @discardableResult
    public static func rebind(
        logicalDeviceID: String,
        to device: HIDPhysicalDeviceDescriptor,
        among connectedDevices: [HIDPhysicalDeviceDescriptor],
        at configurationURL: URL
    ) throws -> OverCUEConfiguration {
        let configuration = try OverCUEConfigurationFileStore.updateCurrent(
            at: configurationURL
        ) { latest in
            try HIDDeviceBindingManager.rebind(
                logicalDeviceID: logicalDeviceID,
                to: device,
                among: connectedDevices,
                configuration: &latest
            )
        }
        OverCUEConfigurationChangedNotification.post()
        return configuration
    }

    @discardableResult
    public static func forgetBindings(
        logicalDeviceID: String,
        at configurationURL: URL
    ) throws -> OverCUEConfiguration {
        let configuration = try OverCUEConfigurationFileStore.updateCurrent(
            at: configurationURL
        ) { latest in
            guard latest.logicalDevices[logicalDeviceID] != nil else {
                throw HIDDeviceBindingManagementError.unknownLogicalDevice(logicalDeviceID)
            }
            _ = HIDDeviceBindingManager.forgetBindings(
                logicalDeviceID: logicalDeviceID,
                configuration: &latest
            )
        }
        OverCUEConfigurationChangedNotification.post()
        return configuration
    }

    @discardableResult
    public static func forgetBinding(
        logicalDeviceID: String,
        device: HIDPhysicalDeviceDescriptor,
        at configurationURL: URL
    ) throws -> OverCUEConfiguration {
        let configuration = try OverCUEConfigurationFileStore.updateCurrent(
            at: configurationURL
        ) { latest in
            guard latest.logicalDevices[logicalDeviceID] != nil else {
                throw HIDDeviceBindingManagementError.unknownLogicalDevice(logicalDeviceID)
            }
            _ = HIDDeviceBindingManager.forgetBinding(
                logicalDeviceID: logicalDeviceID,
                device: device,
                configuration: &latest
            )
        }
        OverCUEConfigurationChangedNotification.post()
        return configuration
    }
}

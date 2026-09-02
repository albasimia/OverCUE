import Foundation
import OverCUECore

struct LogicalDeviceRow: Identifiable, Equatable {
    let id: String
    var name: String
    var profileName: String
    var binding: OverCUEPhysicalDeviceBinding?
    var isConnected: Bool

    var pairingIdentifier: String? {
        guard binding?.kind == .ack05 else { return nil }
        return binding?.legacyDeviceIdentifier
    }
}

private final class DeviceManagementObserverToken: @unchecked Sendable {
    let value: any NSObjectProtocol

    init(_ value: any NSObjectProtocol) {
        self.value = value
    }
}

@MainActor
final class DeviceManagementModel: ObservableObject {
    enum IdentifyPurpose: Equatable {
        case addACK05
        case addGenericHID
        case rebind(logicalDeviceID: String, kind: HIDDeviceKind)
    }

    @Published private(set) var devices: [LogicalDeviceRow] = []
    @Published private(set) var profileNames: [String] = []
    @Published var selectedLogicalDeviceID: String?
    @Published private(set) var identifyPurpose: IdentifyPurpose?
    @Published private(set) var identifyCandidateCount = 0
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private var configuration: OverCUEConfiguration = .defaultValue
    private var connectedLogicalDeviceIDs: Set<String> = []
    private var ack05Monitor: ACK05DeviceIdentifierMonitor?
    private var genericHIDMonitor: GenericHIDDeviceIdentifierMonitor?
    private var configurationObserver: DeviceManagementObserverToken?
    private var runtimeObserver: DeviceManagementObserverToken?

    init() {
        configurationObserver = DeviceManagementObserverToken(
            DistributedNotificationCenter.default().addObserver(
                forName: OverCUEConfigurationChangedNotification.name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.reload() }
            }
        )
        runtimeObserver = DeviceManagementObserverToken(
            DistributedNotificationCenter.default().addObserver(
                forName: OverCUERuntimeStatusNotification.name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let logicalDeviceID = notification.userInfo?[
                    OverCUERuntimeStatusNotification.logicalDeviceIDKey
                ] as? String
                let connected = notification.userInfo?[
                    OverCUERuntimeStatusNotification.connectedKey
                ] as? Bool ?? true
                Task { @MainActor in
                    self?.applyRuntimeStatus(
                        logicalDeviceID: logicalDeviceID,
                        connected: connected
                    )
                }
            }
        )
        reload()
    }

    deinit {
        ack05Monitor?.stop()
        genericHIDMonitor?.stop()
        if let configurationObserver {
            DistributedNotificationCenter.default().removeObserver(configurationObserver.value)
        }
        if let runtimeObserver {
            DistributedNotificationCenter.default().removeObserver(runtimeObserver.value)
        }
    }

    var selectedDevice: LogicalDeviceRow? {
        guard let selectedLogicalDeviceID else { return nil }
        return devices.first { $0.id == selectedLogicalDeviceID }
    }

    var isIdentifying: Bool { identifyPurpose != nil }

    func reload() {
        do {
            let latest = try OverCUEConfigurationFileStore.readCurrent(
                at: OverCUEAppConfigurationLocation.url
            )
            configuration = latest
            profileNames = latest.profiles.keys.sorted()
            devices = latest.logicalDevices.map { id, logicalDevice in
                let binding = latest.physicalDeviceBindings.first {
                    $0.logicalDeviceID == id
                }
                return LogicalDeviceRow(
                    id: id,
                    name: logicalDevice.name,
                    profileName: logicalDevice.profileName,
                    binding: binding,
                    isConnected: connectedLogicalDeviceIDs.contains(id)
                )
            }
            .sorted {
                if $0.name.localizedStandardCompare($1.name) != .orderedSame {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.id < $1.id
            }
            if let selectedLogicalDeviceID,
               devices.contains(where: { $0.id == selectedLogicalDeviceID }) {
                self.selectedLogicalDeviceID = selectedLogicalDeviceID
            } else {
                selectedLogicalDeviceID = devices.first?.id
            }
            errorMessage = nil
        } catch {
            if !FileManager.default.fileExists(atPath: OverCUEAppConfigurationLocation.url.path) {
                configuration = .defaultValue
                profileNames = configuration.profiles.keys.sorted()
                devices = []
                errorMessage = nil
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func beginAddACK05() throws {
        try beginIdentify(.addACK05, kind: .ack05)
    }

    func beginAddGenericHID() throws {
        try beginIdentify(.addGenericHID, kind: .genericHID)
    }

    func beginRebind(
        logicalDeviceID: String,
        kind requestedKind: HIDDeviceKind? = nil
    ) throws {
        let currentKind = configuration.physicalDeviceBindings.first {
            $0.logicalDeviceID == logicalDeviceID
        }?.kind
        let kind = requestedKind ?? currentKind ?? .ack05
        try beginIdentify(
            .rebind(logicalDeviceID: logicalDeviceID, kind: kind),
            kind: kind
        )
    }

    func cancelIdentify() {
        stopIdentifierMonitors()
        identifyPurpose = nil
        identifyCandidateCount = 0
        statusMessage = nil
    }

    func rename(logicalDeviceID: String, name rawName: String) throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw NSError(
                domain: "OverCUE.DeviceManagement",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: L10n.text("devices.error.name")]
            )
        }
        _ = try OverCUEConfigurationFileStore.updateCurrent(
            at: OverCUEAppConfigurationLocation.url,
            fallback: configuration
        ) { latest in
            guard var device = latest.logicalDevices[logicalDeviceID] else {
                throw HIDDeviceBindingManagementError.unknownLogicalDevice(logicalDeviceID)
            }
            device.name = name
            latest.logicalDevices[logicalDeviceID] = device
        }
        OverCUEConfigurationChangedNotification.post()
        reload()
    }

    func assignProfile(logicalDeviceID: String, profileName: String) throws {
        _ = try OverCUEConfigurationFileStore.updateCurrent(
            at: OverCUEAppConfigurationLocation.url,
            fallback: configuration
        ) { latest in
            guard let profile = latest.profiles[profileName] else {
                throw NSError(
                    domain: "OverCUE.DeviceManagement",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: L10n.text("devices.error.profile")]
                )
            }
            guard var device = latest.logicalDevices[logicalDeviceID] else {
                throw HIDDeviceBindingManagementError.unknownLogicalDevice(logicalDeviceID)
            }
            device.profileName = profileName
            latest.logicalDevices[logicalDeviceID] = device

            // Group Preset membership survives a Profile change, but the Preset
            // reference must belong to the new Profile. Fall back to its first
            // Preset instead of leaving a dangling reference.
            if let fallbackPresetID = profile.orderedPresetGroups.first?.id {
                for groupPresetIndex in latest.groupPresets.indices {
                    guard let assignedID = latest.groupPresets[groupPresetIndex]
                        .devicePresetAssignments[logicalDeviceID]
                    else { continue }
                    if profile.presetGroup(id: assignedID) == nil {
                        latest.groupPresets[groupPresetIndex]
                            .devicePresetAssignments[logicalDeviceID] = fallbackPresetID
                    }
                }
            } else {
                for groupPresetIndex in latest.groupPresets.indices {
                    latest.groupPresets[groupPresetIndex]
                        .devicePresetAssignments.removeValue(forKey: logicalDeviceID)
                }
            }
        }
        OverCUEConfigurationChangedNotification.post()
        reload()
    }

    func forgetBinding(logicalDeviceID: String) throws {
        _ = try HIDDeviceManagementFileStore.forgetBindings(
            logicalDeviceID: logicalDeviceID,
            at: OverCUEAppConfigurationLocation.url
        )
        connectedLogicalDeviceIDs.remove(logicalDeviceID)
        statusMessage = L10n.text("devices.message.forgotten")
        reload()
    }

    private func beginIdentify(_ purpose: IdentifyPurpose, kind: HIDDeviceKind) throws {
        cancelIdentify()
        errorMessage = nil
        statusMessage = L10n.text("devices.identify.prompt")
        identifyPurpose = purpose

        let devicesChanged: ([HIDPhysicalDeviceDescriptor]) -> Void = { [weak self] devices in
            Task { @MainActor in self?.identifyCandidateCount = devices.count }
        }
        let identified: (
            HIDPhysicalDeviceDescriptor,
            [HIDPhysicalDeviceDescriptor]
        ) -> Void = { [weak self] descriptor, connectedDevices in
            Task { @MainActor in
                self?.finishIdentify(
                    descriptor: descriptor,
                    connectedDevices: connectedDevices
                )
            }
        }

        do {
            switch kind {
            case .ack05:
                let monitor = ACK05DeviceIdentifierMonitor()
                monitor.onDevicesChanged = devicesChanged
                monitor.onIdentified = identified
                try monitor.start()
                ack05Monitor = monitor
            case .genericHID:
                let monitor = GenericHIDDeviceIdentifierMonitor()
                monitor.onDevicesChanged = devicesChanged
                monitor.onIdentified = identified
                try monitor.start()
                genericHIDMonitor = monitor
            }
        } catch {
            stopIdentifierMonitors()
            identifyPurpose = nil
            statusMessage = nil
            throw error
        }
    }

    private func finishIdentify(
        descriptor: HIDPhysicalDeviceDescriptor,
        connectedDevices: [HIDPhysicalDeviceDescriptor]
    ) {
        guard let purpose = identifyPurpose else { return }
        do {
            let logicalDeviceID: String
            switch purpose {
            case .addACK05:
                logicalDeviceID = try registerACK05(
                    descriptor: descriptor,
                    connectedDevices: connectedDevices
                )
            case .addGenericHID:
                logicalDeviceID = try registerGenericHID(
                    descriptor: descriptor,
                    connectedDevices: connectedDevices
                )
            case let .rebind(existingID, expectedKind):
                guard descriptor.kind == expectedKind else {
                    throw HIDDeviceBindingManagementError.missingPersistentIdentity(
                        descriptor.sessionIdentifier
                    )
                }
                logicalDeviceID = existingID
                _ = try OverCUEConfigurationFileStore.updateCurrent(
                    at: OverCUEAppConfigurationLocation.url,
                    fallback: configuration
                ) { latest in
                    switch descriptor.kind {
                    case .ack05:
                        _ = try ACK05PairedDeviceBindingManager.rebind(
                            logicalDeviceID: existingID,
                            to: descriptor,
                            among: connectedDevices,
                            configuration: &latest
                        )
                    case .genericHID:
                        _ = try HIDDeviceBindingManager.rebind(
                            logicalDeviceID: existingID,
                            to: descriptor,
                            among: connectedDevices,
                            configuration: &latest
                        )
                    }
                }
                OverCUEConfigurationChangedNotification.post()
            }
            selectedLogicalDeviceID = logicalDeviceID
            statusMessage = L10n.text("devices.identify.success")
            errorMessage = nil
            stopIdentifierMonitors()
            identifyPurpose = nil
            identifyCandidateCount = 0
            reload()
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
            stopIdentifierMonitors()
            identifyPurpose = nil
            identifyCandidateCount = 0
        }
    }

    private func registerACK05(
        descriptor: HIDPhysicalDeviceDescriptor,
        connectedDevices: [HIDPhysicalDeviceDescriptor]
    ) throws -> String {
        var createdID = ""
        _ = try OverCUEConfigurationFileStore.updateCurrent(
            at: OverCUEAppConfigurationLocation.url,
            fallback: configuration
        ) { latest in
            let existingResolution = latest.bindingResolution(
                for: descriptor,
                among: connectedDevices
            )
            switch existingResolution {
            case let .bound(logicalDeviceID):
                createdID = logicalDeviceID
                return
            case let .ambiguous(logicalDeviceIDs):
                throw HIDDeviceBindingManagementError.alreadyBound(
                    logicalDeviceIDs: logicalDeviceIDs
                )
            case .unbound:
                break
            }

            let ordinal = latest.logicalDevices.count + 1
            createdID = "logical-\(UUID().uuidString.lowercased())"
            latest.logicalDevices[createdID] = OverCUELogicalDevice(
                name: "ACK05 \(ordinal)",
                profileName: latest.defaultProfile
            )
            do {
                _ = try ACK05PairedDeviceBindingManager.rebind(
                    logicalDeviceID: createdID,
                    to: descriptor,
                    among: connectedDevices,
                    configuration: &latest
                )
            } catch {
                latest.logicalDevices.removeValue(forKey: createdID)
                throw error
            }
        }
        OverCUEConfigurationChangedNotification.post()
        return createdID
    }

    private func registerGenericHID(
        descriptor: HIDPhysicalDeviceDescriptor,
        connectedDevices: [HIDPhysicalDeviceDescriptor]
    ) throws -> String {
        var createdID = ""
        _ = try OverCUEConfigurationFileStore.updateCurrent(
            at: OverCUEAppConfigurationLocation.url,
            fallback: configuration
        ) { latest in
            let existingResolution = latest.bindingResolution(
                for: descriptor,
                among: connectedDevices
            )
            switch existingResolution {
            case let .bound(logicalDeviceID):
                createdID = logicalDeviceID
                return
            case let .ambiguous(logicalDeviceIDs):
                throw HIDDeviceBindingManagementError.alreadyBound(
                    logicalDeviceIDs: logicalDeviceIDs
                )
            case .unbound:
                break
            }

            let ordinal = latest.physicalDeviceBindings.filter { $0.kind == .genericHID }.count + 1
            let baseName = descriptor.productName ?? "Generic HID"
            createdID = "logical-\(UUID().uuidString.lowercased())"
            latest.logicalDevices[createdID] = OverCUELogicalDevice(
                name: "\(baseName) \(ordinal)",
                profileName: latest.defaultProfile
            )
            do {
                _ = try HIDDeviceBindingManager.rebind(
                    logicalDeviceID: createdID,
                    to: descriptor,
                    among: connectedDevices,
                    configuration: &latest
                )
            } catch {
                latest.logicalDevices.removeValue(forKey: createdID)
                throw error
            }
        }
        OverCUEConfigurationChangedNotification.post()
        return createdID
    }

    private func stopIdentifierMonitors() {
        ack05Monitor?.stop()
        ack05Monitor = nil
        genericHIDMonitor?.stop()
        genericHIDMonitor = nil
    }

    private func applyRuntimeStatus(logicalDeviceID: String?, connected: Bool) {
        guard let logicalDeviceID else { return }
        if connected {
            connectedLogicalDeviceIDs.insert(logicalDeviceID)
        } else {
            connectedLogicalDeviceIDs.remove(logicalDeviceID)
        }
        devices = devices.map { row in
            guard row.id == logicalDeviceID else { return row }
            var row = row
            row.isConnected = connected
            return row
        }
    }
}

import Foundation
import OverCUECore

private struct GroupPresetRuntimeStatus: Sendable {
    let mode: RekordboxMappingMode
    let group: Int
    let presetID: String?
    let deviceID: String
    let logicalDeviceID: String?
    let profileName: String
}

private struct AppliedGroupPresetSignature: Equatable, Sendable {
    let groupPresetID: String
    let presetID: String
    let profileName: String
}

private final class GroupPresetRuntimeObserverToken: @unchecked Sendable {
    let value: any NSObjectProtocol

    init(_ value: any NSObjectProtocol) {
        self.value = value
    }
}

/// Applies a Group Preset only when a device first appears or when the Group
/// Preset assignment itself changes. Subsequent Cycle Preset operations remain
/// device-local runtime state and are not snapped back on ordinary status updates.
@MainActor
final class GroupPresetRuntimeCoordinator: ObservableObject {
    @Published private(set) var activeGroupPresetID: String?
    @Published private(set) var activeGroupPresetName: String?

    private var statusesByDeviceID: [String: GroupPresetRuntimeStatus] = [:]
    private var appliedSignaturesByDeviceID: [String: AppliedGroupPresetSignature] = [:]
    private var runtimeObserver: GroupPresetRuntimeObserverToken?
    private var configurationObserver: GroupPresetRuntimeObserverToken?
    private var configurationCache = OverCUEConfigurationReadCache()

    init() {
        runtimeObserver = GroupPresetRuntimeObserverToken(
            DistributedNotificationCenter.default().addObserver(
                forName: OverCUERuntimeStatusNotification.name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let rawMode = notification.userInfo?[OverCUERuntimeStatusNotification.modeKey] as? String
                let group = notification.userInfo?[OverCUERuntimeStatusNotification.groupKey] as? Int
                let presetID = notification.userInfo?[
                    OverCUERuntimeStatusNotification.presetGroupIDKey
                ] as? String
                let deviceID = notification.userInfo?[
                    OverCUERuntimeStatusNotification.deviceIDKey
                ] as? String
                let logicalDeviceID = notification.userInfo?[
                    OverCUERuntimeStatusNotification.logicalDeviceIDKey
                ] as? String
                let profileName = notification.userInfo?[
                    OverCUERuntimeStatusNotification.profileNameKey
                ] as? String
                let connected = notification.userInfo?[
                    OverCUERuntimeStatusNotification.connectedKey
                ] as? Bool ?? true

                guard let rawMode,
                      let mode = RekordboxMappingMode(rawValue: rawMode),
                      let group,
                      let deviceID,
                      let profileName
                else { return }

                let status = GroupPresetRuntimeStatus(
                    mode: mode,
                    group: group,
                    presetID: presetID,
                    deviceID: deviceID,
                    logicalDeviceID: logicalDeviceID,
                    profileName: profileName
                )
                Task { @MainActor in
                    self?.receiveRuntimeStatus(status, connected: connected)
                }
            }
        )
        configurationObserver = GroupPresetRuntimeObserverToken(
            DistributedNotificationCenter.default().addObserver(
                forName: OverCUEConfigurationChangedNotification.name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.configurationChanged() }
            }
        )
        refreshActiveGroupPreset()
    }

    deinit {
        if let runtimeObserver {
            DistributedNotificationCenter.default().removeObserver(runtimeObserver.value)
        }
        if let configurationObserver {
            DistributedNotificationCenter.default().removeObserver(configurationObserver.value)
        }
    }

    private func receiveRuntimeStatus(_ status: GroupPresetRuntimeStatus, connected: Bool) {
        guard connected else {
            statusesByDeviceID.removeValue(forKey: status.deviceID)
            appliedSignaturesByDeviceID.removeValue(forKey: status.deviceID)
            return
        }
        statusesByDeviceID[status.deviceID] = status
        applyIfNeeded(to: status)
    }

    private func configurationChanged() {
        configurationCache.invalidate()
        guard let configuration = try? configurationCache.read(
            at: OverCUEAppConfigurationLocation.url
        ) else {
            activeGroupPresetID = nil
            activeGroupPresetName = nil
            return
        }

        refreshActiveGroupPreset(using: configuration)
        for status in statusesByDeviceID.values {
            if let signature = baselineSignature(for: status, configuration: configuration) {
                if appliedSignaturesByDeviceID[status.deviceID] != signature {
                    applyIfNeeded(to: status, configuration: configuration)
                } else {
                    // Preset order is runtime-significant because the bridge still
                    // addresses mappings by numeric group. Keep the device on its
                    // current stable Preset ID while remapping only that numeric
                    // position, so a temporary Cycle Preset state is not reset to
                    // the Group Preset baseline.
                    synchronizeCurrentPresetPosition(status, configuration: configuration)
                }
            } else {
                appliedSignaturesByDeviceID.removeValue(forKey: status.deviceID)
                synchronizeCurrentPresetPosition(status, configuration: configuration)
            }
        }
    }

    private func refreshActiveGroupPreset() {
        guard let configuration = try? configurationCache.read(
            at: OverCUEAppConfigurationLocation.url
        ) else {
            activeGroupPresetID = nil
            activeGroupPresetName = nil
            return
        }
        refreshActiveGroupPreset(using: configuration)
    }

    private func refreshActiveGroupPreset(using configuration: OverCUEConfiguration) {
        guard let activeID = configuration.activeGroupPresetID,
              let active = configuration.groupPresets.first(where: { $0.id == activeID })
        else {
            activeGroupPresetID = nil
            activeGroupPresetName = nil
            return
        }
        activeGroupPresetID = active.id
        activeGroupPresetName = active.name
    }

    private func baselineSignature(
        for status: GroupPresetRuntimeStatus,
        configuration: OverCUEConfiguration
    ) -> AppliedGroupPresetSignature? {
        guard let logicalDeviceID = status.logicalDeviceID,
              let groupPresetID = configuration.activeGroupPresetID,
              let presetID = configuration.assignedPresetID(for: logicalDeviceID),
              let logicalDevice = configuration.logicalDevices[logicalDeviceID],
              logicalDevice.profileName == status.profileName,
              configuration.profiles[status.profileName]?.presetGroup(id: presetID) != nil
        else { return nil }

        return AppliedGroupPresetSignature(
            groupPresetID: groupPresetID,
            presetID: presetID,
            profileName: status.profileName
        )
    }

    private func applyIfNeeded(to status: GroupPresetRuntimeStatus) {
        guard let configuration = try? configurationCache.read(
            at: OverCUEAppConfigurationLocation.url
        ) else {
            appliedSignaturesByDeviceID.removeValue(forKey: status.deviceID)
            return
        }
        applyIfNeeded(to: status, configuration: configuration)
    }

    private func applyIfNeeded(
        to status: GroupPresetRuntimeStatus,
        configuration: OverCUEConfiguration
    ) {
        guard let signature = baselineSignature(for: status, configuration: configuration),
              let profile = configuration.profiles[status.profileName],
              let presetIndex = profile.orderedPresetGroups.firstIndex(where: {
                  $0.id == signature.presetID
              })
        else {
            appliedSignaturesByDeviceID.removeValue(forKey: status.deviceID)
            return
        }
        guard appliedSignaturesByDeviceID[status.deviceID] != signature else { return }

        // Mark before posting because the bridge immediately publishes a new
        // runtime status in response to this device-scoped control message.
        appliedSignaturesByDeviceID[status.deviceID] = signature
        guard status.presetID != signature.presetID || status.group != presetIndex + 1 else { return }

        postRuntimeControl(
            status: status,
            presetID: signature.presetID,
            presetIndex: presetIndex,
            profile: profile
        )
    }

    private func synchronizeCurrentPresetPosition(
        _ status: GroupPresetRuntimeStatus,
        configuration: OverCUEConfiguration
    ) {
        guard let presetID = status.presetID,
              let profile = configuration.profiles[status.profileName],
              let presetIndex = profile.orderedPresetGroups.firstIndex(where: { $0.id == presetID }),
              status.group != presetIndex + 1
        else { return }

        postRuntimeControl(
            status: status,
            presetID: presetID,
            presetIndex: presetIndex,
            profile: profile
        )
    }

    private func postRuntimeControl(
        status: GroupPresetRuntimeStatus,
        presetID: String,
        presetIndex: Int,
        profile: OverCUEProfile
    ) {
        let group = presetIndex + 1
        let mode = profile.mapping(for: group).rekordboxMode ?? status.mode
        let userInfo: [String: Any] = [
            OverCUERuntimeControlNotification.groupKey: group,
            OverCUERuntimeControlNotification.modeKey: mode.rawValue,
            OverCUERuntimeControlNotification.presetGroupIDKey: presetID,
            OverCUERuntimeControlNotification.scopeKey:
                OverCUERuntimeNotificationScope.device.rawValue,
            OverCUERuntimeControlNotification.deviceIDKey: status.deviceID,
            OverCUERuntimeControlNotification.profileNameKey: status.profileName,
        ]
        DistributedNotificationCenter.default().postNotificationName(
            OverCUERuntimeControlNotification.name,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }
}

import Foundation
import OverCUECore

private struct GroupPresetRuntimeStatus: Sendable {
    let mode: RekordboxMappingMode
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
    private var statusesByDeviceID: [String: GroupPresetRuntimeStatus] = [:]
    private var appliedSignaturesByDeviceID: [String: AppliedGroupPresetSignature] = [:]
    private var runtimeObserver: GroupPresetRuntimeObserverToken?
    private var configurationObserver: GroupPresetRuntimeObserverToken?

    init() {
        runtimeObserver = GroupPresetRuntimeObserverToken(
            DistributedNotificationCenter.default().addObserver(
                forName: OverCUERuntimeStatusNotification.name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let rawMode = notification.userInfo?[OverCUERuntimeStatusNotification.modeKey] as? String
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
                      let deviceID,
                      let profileName
                else { return }

                let status = GroupPresetRuntimeStatus(
                    mode: mode,
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
        for status in statusesByDeviceID.values {
            applyIfNeeded(to: status)
        }
    }

    private func applyIfNeeded(to status: GroupPresetRuntimeStatus) {
        guard let configuration = try? OverCUEConfigurationFileStore.readCurrent(
            at: OverCUEAppConfigurationLocation.url
        ),
              let logicalDeviceID = status.logicalDeviceID,
              let groupPresetID = configuration.activeGroupPresetID,
              let presetID = configuration.assignedPresetID(for: logicalDeviceID),
              let logicalDevice = configuration.logicalDevices[logicalDeviceID],
              logicalDevice.profileName == status.profileName,
              let profile = configuration.profiles[status.profileName],
              let presetIndex = profile.orderedPresetGroups.firstIndex(where: { $0.id == presetID })
        else {
            appliedSignaturesByDeviceID.removeValue(forKey: status.deviceID)
            return
        }

        let signature = AppliedGroupPresetSignature(
            groupPresetID: groupPresetID,
            presetID: presetID,
            profileName: status.profileName
        )
        guard appliedSignaturesByDeviceID[status.deviceID] != signature else { return }

        // Mark before posting because the bridge immediately publishes a new
        // runtime status in response to this device-scoped control message.
        appliedSignaturesByDeviceID[status.deviceID] = signature
        guard status.presetID != presetID else { return }

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

import Foundation
import OverCUECore

private final class GroupPresetObserverToken: @unchecked Sendable {
    let value: any NSObjectProtocol

    init(_ value: any NSObjectProtocol) {
        self.value = value
    }
}

@MainActor
final class GroupPresetManagementModel: ObservableObject {
    @Published private(set) var groupPresets: [OverCUEGroupPreset] = []
    @Published private(set) var activeGroupPresetID: String?
    @Published private(set) var errorMessage: String?

    private var configuration: OverCUEConfiguration = .defaultValue
    private var configurationObserver: GroupPresetObserverToken?

    init() {
        configurationObserver = GroupPresetObserverToken(
            DistributedNotificationCenter.default().addObserver(
                forName: OverCUEConfigurationChangedNotification.name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.reload() }
            }
        )
        reload()
    }

    deinit {
        if let configurationObserver {
            DistributedNotificationCenter.default().removeObserver(configurationObserver.value)
        }
    }

    var activeGroupPreset: OverCUEGroupPreset? {
        guard let activeGroupPresetID else { return nil }
        return groupPresets.first { $0.id == activeGroupPresetID }
    }

    func reload() {
        do {
            let latest = try OverCUEConfigurationFileStore.readCurrent(
                at: OverCUEAppConfigurationLocation.url
            )
            configuration = latest
            groupPresets = latest.orderedGroupPresets
            activeGroupPresetID = latest.activeGroupPresetID.flatMap { activeID in
                groupPresets.contains(where: { $0.id == activeID }) ? activeID : nil
            } ?? groupPresets.first?.id
            errorMessage = nil
        } catch {
            if !FileManager.default.fileExists(atPath: OverCUEAppConfigurationLocation.url.path) {
                configuration = .defaultValue
                groupPresets = configuration.orderedGroupPresets
                activeGroupPresetID = configuration.activeGroupPresetID
                errorMessage = nil
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func activate(id: String) throws {
        _ = try updateConfiguration { latest in
            guard latest.groupPresets.contains(where: { $0.id == id }) else {
                throw GroupPresetManagementError.groupPresetMissing
            }
            latest.activeGroupPresetID = id
        }
    }

    @discardableResult
    func add(name rawName: String) throws -> String {
        let name = try normalizedName(rawName)
        var createdID = ""
        _ = try updateConfiguration { latest in
            createdID = "gp-\(UUID().uuidString.lowercased())"
            let nextOrder = (latest.groupPresets.map(\.order).max() ?? 0) + 1
            latest.groupPresets.append(
                OverCUEGroupPreset(
                    id: createdID,
                    name: name,
                    order: nextOrder
                )
            )
            latest.activeGroupPresetID = createdID
        }
        return createdID
    }

    func rename(id: String, name rawName: String) throws {
        let name = try normalizedName(rawName)
        _ = try updateConfiguration { latest in
            guard let index = latest.groupPresets.firstIndex(where: { $0.id == id }) else {
                throw GroupPresetManagementError.groupPresetMissing
            }
            latest.groupPresets[index].name = name
        }
    }

    func delete(id: String) throws {
        _ = try updateConfiguration { latest in
            let ordered = latest.orderedGroupPresets
            guard ordered.count > 1 else {
                throw GroupPresetManagementError.cannotDeleteLast
            }
            guard let deletedIndex = ordered.firstIndex(where: { $0.id == id }) else {
                throw GroupPresetManagementError.groupPresetMissing
            }
            latest.groupPresets.removeAll { $0.id == id }
            let normalized = latest.orderedGroupPresets.enumerated().map { offset, preset in
                var preset = preset
                preset.order = offset + 1
                return preset
            }
            latest.groupPresets = normalized
            if latest.activeGroupPresetID == id {
                latest.activeGroupPresetID = normalized[min(deletedIndex, normalized.count - 1)].id
            }
        }
    }

    func availablePresets(for logicalDeviceID: String) -> [OverCUEPresetGroup] {
        guard let logicalDevice = configuration.logicalDevices[logicalDeviceID] else { return [] }
        return configuration.profiles[logicalDevice.profileName]?.orderedPresetGroups ?? []
    }

    func isIncluded(logicalDeviceID: String) -> Bool {
        activeGroupPreset?.devicePresetAssignments[logicalDeviceID] != nil
    }

    func assignedPresetID(logicalDeviceID: String) -> String? {
        activeGroupPreset?.devicePresetAssignments[logicalDeviceID]
    }

    func setIncluded(logicalDeviceID: String, included: Bool) throws {
        _ = try updateConfiguration { latest in
            guard let activeID = latest.activeGroupPresetID,
                  let groupPresetIndex = latest.groupPresets.firstIndex(where: { $0.id == activeID })
            else { throw GroupPresetManagementError.groupPresetMissing }
            guard let logicalDevice = latest.logicalDevices[logicalDeviceID],
                  let profile = latest.profiles[logicalDevice.profileName]
            else { throw GroupPresetManagementError.logicalDeviceMissing }

            if included {
                let existing = latest.groupPresets[groupPresetIndex]
                    .devicePresetAssignments[logicalDeviceID]
                if let existing, profile.presetGroup(id: existing) != nil {
                    return
                }
                guard let firstPresetID = profile.orderedPresetGroups.first?.id else {
                    throw GroupPresetManagementError.presetMissing
                }
                latest.groupPresets[groupPresetIndex]
                    .devicePresetAssignments[logicalDeviceID] = firstPresetID
            } else {
                latest.groupPresets[groupPresetIndex]
                    .devicePresetAssignments.removeValue(forKey: logicalDeviceID)
            }
        }
    }

    func assignPreset(logicalDeviceID: String, presetID: String) throws {
        _ = try updateConfiguration { latest in
            guard let activeID = latest.activeGroupPresetID,
                  let groupPresetIndex = latest.groupPresets.firstIndex(where: { $0.id == activeID })
            else { throw GroupPresetManagementError.groupPresetMissing }
            guard let logicalDevice = latest.logicalDevices[logicalDeviceID],
                  let profile = latest.profiles[logicalDevice.profileName]
            else { throw GroupPresetManagementError.logicalDeviceMissing }
            guard profile.presetGroup(id: presetID) != nil else {
                throw GroupPresetManagementError.presetMissing
            }
            latest.groupPresets[groupPresetIndex]
                .devicePresetAssignments[logicalDeviceID] = presetID
        }
    }

    private func normalizedName(_ rawName: String) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw GroupPresetManagementError.invalidName }
        return name
    }

    @discardableResult
    private func updateConfiguration(
        _ update: (inout OverCUEConfiguration) throws -> Void
    ) throws -> OverCUEConfiguration {
        let latest = try OverCUEConfigurationFileStore.updateCurrent(
            at: OverCUEAppConfigurationLocation.url,
            fallback: configuration,
            update
        )
        configuration = latest
        groupPresets = latest.orderedGroupPresets
        activeGroupPresetID = latest.activeGroupPresetID
        errorMessage = nil
        OverCUEConfigurationChangedNotification.post()
        return latest
    }
}

enum GroupPresetManagementError: @preconcurrency LocalizedError {
    case invalidName
    case groupPresetMissing
    case logicalDeviceMissing
    case presetMissing
    case cannotDeleteLast

    @MainActor var errorDescription: String? {
        switch self {
        case .invalidName:
            L10n.text("groupPreset.error.name")
        case .groupPresetMissing:
            L10n.text("groupPreset.error.missing")
        case .logicalDeviceMissing:
            L10n.text("groupPreset.error.deviceMissing")
        case .presetMissing:
            L10n.text("groupPreset.error.presetMissing")
        case .cannotDeleteLast:
            L10n.text("preset.error.last")
        }
    }
}

import Foundation
import OverCUECore

struct PresetGroupMutationResult: Equatable {
    let id: String
    let index: Int
}

enum PresetGroupStoreError: Error, LocalizedError {
    case profileMissing
    case maximumReached
    case invalidName
    case presetMissing
    case cannotDeleteFirst
    case cannotDeleteLast

    var errorDescription: String? {
        switch self {
        case .profileMissing:
            return L10n.text("preset.error.profileMissing")
        case .maximumReached:
            return L10n.text("preset.error.maximum")
        case .invalidName:
            return L10n.text("preset.error.name")
        case .presetMissing:
            return L10n.text("preset.error.missing")
        case .cannotDeleteFirst:
            return L10n.text("preset.error.first")
        case .cannotDeleteLast:
            return L10n.text("preset.error.last")
        }
    }
}

enum OverCUEAppConfigurationLocation {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/OverCUE/config.json")
}

enum PresetGroupStore {
    static func add(
        name rawName: String,
        mode: RekordboxMappingMode
    ) throws -> PresetGroupMutationResult {
        let name = normalizedName(rawName)
        guard !name.isEmpty else { throw PresetGroupStoreError.invalidName }

        var createdID = ""
        var createdIndex = 1
        let configuration = try OverCUEConfigurationFileStore.updateCurrent(
            at: OverCUEAppConfigurationLocation.url,
            fallback: .defaultValue
        ) { latest in
            guard var profile = latest.profiles[latest.defaultProfile] else {
                throw PresetGroupStoreError.profileMissing
            }
            let groups = profile.orderedPresetGroups
            guard groups.count < OverCUEPresetGroup.maximumCount else {
                throw PresetGroupStoreError.maximumReached
            }

            createdID = "pg-\(UUID().uuidString.lowercased())"
            let nextOrder = (groups.map(\.order).max() ?? 0) + 1
            profile.presetGroups.append(
                OverCUEPresetGroup(
                    id: createdID,
                    name: name,
                    order: nextOrder,
                    mapping: OverCUEGroupMapping(rekordboxMode: mode)
                )
            )
            latest.profiles[latest.defaultProfile] = profile
            createdIndex = profile.orderedPresetGroups.firstIndex(where: { $0.id == createdID })
                .map { $0 + 1 } ?? profile.orderedPresetGroups.count
        }
        guard configuration.profiles[configuration.defaultProfile] != nil else {
            throw PresetGroupStoreError.profileMissing
        }
        OverCUEConfigurationChangedNotification.post()
        return PresetGroupMutationResult(id: createdID, index: createdIndex)
    }

    static func rename(id: String, name rawName: String) throws {
        let name = normalizedName(rawName)
        guard !name.isEmpty else { throw PresetGroupStoreError.invalidName }
        _ = try OverCUEConfigurationFileStore.updateCurrent(
            at: OverCUEAppConfigurationLocation.url,
            fallback: .defaultValue
        ) { latest in
            guard var profile = latest.profiles[latest.defaultProfile] else {
                throw PresetGroupStoreError.profileMissing
            }
            guard let index = profile.presetGroups.firstIndex(where: { $0.id == id }) else {
                throw PresetGroupStoreError.presetMissing
            }
            profile.presetGroups[index].name = name
            latest.profiles[latest.defaultProfile] = profile
        }
        OverCUEConfigurationChangedNotification.post()
    }

    static func delete(id: String) throws -> Int {
        var nextIndex = 1
        _ = try OverCUEConfigurationFileStore.updateCurrent(
            at: OverCUEAppConfigurationLocation.url,
            fallback: .defaultValue
        ) { latest in
            guard var profile = latest.profiles[latest.defaultProfile] else {
                throw PresetGroupStoreError.profileMissing
            }
            let ordered = profile.orderedPresetGroups
            guard ordered.count > 1 else { throw PresetGroupStoreError.cannotDeleteLast }
            guard let deletedIndex = ordered.firstIndex(where: { $0.id == id }) else {
                throw PresetGroupStoreError.presetMissing
            }
            // The first Preset currently owns the global Cycle Preset bindings that
            // are overlaid onto the other Presets. Do not make that implicit source
            // mutable until those bindings are promoted to their own global scope.
            guard deletedIndex != 0 else { throw PresetGroupStoreError.cannotDeleteFirst }

            profile.presetGroups.removeAll { $0.id == id }
            let normalized = profile.orderedPresetGroups.enumerated().map { offset, preset in
                var preset = preset
                preset.order = offset + 1
                return preset
            }
            profile.presetGroups = normalized
            latest.profiles[latest.defaultProfile] = profile
            nextIndex = min(deletedIndex + 1, normalized.count)
        }
        OverCUEConfigurationChangedNotification.post()
        return max(1, nextIndex)
    }

    private static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import Foundation

public enum OverCUEConfigurationOrderingError: Error, Equatable, LocalizedError, Sendable {
    case profileMissing(String)
    case invalidPresetOrder
    case invalidGroupPresetOrder

    public var errorDescription: String? {
        switch self {
        case let .profileMissing(profileName):
            return "Profile '\(profileName)' does not exist."
        case .invalidPresetOrder:
            return "Preset order must contain every Preset ID exactly once."
        case .invalidGroupPresetOrder:
            return "Group Preset order must contain every Group Preset ID exactly once."
        }
    }
}

public enum OverCUEConfigurationOrdering {
    public static func reorderPresets(
        ids: [String],
        profileName: String? = nil,
        in configuration: inout OverCUEConfiguration
    ) throws {
        let resolvedProfileName = profileName ?? configuration.defaultProfile
        guard var profile = configuration.profiles[resolvedProfileName] else {
            throw OverCUEConfigurationOrderingError.profileMissing(resolvedProfileName)
        }

        let existingIDs = profile.presetGroups.map(\.id)
        guard isCompleteOrder(ids, for: existingIDs) else {
            throw OverCUEConfigurationOrderingError.invalidPresetOrder
        }

        let orderByID = Dictionary(uniqueKeysWithValues: ids.enumerated().map { offset, id in
            (id, offset + 1)
        })
        for index in profile.presetGroups.indices {
            profile.presetGroups[index].order = orderByID[profile.presetGroups[index].id]!
        }
        configuration.profiles[resolvedProfileName] = profile
    }

    public static func reorderGroupPresets(
        ids: [String],
        in configuration: inout OverCUEConfiguration
    ) throws {
        let existingIDs = configuration.groupPresets.map(\.id)
        guard isCompleteOrder(ids, for: existingIDs) else {
            throw OverCUEConfigurationOrderingError.invalidGroupPresetOrder
        }

        let orderByID = Dictionary(uniqueKeysWithValues: ids.enumerated().map { offset, id in
            (id, offset + 1)
        })
        for index in configuration.groupPresets.indices {
            configuration.groupPresets[index].order = orderByID[configuration.groupPresets[index].id]!
        }
    }

    private static func isCompleteOrder(_ ids: [String], for existingIDs: [String]) -> Bool {
        ids.count == existingIDs.count
            && Set(ids).count == ids.count
            && Set(ids) == Set(existingIDs)
    }
}

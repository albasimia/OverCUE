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

        // Cycle Preset actions are currently stored in the first Preset and
        // overlaid globally at runtime. Reordering must not change those actions
        // merely because another Preset becomes first, so move only that implicit
        // global scope to the new first Preset before updating order values.
        moveGlobalCycleBindingsIfNeeded(
            from: profile.orderedPresetGroups.first?.id,
            to: ids.first,
            in: &profile
        )

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

    private static func moveGlobalCycleBindingsIfNeeded(
        from sourceID: String?,
        to destinationID: String?,
        in profile: inout OverCUEProfile
    ) {
        guard let sourceID,
              let destinationID,
              sourceID != destinationID,
              let sourceIndex = profile.presetGroups.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = profile.presetGroups.firstIndex(where: { $0.id == destinationID })
        else { return }

        var source = profile.presetGroups[sourceIndex].mapping
        var destination = profile.presetGroups[destinationIndex].mapping
        moveGlobalCycleBindings(from: &source.keyMap, to: &destination.keyMap)
        moveGlobalCycleBindings(from: &source.chordMap, to: &destination.chordMap)
        moveGlobalCycleBindings(from: &source.dialMap, to: &destination.dialMap)
        moveGlobalCycleBindings(from: &source.dialChordMap, to: &destination.dialChordMap)
        profile.presetGroups[sourceIndex].mapping = source
        profile.presetGroups[destinationIndex].mapping = destination
    }

    private static func moveGlobalCycleBindings(
        from source: inout [String: String],
        to destination: inout [String: String]
    ) {
        let globalBindings = source.filter { isGroupCycle($0.value) }

        // A cycle binding stored in a non-first Preset was previously inert.
        // Remove it before this Preset becomes first so reordering cannot make an
        // ignored stale binding suddenly active.
        let staleDestinationInputs = destination.compactMap { input, action in
            isGroupCycle(action) ? input : nil
        }
        for input in staleDestinationInputs {
            destination.removeValue(forKey: input)
        }
        for input in globalBindings.keys {
            source.removeValue(forKey: input)
        }
        for (input, action) in globalBindings {
            destination[input] = action
        }
    }

    private static func isGroupCycle(_ rawAction: String) -> Bool {
        ActionTarget(configurationValue: rawAction)?.semanticAction?.isGroupCycle == true
    }

    private static func isCompleteOrder(_ ids: [String], for existingIDs: [String]) -> Bool {
        ids.count == existingIDs.count
            && Set(ids).count == ids.count
            && Set(ids) == Set(existingIDs)
    }
}

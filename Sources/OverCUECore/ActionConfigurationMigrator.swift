public struct ActionMigrationWarning: Equatable, Sendable {
    public let profileName: String
    public let section: String
    public let input: String
    public let rawAction: String

    public init(profileName: String, section: String, input: String, rawAction: String) {
        self.profileName = profileName
        self.section = section
        self.input = input
        self.rawAction = rawAction
    }
}

public enum ActionConfigurationMigrator {
    public static func migrateToCurrentVersion(
        _ source: OverCUEConfiguration
    ) -> (configuration: OverCUEConfiguration, warnings: [ActionMigrationWarning]) {
        migrateToVersion7(source)
    }

    public static func migrateToVersion7(
        _ source: OverCUEConfiguration
    ) -> (configuration: OverCUEConfiguration, warnings: [ActionMigrationWarning]) {
        var result =
            source.version < 6
            ? migrateToVersion6(source)
            : (configuration: source, warnings: [])

        for profileName in result.configuration.profiles.keys.sorted() {
            guard var profile = result.configuration.profiles[profileName] else { continue }
            if let sharedPosition = profile.waveformPosition {
                for group in 1...4 {
                    var mapping = profile.storedMapping(for: group)
                    if mapping.waveformPosition == nil {
                        mapping.waveformPosition = sharedPosition
                    }
                    profile.setMapping(mapping, for: group)
                }
            }
            profile.waveformPosition = nil
            result.configuration.profiles[profileName] = profile
        }
        result.configuration.version = 7
        return result
    }

    public static func migrateToVersion6(
        _ source: OverCUEConfiguration
    ) -> (configuration: OverCUEConfiguration, warnings: [ActionMigrationWarning]) {
        var result =
            source.version < 5
            ? migrateToVersion5(source)
            : (configuration: source, warnings: [])
        let defaultGroup1 = OverCUEProfile.defaultValue.storedMapping(for: 1)

        for profileName in result.configuration.profiles.keys.sorted() {
            guard var profile = result.configuration.profiles[profileName] else { continue }
            var group1 = profile.storedMapping(for: 1)
            let usesPreviousDefaultLayout = defaultGroup1.keyMap.allSatisfy {
                group1.keyMap[$0.key] == $0.value
            }
            guard usesPreviousDefaultLayout else { continue }

            for input in ["K7+K2", "K7+K5"] where group1.chordMap[input] == nil {
                group1.chordMap[input] = defaultGroup1.chordMap[input]
            }
            profile.setMapping(group1, for: 1)
            result.configuration.profiles[profileName] = profile
        }
        result.configuration.version = 6
        return result
    }

    public static func migrateToVersion5(
        _ source: OverCUEConfiguration
    ) -> (configuration: OverCUEConfiguration, warnings: [ActionMigrationWarning]) {
        var result =
            source.version < 4
            ? migrateToVersion4(source)
            : (configuration: source, warnings: [])
        let defaults = OverCUEProfile.defaultValue
        let defaultGroup1 = defaults.storedMapping(for: 1)

        for profileName in result.configuration.profiles.keys.sorted() {
            guard var profile = result.configuration.profiles[profileName] else { continue }
            var group1 = profile.storedMapping(for: 1)
            let group2 = profile.storedMapping(for: 2)
            let group3 = profile.storedMapping(for: 3)
            let usesPreviousDefaultLayout = defaultGroup1.keyMap.allSatisfy {
                group1.keyMap[$0.key] == $0.value
            }
            guard usesPreviousDefaultLayout,
                group2.hasNoInputMappings,
                group3.hasNoInputMappings
            else { continue }

            for (input, target) in defaultGroup1.dialChordMap
            where group1.dialChordMap[input] == nil {
                group1.dialChordMap[input] = target
            }
            group1.rekordboxMode = .performance
            profile.setMapping(group1, for: 1)
            profile.setMapping(defaults.storedMapping(for: 2), for: 2)
            profile.setMapping(defaults.storedMapping(for: 3), for: 3)
            result.configuration.profiles[profileName] = profile
        }
        result.configuration.version = 5
        return result
    }

    public static func migrateToVersion4(
        _ source: OverCUEConfiguration
    ) -> (configuration: OverCUEConfiguration, warnings: [ActionMigrationWarning]) {
        var result =
            source.version < 3
            ? migrateToVersion3(source)
            : (configuration: source, warnings: [])
        for profileName in result.configuration.profiles.keys.sorted() {
            guard var profile = result.configuration.profiles[profileName] else { continue }
            var group1 = profile.mapping(for: 1)
            if group1.dialMap.isEmpty {
                group1.dialMap = [
                    DialDirection.counterclockwise.rawValue: ActionID.jogSearchLeft.rawValue,
                    DialDirection.clockwise.rawValue: ActionID.jogSearchRight.rawValue,
                ]
            }
            profile.setMapping(group1, for: 1)
            result.configuration.profiles[profileName] = profile
        }
        result.configuration.version = 4
        return result
    }

    public static func migrateToVersion3(
        _ source: OverCUEConfiguration
    ) -> (configuration: OverCUEConfiguration, warnings: [ActionMigrationWarning]) {
        var configuration = source
        var warnings: [ActionMigrationWarning] = []

        for profileName in configuration.profiles.keys.sorted() {
            guard var profile = configuration.profiles[profileName] else { continue }
            let hadPreviousDefaultChords =
                Set(profile.chordMap.keys)
                == Set([
                    "K8+K1", "K7+K8", "K7+K4", "K7+K1",
                ])
            profile.keyMap = migrate(
                profile.keyMap,
                profileName: profileName,
                section: "keyMap",
                warnings: &warnings
            )
            profile.chordMap = migrate(
                profile.chordMap,
                profileName: profileName,
                section: "chordMap",
                warnings: &warnings
            )
            if hadPreviousDefaultChords {
                profile.chordMap["K7+K3"] = ActionID.callNextMemoryCue.rawValue
                profile.chordMap["K7+K6"] = ActionID.callPreviousMemoryCue.rawValue
            }
            configuration.profiles[profileName] = profile
        }
        configuration.version = 3
        return (configuration, warnings)
    }

    private static func migrate(
        _ mappings: [String: String],
        profileName: String,
        section: String,
        warnings: inout [ActionMigrationWarning]
    ) -> [String: String] {
        var migrated: [String: String] = [:]
        for (input, rawAction) in mappings {
            if let action = ActionID(rawValue: rawAction)
                ?? ActionID(legacyDisplayName: rawAction)
            {
                migrated[input] = action.rawValue
            } else {
                warnings.append(
                    ActionMigrationWarning(
                        profileName: profileName,
                        section: section,
                        input: input,
                        rawAction: rawAction
                    )
                )
            }
        }
        return migrated
    }
}

extension OverCUEGroupMapping {
    fileprivate var hasNoInputMappings: Bool {
        keyMap.isEmpty && chordMap.isEmpty && dialMap.isEmpty && dialChordMap.isEmpty
    }
}

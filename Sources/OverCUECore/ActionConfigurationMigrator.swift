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
    public static func migrateToVersion3(
        _ source: OverCUEConfiguration
    ) -> (configuration: OverCUEConfiguration, warnings: [ActionMigrationWarning]) {
        var configuration = source
        var warnings: [ActionMigrationWarning] = []

        for profileName in configuration.profiles.keys.sorted() {
            guard var profile = configuration.profiles[profileName] else { continue }
            let hadPreviousDefaultChords = Set(profile.chordMap.keys) == Set([
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
                ?? ActionID(legacyDisplayName: rawAction) {
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

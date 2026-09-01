import XCTest
import OverCUECore

final class GroupPresetTests: XCTestCase {
    func testCurrentVersionDecodeBackfillsDefaultGroupPresetForExistingLogicalDevices() throws {
        var configuration = OverCUEConfiguration(
            version: OverCUEConfiguration.currentVersion,
            profiles: ["default": .defaultValue]
        )
        configuration.logicalDevices["deck-1"] = OverCUELogicalDevice(name: "Deck 1", profileName: "default")
        configuration.logicalDevices["deck-2"] = OverCUELogicalDevice(name: "Deck 2", profileName: "default")

        let decoded = try JSONDecoder().decode(OverCUEConfiguration.self, from: JSONEncoder().encode(configuration))
        let firstPresetID = decoded.profiles["default"]?.orderedPresetGroups.first?.id

        XCTAssertEqual(decoded.version, 10)
        XCTAssertEqual(decoded.activeGroupPresetID, "group-preset-default")
        XCTAssertEqual(decoded.groupPresets.count, 1)
        XCTAssertEqual(decoded.activeGroupPreset?.devicePresetAssignments["deck-1"], firstPresetID)
        XCTAssertEqual(decoded.activeGroupPreset?.devicePresetAssignments["deck-2"], firstPresetID)
    }

    func testLegacyGroupDisplayNamesNormalizeToPresetInCurrentConfiguration() throws {
        let data = Data("""
        {
          "version": 10,
          "profiles": {
            "default": {
              "presetGroups": [
                {
                  "id": "pg-one",
                  "name": "Group 1",
                  "order": 1,
                  "mapping": {"keyMap":{},"chordMap":{},"dialMap":{},"dialChordMap":{}}
                }
              ]
            }
          }
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(OverCUEConfiguration.self, from: data)
        XCTAssertEqual(decoded.profiles["default"]?.orderedPresetGroups.first?.name, "Preset 1")
    }

    func testVersion9MigrationCreatesDefaultGroupPresetForMigratedLogicalDevices() {
        var configuration = OverCUEConfiguration(version: 9, profiles: ["default": .defaultValue])
        configuration.logicalDevices["deck-1"] = OverCUELogicalDevice(name: "Deck 1", profileName: "default")
        let migrated = ActionConfigurationMigrator.migrateToCurrentVersion(configuration).configuration
        let firstPresetID = migrated.profiles["default"]?.orderedPresetGroups.first?.id
        XCTAssertEqual(migrated.version, 10)
        XCTAssertEqual(migrated.activeGroupPresetID, "group-preset-default")
        XCTAssertEqual(migrated.activeGroupPreset?.devicePresetAssignments["deck-1"], firstPresetID)
    }

    func testGroupPresetMembershipIsRepresentedByDeviceAssignmentPresence() {
        var configuration = OverCUEConfiguration.defaultValue
        configuration.logicalDevices["deck-1"] = OverCUELogicalDevice(name: "Deck 1", profileName: "default")
        let firstPresetID = configuration.profiles["default"]!.orderedPresetGroups[0].id
        configuration.groupPresets[0].devicePresetAssignments["deck-1"] = firstPresetID
        XCTAssertEqual(configuration.assignedPresetID(for: "deck-1"), firstPresetID)
        configuration.groupPresets[0].devicePresetAssignments.removeValue(forKey: "deck-1")
        XCTAssertNil(configuration.assignedPresetID(for: "deck-1"))
    }

    func testInvalidPresetReferenceDoesNotResolve() {
        var configuration = OverCUEConfiguration.defaultValue
        configuration.logicalDevices["deck-1"] = OverCUELogicalDevice(name: "Deck 1", profileName: "default")
        configuration.groupPresets[0].devicePresetAssignments["deck-1"] = "missing-preset"
        XCTAssertNil(configuration.assignedPresetID(for: "deck-1"))
    }

    func testConfigurationMergePreservesIndependentGroupPresetAssignments() {
        var base = OverCUEConfiguration.defaultValue
        let presetID = base.profiles["default"]!.orderedPresetGroups[0].id
        base.logicalDevices["deck-1"] = OverCUELogicalDevice(name: "Deck 1", profileName: "default")
        base.logicalDevices["deck-2"] = OverCUELogicalDevice(name: "Deck 2", profileName: "default")
        var local = base
        local.groupPresets[0].devicePresetAssignments["deck-1"] = presetID
        var remote = base
        remote.groupPresets[0].devicePresetAssignments["deck-2"] = presetID
        let merged = OverCUEConfigurationMerger.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(merged.groupPresets[0].devicePresetAssignments["deck-1"], presetID)
        XCTAssertEqual(merged.groupPresets[0].devicePresetAssignments["deck-2"], presetID)
    }
}

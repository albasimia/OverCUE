import Foundation
import XCTest
import OverCUECore
@testable import OverCUEApp

final class ConfigurationHotApplyTests: XCTestCase {
    @MainActor func testActivateAndAssignmentPersistWithoutChangingIdentityOrReordering() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        var configuration = OverCUEConfiguration.defaultValue
        let presets = configuration.profiles[configuration.defaultProfile]!.orderedPresetGroups
        XCTAssertGreaterThan(presets.count, 1)
        configuration.logicalDevices["side"] = OverCUELogicalDevice(name: "SIDE", profileName: configuration.defaultProfile)
        configuration.physicalDeviceBindings = [OverCUEPhysicalDeviceBinding(
            logicalDeviceID: "side", kind: .genericHID, vendorID: 1, productID: 2, serialNumber: "unique")]
        configuration.groupPresets.append(OverCUEGroupPreset(
            id: "other", name: "Other", order: 2,
            devicePresetAssignments: ["side": presets[1].id]))
        try OverCUEConfigurationFileStore.writeCurrent(configuration, at: url)
        let model = GroupPresetManagementModel(configurationURL: url, postsNotifications: false)
        try await model.activate(id: "other")
        let activated = try OverCUEConfigurationFileStore.readCurrent(at: url)
        XCTAssertEqual(model.activeGroupPresetID, "other")
        XCTAssertEqual(activated.activeGroupPresetID, "other")
        XCTAssertEqual(activated.assignedPresetID(for: "side"), presets[1].id)
        XCTAssertEqual(activated.physicalDeviceBindings, configuration.physicalDeviceBindings)
        XCTAssertEqual(activated.logicalDevices, configuration.logicalDevices)
        XCTAssertEqual(activated.profiles, configuration.profiles)
        XCTAssertFalse(OverCUEConfigurationReloadPlan(previous: configuration, latest: activated).requiresHIDEnumeration)
        try await model.assignPreset(logicalDeviceID: "side", presetID: presets[0].id)
        XCTAssertEqual(try OverCUEConfigurationFileStore.readCurrent(at: url).assignedPresetID(for: "side"), presets[0].id)
    }

    @MainActor func testShortcutRemovalDeletesACK05FormsAndPreservesOtherPreset() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        let suite = "OverCUE.Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var configuration = OverCUEConfiguration.defaultValue
        var profile = configuration.profiles[configuration.defaultProfile]!
        var mapping = profile.storedMapping(for: 1)
        mapping.keyMap["K1"] = "rekordbox:3001"
        mapping.chordMap["K1+K2"] = "rekordbox:3001"
        mapping.dialMap["clockwise"] = "rekordbox:3001"
        mapping.dialChordMap["K1+clockwise"] = "rekordbox:3001"
        profile.setMapping(mapping, for: 1)
        profile.setMapping(mapping, for: 2)
        configuration.profiles[configuration.defaultProfile] = profile
        try OverCUEConfigurationFileStore.writeCurrent(configuration, at: url)
        let model = ShortcutSettingsModel(configurationURL: url, defaults: defaults,
                                          startsRuntime: false, postsNotifications: false)
        await model.removeBindings(for: RekordboxShortcutEntry(
            index: 0, commandID: "3001", description: "Test action", shortcut: ""))
        let saved = try OverCUEConfigurationFileStore.readCurrent(at: url).profiles[configuration.defaultProfile]!
        let removed = saved.storedMapping(for: 1)
        XCTAssertEqual(removed.keyMap["K1"], "unassigned")
        XCTAssertFalse(removed.chordMap.values.contains("rekordbox:3001"))
        XCTAssertFalse(removed.dialMap.values.contains("rekordbox:3001"))
        XCTAssertFalse(removed.dialChordMap.values.contains("rekordbox:3001"))
        XCTAssertEqual(saved.storedMapping(for: 2), mapping)
    }

    func testSidecarRemovalPreservesOtherDeviceAndPreset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("generic.json")
        let input = GenericHIDInputBindingKey(input: GenericHIDInputDescriptor(
            usagePage: 0x07, usage: 0x59), activation: .press)
        let target = try XCTUnwrap(ActionTarget(configurationValue: "rekordbox:3001"))
        for (device, preset) in [("a", "editor"), ("a", "runtime"), ("b", "editor")] {
            try GenericHIDMappingStore.assign(logicalDeviceID: device, presetID: preset,
                                             input: input, target: target, at: url, postsNotification: false)
        }
        try GenericHIDMappingStore.removeTarget(logicalDeviceIDs: ["a"], presetID: "editor",
                                              target: target, at: url, postsNotification: false)
        let document = try GenericHIDMappingStore.read(at: url)
        XCTAssertTrue(GenericHIDMappingStore.mapping(logicalDeviceID: "a", presetID: "editor", in: document).isEmpty)
        XCTAssertEqual(GenericHIDMappingStore.mapping(logicalDeviceID: "a", presetID: "runtime", in: document)[input], target)
        XCTAssertEqual(GenericHIDMappingStore.mapping(logicalDeviceID: "b", presetID: "editor", in: document)[input], target)
    }
}

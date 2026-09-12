import XCTest
@testable import OverCUECore

final class ConfigurationReconciliationTests: XCTestCase {
    func testPresetReconciliationKeepsRemoteOrderWhilePreservingLocalFields() throws {
        let baseline = makeConfiguration()
        var local = baseline
        var remote = baseline

        var localProfile = try XCTUnwrap(local.profiles["default"])
        let localIndex = try XCTUnwrap(localProfile.presetGroups.firstIndex(where: { $0.id == "preset-b" }))
        localProfile.presetGroups[localIndex].name = "Locally Renamed"
        localProfile.presetGroups[localIndex].order = 1
        localProfile.presetGroups[localIndex].mapping.keyMap["K8"] = ActionID.jogSearchLeft.rawValue
        local.profiles["default"] = localProfile

        try OverCUEConfigurationOrdering.reorderPresets(
            ids: ["preset-c", "preset-a", "preset-b"],
            in: &remote
        )

        let reconciled = OverCUEConfigurationSnapshotSynchronizer.reconcile(
            configuration: local,
            persistedConfiguration: baseline,
            remote: remote
        ).configuration

        let profile = try XCTUnwrap(reconciled.profiles["default"])
        XCTAssertEqual(profile.orderedPresetGroups.map(\.id), ["preset-c", "preset-a", "preset-b"])
        XCTAssertEqual(profile.orderedPresetGroups.map(\.order), [1, 2, 3])

        let presetB = try XCTUnwrap(profile.presetGroup(id: "preset-b"))
        XCTAssertEqual(presetB.name, "Locally Renamed")
        XCTAssertEqual(presetB.mapping.keyMap["K8"], ActionID.jogSearchLeft.rawValue)
    }

    func testGroupPresetReconciliationKeepsRemoteOrderWhilePreservingLocalAssignments() throws {
        let baseline = makeConfiguration()
        var local = baseline
        var remote = baseline

        let localIndex = try XCTUnwrap(local.groupPresets.firstIndex(where: { $0.id == "group-b" }))
        local.groupPresets[localIndex].name = "Locally Renamed Group"
        local.groupPresets[localIndex].order = 1
        local.groupPresets[localIndex].devicePresetAssignments["device-1"] = "preset-b"

        try OverCUEConfigurationOrdering.reorderGroupPresets(
            ids: ["group-c", "group-a", "group-b"],
            in: &remote
        )

        let reconciled = OverCUEConfigurationSnapshotSynchronizer.reconcile(
            configuration: local,
            persistedConfiguration: baseline,
            remote: remote
        ).configuration

        XCTAssertEqual(reconciled.orderedGroupPresets.map(\.id), ["group-c", "group-a", "group-b"])
        XCTAssertEqual(reconciled.orderedGroupPresets.map(\.order), [1, 2, 3])

        let groupB = try XCTUnwrap(reconciled.groupPresets.first(where: { $0.id == "group-b" }))
        XCTAssertEqual(groupB.name, "Locally Renamed Group")
        XCTAssertEqual(groupB.devicePresetAssignments["device-1"], "preset-b")
    }

    private func makeConfiguration() -> OverCUEConfiguration {
        OverCUEConfiguration(
            profiles: [
                "default": OverCUEProfile(
                    presetGroups: [
                        preset("preset-a", order: 1),
                        preset("preset-b", order: 2),
                        preset("preset-c", order: 3),
                    ]
                ),
            ],
            groupPresets: [
                groupPreset("group-a", order: 1),
                groupPreset("group-b", order: 2),
                groupPreset("group-c", order: 3),
            ],
            activeGroupPresetID: "group-b"
        )
    }

    private func preset(_ id: String, order: Int) -> OverCUEPresetGroup {
        OverCUEPresetGroup(
            id: id,
            name: id,
            order: order,
            mapping: OverCUEGroupMapping(rekordboxMode: .performance)
        )
    }

    private func groupPreset(_ id: String, order: Int) -> OverCUEGroupPreset {
        OverCUEGroupPreset(id: id, name: id, order: order)
    }
}

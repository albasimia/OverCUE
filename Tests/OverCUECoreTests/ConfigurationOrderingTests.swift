import XCTest
@testable import OverCUECore

final class ConfigurationOrderingTests: XCTestCase {
    func testReorderPresetsUsesStableIDsAndNormalizesOrder() throws {
        var configuration = makeConfiguration()

        try OverCUEConfigurationOrdering.reorderPresets(
            ids: ["preset-c", "preset-a", "preset-b"],
            in: &configuration
        )

        XCTAssertEqual(
            configuration.profiles["default"]?.orderedPresetGroups.map(\.id),
            ["preset-c", "preset-a", "preset-b"]
        )
        XCTAssertEqual(
            configuration.profiles["default"]?.orderedPresetGroups.map(\.order),
            [1, 2, 3]
        )
    }

    func testReorderPresetsRejectsMissingDuplicateAndUnknownIDs() {
        let invalidOrders = [
            ["preset-a", "preset-b"],
            ["preset-a", "preset-a", "preset-c"],
            ["preset-a", "preset-b", "preset-x"],
        ]

        for ids in invalidOrders {
            var configuration = makeConfiguration()
            XCTAssertThrowsError(
                try OverCUEConfigurationOrdering.reorderPresets(ids: ids, in: &configuration)
            ) { error in
                XCTAssertEqual(error as? OverCUEConfigurationOrderingError, .invalidPresetOrder)
            }
        }
    }

    func testReorderPresetsCanTargetNonDefaultProfile() throws {
        var configuration = makeConfiguration()
        configuration.profiles["secondary"] = OverCUEProfile(
            presetGroups: [
                preset("secondary-a", order: 10),
                preset("secondary-b", order: 20),
            ]
        )

        try OverCUEConfigurationOrdering.reorderPresets(
            ids: ["secondary-b", "secondary-a"],
            profileName: "secondary",
            in: &configuration
        )

        XCTAssertEqual(
            configuration.profiles["secondary"]?.orderedPresetGroups.map(\.id),
            ["secondary-b", "secondary-a"]
        )
        XCTAssertEqual(
            configuration.profiles["default"]?.orderedPresetGroups.map(\.id),
            ["preset-a", "preset-b", "preset-c"]
        )
    }

    func testReorderGroupPresetsUsesStableIDsAndNormalizesOrder() throws {
        var configuration = makeConfiguration()

        try OverCUEConfigurationOrdering.reorderGroupPresets(
            ids: ["group-c", "group-a", "group-b"],
            in: &configuration
        )

        XCTAssertEqual(
            configuration.orderedGroupPresets.map(\.id),
            ["group-c", "group-a", "group-b"]
        )
        XCTAssertEqual(configuration.orderedGroupPresets.map(\.order), [1, 2, 3])
        XCTAssertEqual(configuration.activeGroupPresetID, "group-b")
    }

    func testReorderGroupPresetsRejectsPartialOrder() {
        var configuration = makeConfiguration()

        XCTAssertThrowsError(
            try OverCUEConfigurationOrdering.reorderGroupPresets(
                ids: ["group-a", "group-b"],
                in: &configuration
            )
        ) { error in
            XCTAssertEqual(error as? OverCUEConfigurationOrderingError, .invalidGroupPresetOrder)
        }
    }

    private func makeConfiguration() -> OverCUEConfiguration {
        OverCUEConfiguration(
            profiles: [
                "default": OverCUEProfile(
                    presetGroups: [
                        preset("preset-a", order: 10),
                        preset("preset-b", order: 20),
                        preset("preset-c", order: 30),
                    ]
                ),
            ],
            groupPresets: [
                groupPreset("group-a", order: 10),
                groupPreset("group-b", order: 20),
                groupPreset("group-c", order: 30),
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

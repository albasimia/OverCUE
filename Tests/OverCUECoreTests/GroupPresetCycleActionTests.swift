import XCTest
import OverCUECore

final class GroupPresetCycleActionTests: XCTestCase {
    func testLegacyCycleActionsExposeGroupPresetDirection() {
        XCTAssertEqual(ActionID.cycleGroup.groupPresetCycleStep, 1)
        XCTAssertEqual(ActionID.cycleGroupBackward.groupPresetCycleStep, -1)
        XCTAssertEqual(ActionID.cycleGroup.displayName, "Next Group Preset")
        XCTAssertEqual(ActionID.cycleGroupBackward.displayName, "Previous Group Preset")
    }

    func testOldCycleDisplayNamesStillMigrate() {
        XCTAssertEqual(ActionID(legacyDisplayName: "Next Preset Group"), .cycleGroup)
        XCTAssertEqual(ActionID(legacyDisplayName: "Previous Preset Group"), .cycleGroupBackward)
    }

    func testGroupPresetCycleConsumesDeviceLocalPresetEvent() {
        let next = ActionEvent(
            action: .cycleGroup,
            phase: .triggered,
            sourceKey: .k2,
            sourceLabel: "K7+K2"
        )
        let previous = ActionEvent(
            action: .cycleGroupBackward,
            phase: .triggered,
            sourceKey: .k5,
            sourceLabel: "K7+K5"
        )

        XCTAssertEqual(next.target, .action(.cycleGroup))
        XCTAssertEqual(previous.target, .action(.cycleGroupBackward))
        XCTAssertEqual(next.phase, .released)
        XCTAssertEqual(previous.phase, .released)
    }
}

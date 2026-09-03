import XCTest
import OverCUECore

final class RuntimeStateOwnershipTests: XCTestCase {
    func testRuntimeStatesRemainDeviceScoped() {
        var registry = OverCUERuntimeStateRegistry()
        registry.apply(
            mode: .performance,
            group: 1,
            presetGroupID: "preset-a",
            deviceID: "device-a",
            logicalDeviceID: "logical-a",
            profileName: "default",
            defaultProfileName: "default",
            connected: true
        )
        registry.apply(
            mode: .export,
            group: 2,
            presetGroupID: "preset-b",
            deviceID: "device-b",
            logicalDeviceID: "logical-b",
            profileName: "default",
            defaultProfileName: "default",
            connected: true
        )

        XCTAssertEqual(registry.statesByDeviceID["device-a"]?.presetGroupID, "preset-a")
        XCTAssertEqual(registry.statesByDeviceID["device-b"]?.presetGroupID, "preset-b")
        XCTAssertEqual(registry.focusedState?.target.deviceID, "device-b")
    }

    func testNonDefaultStatusCannotRetargetDefaultRuntimeFocus() {
        var registry = OverCUERuntimeStateRegistry()
        registry.apply(
            mode: .performance,
            group: 1,
            presetGroupID: "preset-a",
            deviceID: "default-device",
            logicalDeviceID: "logical-a",
            profileName: "default",
            defaultProfileName: "default",
            connected: true
        )
        registry.apply(
            mode: .export,
            group: 3,
            presetGroupID: "other-preset",
            deviceID: "other-device",
            logicalDeviceID: "logical-other",
            profileName: "other",
            defaultProfileName: "default",
            connected: true
        )

        XCTAssertEqual(registry.focusedState?.target.deviceID, "default-device")
        XCTAssertNil(registry.statesByDeviceID["other-device"])
    }

    func testFocusedDeviceDisconnectDoesNotPromoteAnotherDeviceImplicitly() {
        var registry = OverCUERuntimeStateRegistry()
        for device in ["device-a", "device-b"] {
            registry.apply(
                mode: .performance,
                group: device == "device-a" ? 1 : 2,
                presetGroupID: device,
                deviceID: device,
                logicalDeviceID: device,
                profileName: "default",
                defaultProfileName: "default",
                connected: true
            )
        }
        registry.apply(
            mode: .performance,
            group: 2,
            presetGroupID: "device-b",
            deviceID: "device-b",
            logicalDeviceID: "device-b",
            profileName: "default",
            defaultProfileName: "default",
            connected: false
        )

        XCTAssertNil(registry.focusedState)
        XCTAssertNotNil(registry.statesByDeviceID["device-a"])
    }
}

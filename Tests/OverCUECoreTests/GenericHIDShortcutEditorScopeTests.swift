import XCTest
import OverCUECore

final class GenericHIDShortcutEditorScopeTests: XCTestCase {
    func testEditorPresetOverridesDifferentGroupPresetAssignmentsForDisplayAndDeletion() {
        var configuration = OverCUEConfiguration.defaultValue
        let runtimePresetID = configuration.profiles["default"]!.orderedPresetGroups[0].id
        configuration.logicalDevices["side-a"] = OverCUELogicalDevice(
            name: "Side A",
            profileName: "default"
        )
        configuration.logicalDevices["side-b"] = OverCUELogicalDevice(
            name: "Side B",
            profileName: "default"
        )
        configuration.physicalDeviceBindings = [
            OverCUEPhysicalDeviceBinding(
                logicalDeviceID: "side-a",
                kind: .genericHID,
                vendorID: 1,
                productID: 2,
                serialNumber: "A"
            ),
            OverCUEPhysicalDeviceBinding(
                logicalDeviceID: "side-b",
                kind: .genericHID,
                vendorID: 1,
                productID: 2,
                serialNumber: "B"
            ),
        ]
        configuration.groupPresets[0].devicePresetAssignments = [
            "side-a": runtimePresetID,
            "side-b": runtimePresetID,
        ]

        let scopes = GenericHIDShortcutEditorScopeResolver.scopes(
            configuration: configuration,
            profileName: "default",
            editorPresetID: "editor-preset"
        )

        XCTAssertEqual(Set(scopes.map(\.logicalDeviceID)), ["side-a", "side-b"])
        XCTAssertEqual(Set(scopes.map(\.presetID)), ["editor-preset"])
    }
}

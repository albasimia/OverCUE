import XCTest
import OverCUECore

final class ConfigurationReloadPlanTests: XCTestCase {
    func testMappingModeOrderAndGroupChangesDoNotEnumerateHID() {
        let base = OverCUEConfiguration.defaultValue
        var latest = base
        latest.activeGroupPresetID = "another"
        latest.groupPresets[0].devicePresetAssignments["side"] = "preset"
        latest.groupPresets[0].order = 2
        latest.profiles[latest.defaultProfile]?.presetGroups[0].order = 2
        latest.profiles[latest.defaultProfile]?.presetGroups[0].mapping.keyMap["K1"] = "unassigned"
        latest.profiles[latest.defaultProfile]?.presetGroups[0].mapping.rekordboxMode = .export
        XCTAssertFalse(OverCUEConfigurationReloadPlan(previous: base, latest: latest).requiresHIDEnumeration)
    }

    func testGenericBindingAdditionRemovalAndRebindEnumerateHID() {
        let base = OverCUEConfiguration.defaultValue
        var bound = base
        bound.physicalDeviceBindings.append(OverCUEPhysicalDeviceBinding(
            logicalDeviceID: "side", kind: .genericHID, vendorID: 1, productID: 2, serialNumber: "A"))
        XCTAssertTrue(OverCUEConfigurationReloadPlan(previous: base, latest: bound).requiresHIDEnumeration)
        XCTAssertTrue(OverCUEConfigurationReloadPlan(previous: bound, latest: base).requiresHIDEnumeration)
        var rebound = bound
        rebound.physicalDeviceBindings[0].serialNumber = "B"
        XCTAssertTrue(OverCUEConfigurationReloadPlan(previous: bound, latest: rebound).requiresHIDEnumeration)
    }
}

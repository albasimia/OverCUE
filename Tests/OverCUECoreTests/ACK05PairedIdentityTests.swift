import XCTest
import OverCUECore

final class ACK05PairedIdentityTests: XCTestCase {
    private let firstPairingID = "31100918-88D2-1452-8C2E-563FF9B1C453"
    private let secondPairingID = "E8A00866-5AC3-4BDE-BE4D-FC42ED747BE0"
    private let usbSlotLocationID: UInt32 = 18_087_936 // 0x01140000

    func testACK05UsesPairingUUIDAsPersistentIdentityWithoutSerial() throws {
        let device = descriptor(pairingID: firstPairingID, session: "session-a")

        XCTAssertNil(device.serialNumber)
        XCTAssertEqual(device.ack05PairingIdentifier, firstPairingID)
        XCTAssertEqual(device.ack05BindingIdentifier, firstPairingID)
        XCTAssertEqual(
            device.persistentIdentifier,
            "ack05:28BD:0202:pairing:\(firstPairingID)"
        )
    }

    func testACK05PairingIdentityCanBindLogicalDevice() throws {
        var configuration = OverCUEConfiguration.defaultValue
        configuration.logicalDevices["deck-a"] = OverCUELogicalDevice(
            name: "Deck A",
            profileName: configuration.defaultProfile
        )
        let device = descriptor(pairingID: firstPairingID, session: "session-a")

        let binding = try ACK05PairedDeviceBindingManager.rebind(
            logicalDeviceID: "deck-a",
            to: device,
            among: [device],
            configuration: &configuration
        )

        XCTAssertEqual(binding.legacyDeviceIdentifier, firstPairingID)
        XCTAssertEqual(
            configuration.bindingResolution(for: device, among: [device]),
            .bound(logicalDeviceID: "deck-a")
        )
    }

    func testRepairedACK05DoesNotMatchOldPairingBinding() throws {
        var configuration = OverCUEConfiguration.defaultValue
        configuration.logicalDevices["deck-a"] = OverCUELogicalDevice(
            name: "Deck A",
            profileName: configuration.defaultProfile
        )
        let beforeRepair = descriptor(pairingID: firstPairingID, session: "session-a")
        _ = try ACK05PairedDeviceBindingManager.rebind(
            logicalDeviceID: "deck-a",
            to: beforeRepair,
            among: [beforeRepair],
            configuration: &configuration
        )

        let afterRepair = descriptor(pairingID: secondPairingID, session: "session-b")
        XCTAssertEqual(
            configuration.bindingResolution(for: afterRepair, among: [afterRepair]),
            .unbound
        )
    }

    func testUSBACK05UsesLocationAsSlotIdentityWithoutSerial() {
        let device = usbDescriptor(locationID: usbSlotLocationID, transportIdentifier: "interface-a")

        XCTAssertNil(device.serialNumber)
        XCTAssertNil(device.ack05PairingIdentifier)
        XCTAssertEqual(device.ack05USBSlotIdentifier, "usb-slot:01140000")
        XCTAssertEqual(device.ack05BindingIdentifier, "usb-slot:01140000")
        XCTAssertEqual(
            device.persistentIdentifier,
            "ack05:28BD:0202:usb-slot:01140000"
        )
        XCTAssertEqual(
            device.sessionIdentifier,
            "ack05:28BD:0202:session:usb-slot:01140000"
        )
    }

    func testUSBACK05InterfacesShareOneRuntimeSessionAndCanBindSlot() throws {
        let interfaces = [
            usbDescriptor(locationID: usbSlotLocationID, transportIdentifier: "interface-mouse"),
            usbDescriptor(locationID: usbSlotLocationID, transportIdentifier: "interface-digitizer"),
            usbDescriptor(locationID: usbSlotLocationID, transportIdentifier: "interface-vendor"),
        ]

        XCTAssertEqual(Set(interfaces.map(\.sessionIdentifier)).count, 1)
        XCTAssertEqual(Set(interfaces.compactMap(\.persistentIdentifier)).count, 1)

        var configuration = OverCUEConfiguration.defaultValue
        configuration.logicalDevices["deck-a"] = OverCUELogicalDevice(
            name: "Deck A",
            profileName: configuration.defaultProfile
        )
        let binding = try ACK05PairedDeviceBindingManager.rebind(
            logicalDeviceID: "deck-a",
            to: interfaces[1],
            among: interfaces,
            configuration: &configuration
        )

        XCTAssertEqual(binding.legacyDeviceIdentifier, "usb-slot:01140000")
        XCTAssertEqual(
            configuration.bindingResolution(for: interfaces[2], among: interfaces),
            .bound(logicalDeviceID: "deck-a")
        )
    }

    func testUSBACK05MovingToAnotherPortDoesNotMatchOldSlotBinding() throws {
        var configuration = OverCUEConfiguration.defaultValue
        configuration.logicalDevices["deck-a"] = OverCUELogicalDevice(
            name: "Deck A",
            profileName: configuration.defaultProfile
        )
        let originalSlot = usbDescriptor(
            locationID: usbSlotLocationID,
            transportIdentifier: "interface-a"
        )
        _ = try ACK05PairedDeviceBindingManager.rebind(
            logicalDeviceID: "deck-a",
            to: originalSlot,
            among: [originalSlot],
            configuration: &configuration
        )

        let anotherSlot = usbDescriptor(
            locationID: 18_022_400, // 0x01130000
            transportIdentifier: "interface-b"
        )
        XCTAssertEqual(
            configuration.bindingResolution(for: anotherSlot, among: [anotherSlot]),
            .unbound
        )
    }

    func testGenericHIDDoesNotPromoteUUIDOrLocationToACK05Identity() {
        let device = HIDPhysicalDeviceDescriptor(
            kind: .genericHID,
            vendorID: 0x1234,
            productID: 0x5678,
            transport: "USB",
            locationID: usbSlotLocationID,
            transportIdentifier: "session-a",
            legacyIdentifiers: [firstPairingID]
        )

        XCTAssertNil(device.ack05PairingIdentifier)
        XCTAssertNil(device.ack05USBSlotIdentifier)
        XCTAssertNil(device.ack05BindingIdentifier)
        XCTAssertNil(device.persistentIdentifier)
        XCTAssertEqual(device.sessionIdentifier, "genericHID:1234:5678:session:session-a")
    }

    private func descriptor(pairingID: String, session: String) -> HIDPhysicalDeviceDescriptor {
        HIDPhysicalDeviceDescriptor(
            kind: .ack05,
            vendorID: 0x28BD,
            productID: 0x0202,
            transport: "Bluetooth Low Energy",
            locationID: 403_247_153,
            transportIdentifier: session,
            legacyIdentifiers: [pairingID, "e4-68-c8-e6-9b-f5"]
        )
    }

    private func usbDescriptor(
        locationID: UInt32,
        transportIdentifier: String
    ) -> HIDPhysicalDeviceDescriptor {
        HIDPhysicalDeviceDescriptor(
            kind: .ack05,
            vendorID: 0x28BD,
            productID: 0x0202,
            serialNumber: "                    ",
            productName: "Shortcut Remote",
            manufacturerName: "Hanvon Ugee",
            transport: "USB",
            locationID: locationID,
            transportIdentifier: transportIdentifier
        )
    }
}

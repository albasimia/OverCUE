import XCTest
import OverCUECore

final class GenericHIDReviewTests: XCTestCase {
    func testRelativeDirectionAndMagnitudeReachActionLayer() throws {
        let input = GenericHIDInputDescriptor(usagePage: 0x01, usage: 0x37, reportID: 3)
        let element = GenericHIDRuntimeElementDescriptor(
            input: input,
            cookie: 100,
            isRelative: true,
            matchingElementCount: 1
        )
        var resolver = GenericHIDActionResolver()
        let mapping: [GenericHIDInputBindingKey: ActionTarget] = [
            GenericHIDInputBindingKey(input: input, activation: .relativePositive): .action(.jumpForward),
            GenericHIDInputBindingKey(input: input, activation: .relativeNegative): .action(.jumpBackward),
        ]

        let positive = GenericHIDEvent(
            sessionDeviceID: "generic-a",
            element: element,
            phase: .relative(delta: 3)
        )
        let negative = GenericHIDEvent(
            sessionDeviceID: "generic-a",
            element: element,
            phase: .relative(delta: -2)
        )

        let positiveEvent = try XCTUnwrap(resolver.resolve(event: positive, mapping: mapping).first)
        XCTAssertEqual(positiveEvent.action, .jumpForward)
        XCTAssertEqual(positiveEvent.activationCount, 3)
        XCTAssertNil(positiveEvent.sourceID?.ack05Key)
        XCTAssertNotNil(positiveEvent.sourceID)

        let negativeEvent = try XCTUnwrap(resolver.resolve(event: negative, mapping: mapping).first)
        XCTAssertEqual(negativeEvent.action, .jumpBackward)
        XCTAssertEqual(negativeEvent.activationCount, 2)
    }

    func testGenericHoldKeepsSameGenericSourceAcrossPressAndRelease() throws {
        let input = GenericHIDInputDescriptor(usagePage: 0x07, usage: 0x04, reportID: 1)
        let element = GenericHIDRuntimeElementDescriptor(
            input: input,
            cookie: 200,
            isRelative: false,
            matchingElementCount: 1
        )
        let mapping: [GenericHIDInputBindingKey: ActionTarget] = [
            GenericHIDInputBindingKey(input: input, activation: .press): .action(.cue),
        ]
        var resolver = GenericHIDActionResolver()
        let press = GenericHIDEvent(
            sessionDeviceID: "generic-a",
            element: element,
            phase: .pressed
        )
        let release = GenericHIDEvent(
            sessionDeviceID: "generic-a",
            element: element,
            phase: .released
        )

        let pressedEvent = try XCTUnwrap(resolver.resolve(event: press, mapping: mapping).first)
        let releasedEvent = try XCTUnwrap(resolver.resolve(event: release, mapping: mapping).first)
        XCTAssertEqual(pressedEvent.phase, .pressed)
        XCTAssertEqual(releasedEvent.phase, .released)
        XCTAssertEqual(pressedEvent.sourceID, releasedEvent.sourceID)
        XCTAssertNil(pressedEvent.sourceID?.ack05Key)
    }

    func testVerifiedMacroPadKeyboardAndConsumerControlsArePersistable() throws {
        let inputs: [GenericHIDInputDescriptor] = [
            GenericHIDInputDescriptor(usagePage: 0x07, usage: 0x59),
            GenericHIDInputDescriptor(usagePage: 0x07, usage: 0x5A),
            GenericHIDInputDescriptor(usagePage: 0x07, usage: 0x5B),
            GenericHIDInputDescriptor(usagePage: 0x07, usage: 0x5C),
            GenericHIDInputDescriptor(usagePage: 0x0C, usage: 0xE9, reportID: 3),
            GenericHIDInputDescriptor(usagePage: 0x0C, usage: 0xEA, reportID: 3),
            GenericHIDInputDescriptor(usagePage: 0x0C, usage: 0xE2, reportID: 3),
        ]

        for input in inputs {
            let element = GenericHIDRuntimeElementDescriptor(
                input: input,
                cookie: 1,
                isRelative: false,
                matchingElementCount: 1
            )
            let event = try XCTUnwrap(
                GenericHIDEventNormalizer.normalize(
                    GenericHIDRawValue(
                        sessionDeviceID: "macro-pad",
                        element: element,
                        value: 1
                    )
                )
            )
            XCTAssertEqual(event.phase, .pressed)
            let candidate = GenericHIDLearnCandidate(event: event)
            XCTAssertEqual(candidate.persistentInput, input)
            XCTAssertEqual(candidate.activation, .press)
            XCTAssertEqual(candidate.persistentBindingKey?.input, input)
        }
    }

    func testGenericHIDSerialCanBindLogicalDevice() throws {
        var configuration = OverCUEConfiguration.defaultValue
        configuration.logicalDevices["deck-a"] = OverCUELogicalDevice(
            name: "Deck A",
            profileName: configuration.defaultProfile
        )
        let device = HIDPhysicalDeviceDescriptor(
            kind: .genericHID,
            vendorID: 0x0816,
            productID: 0x246E,
            serialNumber: "3F8701678182",
            productName: "SIDE-KEYBOARD",
            transport: "USB",
            locationID: 17_903_616,
            transportIdentifier: "aggregate-session-a"
        )

        let binding = try HIDDeviceBindingManager.rebind(
            logicalDeviceID: "deck-a",
            to: device,
            among: [device],
            configuration: &configuration
        )

        XCTAssertEqual(binding.kind, .genericHID)
        XCTAssertEqual(binding.serialNumber, "3F8701678182")
        XCTAssertEqual(
            configuration.bindingResolution(for: device, among: [device]),
            .bound(logicalDeviceID: "deck-a")
        )
    }

    func testGenericHIDDuplicateSerialAcrossLiveAttachmentsIsAmbiguous() {
        var configuration = OverCUEConfiguration.defaultValue
        configuration.logicalDevices["deck-a"] = OverCUELogicalDevice(
            name: "Deck A",
            profileName: configuration.defaultProfile
        )
        let first = HIDPhysicalDeviceDescriptor(
            kind: .genericHID,
            vendorID: 0x0816,
            productID: 0x246E,
            serialNumber: "DUPLICATE",
            transport: "USB",
            locationID: 0x01110000,
            transportIdentifier: "aggregate-session-a"
        )
        let second = HIDPhysicalDeviceDescriptor(
            kind: .genericHID,
            vendorID: 0x0816,
            productID: 0x246E,
            serialNumber: "DUPLICATE",
            transport: "USB",
            locationID: 0x01120000,
            transportIdentifier: "aggregate-session-b"
        )

        XCTAssertThrowsError(
            try HIDDeviceBindingManager.rebind(
                logicalDeviceID: "deck-a",
                to: first,
                among: [first, second],
                configuration: &configuration
            )
        ) { error in
            XCTAssertEqual(
                error as? HIDDeviceBindingManagementError,
                .ambiguousPersistentIdentity(first.persistentIdentifier!)
            )
        }
        XCTAssertTrue(configuration.physicalDeviceBindings.isEmpty)
    }

    func testRebindRejectsDisconnectedIdentifyDescriptor() {
        var configuration = OverCUEConfiguration.defaultValue
        configuration.logicalDevices["deck-a"] = OverCUELogicalDevice(
            name: "Deck A",
            profileName: configuration.defaultProfile
        )
        let identified = HIDPhysicalDeviceDescriptor(
            kind: .genericHID,
            vendorID: 0x1234,
            productID: 0x5678,
            serialNumber: "SERIAL-A",
            transportIdentifier: "session-a"
        )
        let replacement = HIDPhysicalDeviceDescriptor(
            kind: .genericHID,
            vendorID: 0x1234,
            productID: 0x5678,
            serialNumber: "SERIAL-A",
            transportIdentifier: "session-b"
        )

        XCTAssertThrowsError(
            try HIDDeviceBindingManager.rebind(
                logicalDeviceID: "deck-a",
                to: identified,
                among: [replacement],
                configuration: &configuration
            )
        ) { error in
            XCTAssertEqual(
                error as? HIDDeviceBindingManagementError,
                .deviceNotConnected(identified.sessionIdentifier)
            )
        }
        XCTAssertTrue(configuration.physicalDeviceBindings.isEmpty)
    }
}

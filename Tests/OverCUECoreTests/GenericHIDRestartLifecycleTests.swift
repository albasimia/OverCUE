import Foundation
import XCTest
import OverCUECore

/// Synthetic component tests plus source wiring guards. These do not claim to
/// exercise macOS callback delivery, the SwiftUI lifecycle, or physical Learn.
final class GenericHIDRestartLifecycleTests: XCTestCase {
    private func coordinatorSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(
            "Sources/OverCUEApp/GenericHIDRuntimeCoordinator.swift"), encoding: .utf8)
    }

    private func section(_ source: String, _ start: String, _ end: String) throws -> String {
        let a = try XCTUnwrap(source.range(of: start))
        let b = try XCTUnwrap(source.range(of: end, range: a.upperBound..<source.endIndex))
        return String(source[a.lowerBound..<b.lowerBound])
    }

    func testEveryStartRestoresSchedulingAndExplicitSnapshotAfterSuccessfulOpen() throws {
        let source = try coordinatorSource()
        let start = try section(source, "func start() throws", "func beginCapture(")
        let open = try XCTUnwrap(start.range(of: "IOHIDManagerOpen("))
        let success = try XCTUnwrap(start.range(of: "isOpen = true"))
        let schedule = try XCTUnwrap(start.range(of: "IOHIDManagerScheduleWithRunLoop("))
        let snapshot = try XCTUnwrap(start.range(of: "registerCurrentInterfaces(source: \"start-enumeration\")"))
        XCTAssertLessThan(open.lowerBound, success.lowerBound)
        XCTAssertLessThan(success.lowerBound, schedule.lowerBound)
        XCTAssertLessThan(schedule.lowerBound, snapshot.lowerBound)
        XCTAssertFalse(try section(source, "init()", "deinit").contains("IOHIDManagerScheduleWithRunLoop"))
        let failure = try section(start, "guard result == kIOReturnSuccess", "isOpen = true")
        XCTAssertTrue(failure.contains("IOHIDManagerClose"))
        XCTAssertTrue(failure.contains("removeObservers()"))
    }

    func testSnapshotAndHotplugUseOneRegistrationPathAndReloadRetriesSnapshot() throws {
        let source = try coordinatorSource()
        let match = try section(source, "fileprivate func didMatch(", "private func registerCurrentInterfaces(")
        let snapshot = try section(source, "private func registerCurrentInterfaces(", "private func registerMatchedInterface(")
        XCTAssertTrue(match.contains("registerMatchedInterface(device, source:"))
        XCTAssertTrue(snapshot.contains("IOHIDManagerCopyDevices(manager)"))
        XCTAssertTrue(snapshot.contains("registerMatchedInterface(device, source:"))
        let register = try section(source, "private func registerMatchedInterface(", "fileprivate func didRemove(")
        for call in ["registerInterface(device)", "preloadMetadata(for: device)", "refreshRuntimeStates()"] {
            XCTAssertTrue(register.contains(call), call)
        }
        XCTAssertTrue(try section(source, "private func reloadConfigurationAndMappings()",
                                  "private func reloadLearnedMappings()").contains(
                                    "registerCurrentInterfaces(source: \"config-reload\")"))
        let grouping = try section(source, "private func registerInterface(", "private func candidateDescriptor(")
        XCTAssertTrue(grouping.contains("if let existingKey = groupKeyByInterfaceID[interfaceID]"))
        XCTAssertTrue(grouping.contains("return group.representative"))
    }

    func testStopClearsAllLiveStateAndStoppedCallbacksCannotRepopulateIt() throws {
        let source = try coordinatorSource()
        let stop = try section(source, "func stop()", "fileprivate func didMatch(")
        for reset in ["groups = [:]", "groupKeyByInterfaceID = [:]", "statesBySessionID = [:]",
                      "metadataCatalogs.removeAll()", "interfacesByID = [:]", "endCapture()"] {
            XCTAssertTrue(stop.contains(reset), reset)
        }
        XCTAssertLessThan(try XCTUnwrap(stop.range(of: "isOpen = false")).lowerBound,
                          try XCTUnwrap(stop.range(of: "IOHIDManagerClose(")).lowerBound)
        for (start, end) in [
            ("fileprivate func didMatch(", "private func registerCurrentInterfaces("),
            ("fileprivate func didRemove(", "fileprivate func didReceiveValue("),
            ("fileprivate func didReceiveValue(", "private func configureDeviceMatching()"),
        ] {
            XCTAssertTrue(try section(source, start, end).contains("guard isOpen, result == kIOReturnSuccess"))
        }
    }

    func testThreeSerialsRestartCatalogsBindingsAndThreeLearnCaptures() throws {
        let devices = (1...3).map { index in
            HIDPhysicalDeviceDescriptor(kind: .genericHID, vendorID: 0x0816, productID: 0x246E,
                                        serialNumber: "SYNTHETIC-\(index)", productName: "SIDE-KEYBOARD",
                                        transportIdentifier: "session-\(index)")
        }
        var configuration = OverCUEConfiguration.defaultValue
        for (index, device) in devices.enumerated() {
            let logicalID = "side-\(index)"
            configuration.logicalDevices[logicalID] = .init(name: logicalID, profileName: configuration.defaultProfile)
            configuration.groupPresets[0].devicePresetAssignments[logicalID] =
                configuration.profiles[configuration.defaultProfile]!.orderedPresetGroups[index].id
            _ = try HIDDeviceBindingManager.rebind(logicalDeviceID: logicalID, to: device,
                                                  among: devices, configuration: &configuration)
        }
        var catalogs = GenericHIDElementCatalogStore()
        var sessionBindings: [String: String] = [:]
        var sessionPresets: [String: String] = [:]
        var liveInterfaces: [UInt: HIDPhysicalDeviceDescriptor] = [:]
        var scans = 0
        let usages: [UInt32] = [0xE9, 0xEA, 0xE2]
        for _ in 0..<3 { // Same connected snapshot on three successive starts.
            for _ in 0..<2 { // Explicit snapshot, then duplicate match callbacks.
                for (index, device) in devices.enumerated() {
                    let interface = UInt(index + 1)
                    liveInterfaces[interface] = device
                    XCTAssertTrue(catalogs.preload(interfaceID: interface) {
                        scans += 1
                        return usages.enumerated().map { offset, usage in
                            .init(cookie: UInt64(offset + 1),
                                  input: .init(usagePage: 0x0C, usage: usage, reportID: 3), isRelative: false)
                        }
                    })
                    guard case let .bound(logicalID) = configuration.bindingResolution(for: device, among: devices) else {
                        return XCTFail("distinct serial must retain independent binding")
                    }
                    sessionBindings[device.sessionIdentifier] = logicalID
                    sessionPresets[device.sessionIdentifier] = try XCTUnwrap(configuration.assignedPresetID(for: logicalID))
                }
            }
            XCTAssertEqual(liveInterfaces.count, 3)
            XCTAssertEqual(Set(sessionBindings.values).count, 3)
            XCTAssertEqual(Set(sessionPresets.values).count, 3)
            let scansBeforeInput = scans
            var learn = GenericHIDLearnSession()
            for (offset, usage) in usages.enumerated() { // Three consecutive capture/end sessions.
                learn.begin()
                let metadata = try XCTUnwrap(catalogs.element(interfaceID: 2, cookie: UInt64(offset + 1)))
                let event = try XCTUnwrap(GenericHIDEventNormalizer.normalize(.init(
                    sessionDeviceID: devices[1].sessionIdentifier, element: metadata, value: 1)))
                guard case let .captured(candidate) = learn.observe(event) else { return XCTFail("capture") }
                XCTAssertEqual(candidate.persistentBindingKey?.input.usage.usage, usage)
                XCTAssertEqual(sessionBindings[candidate.sessionDeviceID], "side-1")
                learn.cancel()
            }
            XCTAssertEqual(scans, scansBeforeInput, "even first input cannot enumerate")
            catalogs.removeAll()
            sessionBindings.removeAll()
            sessionPresets.removeAll()
            liveInterfaces.removeAll()
            XCTAssertTrue(sessionBindings.isEmpty)
            XCTAssertTrue(sessionPresets.isEmpty)
            XCTAssertTrue(liveInterfaces.isEmpty)
            for interface: UInt in [1, 2, 3] { XCTAssertNil(catalogs.element(interfaceID: interface, cookie: 1)) }
        }
        XCTAssertEqual(scans, 9, "one preload per interface per start, not per notification/input")
    }
}

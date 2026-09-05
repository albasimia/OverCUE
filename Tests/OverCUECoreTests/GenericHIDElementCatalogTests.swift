import Foundation
import XCTest
import OverCUECore

final class GenericHIDElementCatalogTests: XCTestCase {
    private func element(_ cookie: UInt64, _ usage: UInt32 = 0xE9) -> GenericHIDElementCatalog.Element {
        .init(cookie: cookie, input: .init(usagePage: 0x0C, usage: usage, reportID: 3), isRelative: false)
    }

    func testCompleteMetadataAndRelativeFlagSurviveCatalog() throws {
        let input = GenericHIDInputDescriptor(
            usagePage: 1, usage: 0x37, reportID: 7,
            collectionPath: [HIDUsage(page: 1, usage: 8), HIDUsage(page: 1, usage: 1)]
        )
        let catalog = GenericHIDElementCatalog(elements: [
            element(1), .init(cookie: 2, input: input, isRelative: true),
        ])
        let actual = try XCTUnwrap(catalog.elementsByCookie[2])
        XCTAssertEqual(catalog.elementsByCookie.count, 2)
        XCTAssertEqual(actual.input, input)
        XCTAssertEqual(actual.cookie, 2)
        XCTAssertTrue(actual.isRelative)
        XCTAssertEqual(actual.persistentInput, input)
        XCTAssertFalse(try XCTUnwrap(catalog.elementsByCookie[1]).isRelative)
    }

    func testDuplicateDescriptorsRemainUnpersistableAndDuplicateCookiesFailClosed() {
        let catalog = GenericHIDElementCatalog(elements: [element(1), element(2)])
        for cookie: UInt64 in [1, 2] {
            XCTAssertEqual(catalog.elementsByCookie[cookie]?.matchingElementCount, 2)
            XCTAssertNil(catalog.elementsByCookie[cookie]?.persistentInput)
        }
        let conflicting = GenericHIDElementCatalog(elements: [element(1), element(1, 0xEA)])
        XCTAssertTrue(conflicting.elementsByCookie.isEmpty)
    }

    func testUniqueConsumerInputsPersistIncludingFirstLookup() throws {
        let catalog = GenericHIDElementCatalog(elements: [element(1), element(2, 0xEA), element(3, 0xE2)])
        for (cookie, usage): (UInt64, UInt32) in [(1, 0xE9), (2, 0xEA), (3, 0xE2)] {
            let actual = try XCTUnwrap(catalog.elementsByCookie[cookie])
            XCTAssertEqual(actual.matchingElementCount, 1)
            XCTAssertEqual(actual.persistentInput, element(cookie, usage).input)
        }
    }

    func testReportAndCollectionPathArePartOfDuplicateIdentity() {
        let base = element(1)
        let catalog = GenericHIDElementCatalog(elements: [
            base,
            .init(cookie: 2, input: .init(usagePage: 0x0C, usage: 0xE9, reportID: 4), isRelative: false),
            .init(cookie: 3, input: .init(usagePage: 0x0C, usage: 0xE9, reportID: 3,
                                        collectionPath: [HIDUsage(page: 1, usage: 1)]), isRelative: false),
        ])
        XCTAssertTrue(catalog.elementsByCookie.values.allSatisfy { $0.matchingElementCount == 1 })
    }

    func testThreeInterfacesRemovalReconnectAndRestartIsolateCookies() {
        var store = GenericHIDElementCatalogStore()
        for interface: UInt in [1, 2, 3] {
            XCTAssertTrue(store.preload(interfaceID: interface) { [element(1, UInt32(interface))] })
        }
        store.remove(interfaceID: 2)
        XCTAssertNil(store.element(interfaceID: 2, cookie: 1))
        XCTAssertEqual(store.element(interfaceID: 1, cookie: 1)?.input.usage.usage, 1)
        XCTAssertEqual(store.element(interfaceID: 3, cookie: 1)?.input.usage.usage, 3)
        XCTAssertTrue(store.preload(interfaceID: 2) { [element(2)] })
        XCTAssertNil(store.element(interfaceID: 2, cookie: 1))
        XCTAssertNotNil(store.element(interfaceID: 2, cookie: 2))
        store.removeAll()
        for interface: UInt in [1, 2, 3] { XCTAssertFalse(store.isReady(interfaceID: interface)) }
        XCTAssertTrue(store.preload(interfaceID: 1) { [element(9)] })
        XCTAssertNil(store.element(interfaceID: 1, cookie: 1))
        XCTAssertNotNil(store.element(interfaceID: 1, cookie: 9))
    }

    func testFailureAndUnknownCookieNeverRetryOnLookupReadyRefreshNeverEnumerates() {
        var store = GenericHIDElementCatalogStore()
        var enumerations = 0
        XCTAssertFalse(store.preload(interfaceID: 1) { enumerations += 1; return nil })
        for _ in 0..<10 { XCTAssertNil(store.element(interfaceID: 1, cookie: 1)) }
        XCTAssertEqual(enumerations, 1)
        XCTAssertFalse(store.preload(interfaceID: 1) { enumerations += 1; return [] })
        XCTAssertTrue(store.preload(interfaceID: 1) { enumerations += 1; return [element(1)] })
        for _ in 0..<10 {
            XCTAssertNotNil(store.element(interfaceID: 1, cookie: 1))
            XCTAssertNil(store.element(interfaceID: 1, cookie: 999))
        }
        XCTAssertTrue(store.preload(interfaceID: 1) { enumerations += 1; return nil })
        XCTAssertEqual(enumerations, 3)
    }

    func testRuntimeCallbackCannotEnumerateOrConstructMetadata() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Sources/OverCUEApp/GenericHIDRuntimeCoordinator.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "fileprivate func didReceiveValue("))
        let end = try XCTUnwrap(source.range(of: "private func configureDeviceMatching()", range: start.upperBound..<source.endIndex))
        let callback = String(source[start.lowerBound..<end.lowerBound])
        for forbidden in ["IOHIDDeviceCopyMatchingElements", "collectionPath(for:", "preloadMetadata",
                          "registerInterface(", "refreshRuntimeStates(", "GenericHIDInputDescriptor("] {
            XCTAssertFalse(callback.contains(forbidden), forbidden)
        }
        XCTAssertTrue(callback.contains("metadataCatalogs.element("))
        XCTAssertEqual(source.components(separatedBy: "IOHIDDeviceCopyMatchingElements(").count - 1, 1)
    }
}

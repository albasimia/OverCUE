import Foundation
import XCTest
import OverCUECore

final class ConfigurationReadCacheTests: XCTestCase {
    private func fixture(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("config.json"))
    }

    private func write(_ config: OverCUEConfiguration, to url: URL) throws {
        try JSONEncoder().encode(config).write(to: url, options: .atomic)
    }

    func testUnchangedReadsAndExplicitInvalidation() throws {
        try fixture { url in
            try write(.defaultValue, to: url)
            var cache = OverCUEConfigurationReadCache()
            let first = try cache.read(at: url)
            for _ in 0..<100 { XCTAssertEqual(try cache.read(at: url), first) }
            cache.invalidate()
            XCTAssertEqual(try cache.read(at: url), first)
        }
    }

    func testAtomicReplacementWithoutNotification() throws {
        try fixture { url in
            var config = OverCUEConfiguration.defaultValue
            try write(config, to: url)
            var cache = OverCUEConfigurationReadCache()
            let original = try cache.read(at: url)
            var profile = config.profiles[config.defaultProfile]!
            var mapping = profile.mapping(for: 1)
            mapping.rekordboxMode = .export
            profile.setMapping(mapping, for: 1)
            config.profiles[config.defaultProfile] = profile
            try write(config, to: url)
            XCTAssertEqual(try cache.read(at: url), try OverCUEConfigurationFileStore.readCurrent(at: url))
            XCTAssertNotEqual(try cache.read(at: url), original)
        }
    }

    func testInvalidAndMissingFilesDoNotReturnStaleConfig() throws {
        try fixture { url in
            try write(.defaultValue, to: url)
            var cache = OverCUEConfigurationReadCache()
            _ = try cache.read(at: url)
            try Data("invalid".utf8).write(to: url, options: .atomic)
            XCTAssertThrowsError(try cache.read(at: url))
            try FileManager.default.removeItem(at: url)
            XCTAssertThrowsError(try cache.read(at: url))
            try write(.defaultValue, to: url)
            XCTAssertEqual(try cache.read(at: url), try OverCUEConfigurationFileStore.readCurrent(at: url))
        }
    }

    func testUnsupportedVersionDoesNotReturnStaleConfig() throws {
        try fixture { url in
            try write(.defaultValue, to: url)
            var cache = OverCUEConfigurationReadCache()
            _ = try cache.read(at: url)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            json["version"] = 999
            try JSONSerialization.data(withJSONObject: json).write(to: url, options: .atomic)
            XCTAssertThrowsError(try cache.read(at: url))
        }
    }

    func testCacheIsScopedToURL() throws {
        try fixture { url in
            try write(.defaultValue, to: url)
            var cache = OverCUEConfigurationReadCache()
            _ = try cache.read(at: url)
            XCTAssertThrowsError(try cache.read(at: url.appendingPathExtension("missing")))
        }
    }

    func testSymlinkTargetReplacementIsObserved() throws {
        try fixture { url in
            try write(.defaultValue, to: url)
            let link = url.appendingPathExtension("link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
            var cache = OverCUEConfigurationReadCache()
            _ = try cache.read(at: link)
            try Data("invalid replacement".utf8).write(to: url, options: .atomic)
            XCTAssertThrowsError(try cache.read(at: link))
        }
    }

    func testReadCacheBenchmark() throws {
        try fixture { url in
            try write(.defaultValue, to: url)
            var cache = OverCUEConfigurationReadCache()
            let expected = try cache.read(at: url)
            let start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<500 { _ = try OverCUEConfigurationFileStore.readCurrent(at: url) }
            let uncached = ProcessInfo.processInfo.systemUptime - start
            let cachedStart = ProcessInfo.processInfo.systemUptime
            for _ in 0..<500 { _ = try cache.read(at: url) }
            let cached = ProcessInfo.processInfo.systemUptime - cachedStart
            XCTAssertEqual(try cache.read(at: url), expected)
            print("CONFIG READ BENCHMARK 500 reads: uncached=\(uncached * 1000)ms cached=\(cached * 1000)ms (not HID end-to-end latency)")
        }
    }
}

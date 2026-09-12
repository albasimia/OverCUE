import Foundation
import XCTest
import OverCUECore
@testable import OverCUEApp

final class ResponsivenessTests: XCTestCase {
    @MainActor func testProcessExitWaitLetsMainActorContinue() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0.25"]
        try process.run()
        var heartbeatWhileChildRunning = false
        let heartbeat = Task { @MainActor in
            try await Task.sleep(for: .milliseconds(40))
            heartbeatWhileChildRunning = process.isRunning
        }
        await OverCUEProcessTermination.waitForExit(process)
        try await heartbeat.value
        XCTAssertTrue(heartbeatWhileChildRunning)
        XCTAssertFalse(process.isRunning)
    }

    @MainActor func testPersistenceTransactionDoesNotOccupyMainActor() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".lock"))
            try? FileManager.default.removeItem(at: url) }
        let heartbeat = Task { @MainActor in
            try await Task.sleep(for: .milliseconds(30))
            return ProcessInfo.processInfo.systemUptime
        }
        let end = try await OverCUEPersistenceWorker.run {
            XCTAssertFalse(Thread.isMainThread)
            _ = try OverCUEConfigurationFileStore.updateCurrent(at: url, fallback: .defaultValue) { latest in
                // Deliberately slow locked transaction; UI must still execute.
                Thread.sleep(forTimeInterval: 0.2)
                latest.groupPresets[0].name = "Saved off-main"
            }
            return ProcessInfo.processInfo.systemUptime
        }
        let beat = try await heartbeat.value
        XCTAssertLessThan(beat, end)
        XCTAssertEqual(try OverCUEConfigurationFileStore.readCurrent(at: url).groupPresets[0].name,
                       "Saved off-main")
    }
}

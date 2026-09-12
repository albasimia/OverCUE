import Darwin
import Foundation

/// The caller owns Process and has requested termination. Suspending here lets
/// the main runloop continue while exclusive HID claims are handed back to macOS.
enum OverCUEProcessTermination {
    @MainActor static func waitForExit(_ process: Process) async {
        let span = OverCUEPerformanceSpan("ACK05 process exit")
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        var escalated = false
        while process.isRunning {
            if !escalated, ProcessInfo.processInfo.systemUptime >= deadline {
                // Only the child represented by this still-running Process.
                kill(process.processIdentifier, SIGKILL)
                escalated = true
            }
            // Teardown must finish even if its caller is cancelled. A timer
            // continuation stays suspended instead of spinning on cancelled sleep.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) {
                    continuation.resume()
                }
            }
        }
        span.mark("operation end")
    }
}

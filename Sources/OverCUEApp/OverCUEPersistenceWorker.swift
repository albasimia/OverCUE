import Foundation
import OverCUECore

/// File transactions run on one utility queue. Callers pass immutable Sendable
/// snapshots, and publish UI/runtime state only after the transaction completes.
/// FileStore still owns cross-process flock, reconciliation and atomic writes.
enum OverCUEPersistenceWorker {
    private static let queue = DispatchQueue(label: "com.overcue.persistence", qos: .userInitiated)

    static func run<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try operation() })
            }
        }
    }
}

struct OverCUEPerformanceSpan: Sendable {
    private static let enabled = ProcessInfo.processInfo.environment["OVERCUE_PERFORMANCE_DIAGNOSTICS"] == "1"
    private let operation: String
    private let start = ProcessInfo.processInfo.systemUptime

    init(_ operation: String) {
        self.operation = operation
        mark("operation start")
    }

    func mark(_ phase: String) {
        guard Self.enabled else { return }
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000
        NSLog("[OverCUE performance] %@ %@ thread=%@ elapsed=%.3fms", operation, phase,
              Thread.isMainThread ? "main" : "background", elapsed)
    }
}

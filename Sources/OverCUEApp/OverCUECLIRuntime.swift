import Foundation
import IOKit.hid
import OverCUECore

@MainActor
final class OverCUECLIRuntime {
    @MainActor
    enum Status: Equatable {
        case stopped
        case starting
        case running
        case degraded(String)
        case failed(String)

        var displayText: String {
            switch self {
            case .stopped: L10n.text("app.status.stopped")
            case .starting: L10n.text("app.status.starting")
            case .running: L10n.text("app.status.running")
            case let .degraded(message): L10n.text("app.status.degraded", message)
            case let .failed(message): L10n.text("app.status.failed", message)
            }
        }
    }

    var onStatusChanged: ((Status) -> Void)?

    private var process: Process?
    // All HID operations remain on MainActor. Only waits suspend; later lifecycle
    // requests invalidate stale starts and wait for the previous handoff to finish.
    private var lifecycleTask: Task<Void, Never>?
    private var lifecycleGeneration = 0

    private func enqueue(_ operation: @escaping @MainActor (Int) async -> Void) {
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        let previous = lifecycleTask
        lifecycleTask = Task { @MainActor in
            await previous?.value
            guard generation == self.lifecycleGeneration else { return }
            await operation(generation)
        }
    }

    private let genericHIDRuntime = GenericHIDRuntimeCoordinator()
    private let genericHIDNativeEventSuppressor = GenericHIDNativeEventSuppressor()
    private let genericHIDSuppressionDisabledForDiagnostics = ProcessInfo.processInfo.environment[
        "OVERCUE_DISABLE_GENERIC_HID_SUPPRESSION"
    ] == "1"
    private var isShortcutCaptureActive = false
    private var genericRuntimeStartedForCapture = false
    private(set) var status: Status = .stopped {
        didSet { onStatusChanged?(status) }
    }

    func start(mode: RekordboxMappingMode, group: Int) {
        enqueue { generation in
            await self.startImpl(mode: mode, group: group, generation: generation)
        }
    }

    private func startImpl(mode: RekordboxMappingMode, group: Int, generation: Int) async {
        // Existing ShortcutSettingsModel resumes runtime by calling start().
        // If this was a unified capture, resume only ACK05 and leave the same
        // Generic HID runtime / native-event suppressor alive.
        if isShortcutCaptureActive {
            await endShortcutCaptureImpl(mode: mode, group: group, resumeRuntime: true, generation: generation)
            return
        }

        await stopImpl()
        guard generation == lifecycleGeneration else { return }
        status = .starting

        var failures: [String] = []
        do {
            try startACK05Process(mode: mode, group: group)
        } catch {
            failures.append(error.localizedDescription)
        }
        do {
            try await startGenericHIDNativeEventSuppressorIfEnabled()
            try await startGenericHIDRuntimeWithHandoffRetry(generation: generation)
        } catch {
            genericHIDRuntime.stop()
            await genericHIDNativeEventSuppressor.stopAsync()
            failures.append(error.localizedDescription)
        }
        guard generation == lifecycleGeneration else { return }
        if process != nil || genericHIDRuntime.isRunning {
            status = failures.isEmpty ? .running : .degraded(failures.joined(separator: " "))
        } else {
            status = .failed(failures.joined(separator: " "))
        }
    }

    func beginShortcutCapture(
        onGenericHIDCaptured: @escaping (String, GenericHIDInputBindingKey) -> Void
    ) async throws {
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        let previous = lifecycleTask
        let task = Task { @MainActor in
            await previous?.value
            guard generation == self.lifecycleGeneration else { throw CancellationError() }
            try await self.beginShortcutCaptureImpl(onGenericHIDCaptured: onGenericHIDCaptured, generation: generation)
            guard generation == self.lifecycleGeneration else { throw CancellationError() }
        }
        lifecycleTask = Task { _ = try? await task.value }
        try await task.value
    }

    private func beginShortcutCaptureImpl(
        onGenericHIDCaptured: @escaping (String, GenericHIDInputBindingKey) -> Void,
        generation: Int
    ) async throws {
        if isShortcutCaptureActive {
            genericHIDRuntime.beginCapture(onCaptured: onGenericHIDCaptured)
            return
        }

        await stopACK05Process()
        guard generation == lifecycleGeneration else { throw CancellationError() }
        genericRuntimeStartedForCapture = !genericHIDRuntime.isRunning
        do {
            try await startGenericHIDNativeEventSuppressorIfEnabled()
            guard generation == lifecycleGeneration else { throw CancellationError() }
            if genericRuntimeStartedForCapture {
                try await startGenericHIDRuntimeWithHandoffRetry(generation: generation)
            }
            genericHIDRuntime.beginCapture(onCaptured: onGenericHIDCaptured)
            isShortcutCaptureActive = true
            status = .running
        } catch {
            if genericRuntimeStartedForCapture {
                genericHIDRuntime.stop()
                await genericHIDNativeEventSuppressor.stopAsync()
            }
            genericRuntimeStartedForCapture = false
            isShortcutCaptureActive = false
            throw error
        }
    }

    func endShortcutCapture(
        mode: RekordboxMappingMode,
        group: Int,
        resumeRuntime: Bool
    ) {
        enqueue { generation in
            await self.endShortcutCaptureImpl(mode: mode, group: group, resumeRuntime: resumeRuntime, generation: generation)
        }
    }

    private func endShortcutCaptureImpl(
        mode: RekordboxMappingMode, group: Int, resumeRuntime: Bool, generation: Int
    ) async {
        guard isShortcutCaptureActive else {
            if !resumeRuntime, genericRuntimeStartedForCapture {
                genericHIDRuntime.stop()
                await genericHIDNativeEventSuppressor.stopAsync()
                genericRuntimeStartedForCapture = false
            }
            if resumeRuntime, process == nil {
                do {
                    try startACK05Process(mode: mode, group: group)
                    status = genericHIDRuntime.isRunning
                        ? .running
                        : .degraded("Generic HID capture unavailable")
                } catch {
                    status = genericHIDRuntime.isRunning
                        ? .degraded(error.localizedDescription)
                        : .failed(error.localizedDescription)
                }
            }
            return
        }

        genericHIDRuntime.endCapture()
        isShortcutCaptureActive = false

        guard resumeRuntime else {
            await stopACK05Process()
            genericHIDRuntime.stop()
            await genericHIDNativeEventSuppressor.stopAsync()
            genericRuntimeStartedForCapture = false
            status = .stopped
            return
        }

        genericRuntimeStartedForCapture = false
        var failure: String?
        do {
            try await startGenericHIDNativeEventSuppressorIfEnabled()
            guard generation == lifecycleGeneration else { return }
            if process == nil {
                try startACK05Process(mode: mode, group: group)
            }
        } catch {
            failure = error.localizedDescription
        }
        if process != nil || genericHIDRuntime.isRunning {
            status = failure.map(Status.degraded) ?? .running
        } else {
            status = .failed(failure ?? L10n.text("cli.exited", 1))
        }
    }

    private func startGenericHIDNativeEventSuppressorIfEnabled() async throws {
        guard !genericHIDSuppressionDisabledForDiagnostics else { return }
        try await genericHIDNativeEventSuppressor.startAsync()
    }

    private func startGenericHIDRuntimeWithHandoffRetry(generation: Int) async throws {
        let maximumAttempts = 16

        for attempt in 1...maximumAttempts {
            guard generation == lifecycleGeneration else { throw CancellationError() }
            do {
                try genericHIDRuntime.start()
                return
            } catch let error as GenericHIDDeviceIdentifierMonitorError {
                guard case let .openFailed(status) = error,
                      status == kIOReturnExclusiveAccess,
                      attempt < maximumAttempts
                else {
                    throw error
                }
                genericHIDRuntime.stop()
                try await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func startACK05Process(mode: RekordboxMappingMode, group: Int) throws {
        guard process == nil else { return }
        guard let launch = launchConfiguration(mode: mode, group: group) else {
            throw NSError(
                domain: "OverCUE.CLI",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: L10n.text("cli.notFound")]
            )
        }

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = launch.executableURL
        process.arguments = launch.arguments
        process.currentDirectoryURL = launch.currentDirectoryURL
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        process.terminationHandler = { [weak self] terminatedProcess in
            let exitStatus = terminatedProcess.terminationStatus
            let detail = Self.errorDetail(from: errorPipe)
            Task { @MainActor in
                guard let self, self.process === terminatedProcess else { return }
                self.process = nil
                guard !self.isShortcutCaptureActive else { return }
                let detail = detail?.localizedCaseInsensitiveContains("HID access was denied") == true
                    ? L10n.text("cli.inputPermission")
                    : (detail ?? L10n.text("cli.exited", exitStatus))
                if self.genericHIDRuntime.isRunning {
                    self.status = .degraded(detail)
                } else if exitStatus == 0 {
                    self.status = .stopped
                } else {
                    self.status = .failed(detail)
                }
            }
        }
        try process.run()
        self.process = process
    }

    private func stopACK05Process() async {
        guard let process else { return }
        self.process = nil
        if process.isRunning {
            process.terminate()
            // Process stays retained through termination. Never block the HID/UI
            // runloop while the helper releases its exclusive device claims.
            await OverCUEProcessTermination.waitForExit(process)
        }
    }

    nonisolated private static func errorDetail(from pipe: Pipe) -> String? {
        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let output = String(data: data, encoding: .utf8)
        else { return nil }
        let firstLine = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.isEmpty })
        return firstLine
    }

    func restart(mode: RekordboxMappingMode, group: Int) {
        start(mode: mode, group: group)
    }

    func stop() {
        if process?.isRunning == true { process?.terminate() }
        // Stop input and suppression immediately, even while a process is exiting.
        genericHIDRuntime.endCapture()
        genericHIDRuntime.stop()
        genericHIDNativeEventSuppressor.requestStop()
        enqueue { _ in await self.stopImpl() }
    }

    private func stopImpl() async {
        isShortcutCaptureActive = false
        genericRuntimeStartedForCapture = false
        genericHIDRuntime.endCapture()
        genericHIDRuntime.stop()
        await genericHIDNativeEventSuppressor.stopAsync()
        await stopACK05Process()
        status = .stopped
    }

    private func launchConfiguration(mode: RekordboxMappingMode, group: Int) -> LaunchConfiguration? {
        let arguments = [
            "--output", "mouse",
            "--rekordbox-mode", mode.rawValue,
            "--group", String(group),
            "--no-accessibility-prompt",
            "--parent-pid", String(ProcessInfo.processInfo.processIdentifier),
        ]
        let fileManager = FileManager.default
        var candidates: [URL] = []

        candidates.append(
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Helpers/overcue-cli")
        )
        if let executableURL = Bundle.main.executableURL {
            candidates.append(executableURL.deletingLastPathComponent().appendingPathComponent("overcue-cli"))
        }
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        candidates.append(currentDirectory.appendingPathComponent(".build/debug/overcue-cli"))

        if let packageRoot = packageRoot(startingAt: currentDirectory) {
            candidates.append(packageRoot.appendingPathComponent(".build/debug/overcue-cli"))
            if let executable = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
                return LaunchConfiguration(
                    executableURL: executable,
                    arguments: arguments,
                    currentDirectoryURL: packageRoot
                )
            }
            return LaunchConfiguration(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["swift", "run", "overcue-cli"] + arguments,
                currentDirectoryURL: packageRoot
            )
        }

        guard let executable = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
            return nil
        }
        return LaunchConfiguration(executableURL: executable, arguments: arguments, currentDirectoryURL: currentDirectory)
    }

    private func packageRoot(startingAt directory: URL) -> URL? {
        var candidate = directory.standardizedFileURL
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            guard parent != candidate else { break }
            candidate = parent
        }
        return nil
    }
}

private struct LaunchConfiguration {
    let executableURL: URL
    let arguments: [String]
    let currentDirectoryURL: URL
}

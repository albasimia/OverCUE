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
        // Existing ShortcutSettingsModel resumes runtime by calling start().
        // If this was a unified capture, resume only ACK05 and leave the same
        // Generic HID runtime / native-event suppressor alive.
        if isShortcutCaptureActive {
            endShortcutCapture(mode: mode, group: group, resumeRuntime: true)
            return
        }

        stop()
        status = .starting

        var failures: [String] = []
        do {
            try startACK05Process(mode: mode, group: group)
        } catch {
            failures.append(error.localizedDescription)
        }
        do {
            try startGenericHIDNativeEventSuppressorIfEnabled()
            try startGenericHIDRuntimeWithHandoffRetry()
        } catch {
            genericHIDRuntime.stop()
            genericHIDNativeEventSuppressor.stop()
            failures.append(error.localizedDescription)
        }
        if process != nil || genericHIDRuntime.isRunning {
            status = failures.isEmpty ? .running : .degraded(failures.joined(separator: " "))
        } else {
            status = .failed(failures.joined(separator: " "))
        }
    }

    func beginShortcutCapture(
        onGenericHIDCaptured: @escaping (String, GenericHIDInputBindingKey) -> Void
    ) throws {
        if isShortcutCaptureActive {
            genericHIDRuntime.beginCapture(onCaptured: onGenericHIDCaptured)
            return
        }

        stopACK05Process()
        genericRuntimeStartedForCapture = !genericHIDRuntime.isRunning
        do {
            try startGenericHIDNativeEventSuppressorIfEnabled()
            if genericRuntimeStartedForCapture {
                try startGenericHIDRuntimeWithHandoffRetry()
            }
            genericHIDRuntime.beginCapture(onCaptured: onGenericHIDCaptured)
            isShortcutCaptureActive = true
            status = .running
        } catch {
            if genericRuntimeStartedForCapture {
                genericHIDRuntime.stop()
                genericHIDNativeEventSuppressor.stop()
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
        guard isShortcutCaptureActive else {
            if !resumeRuntime, genericRuntimeStartedForCapture {
                genericHIDRuntime.stop()
                genericHIDNativeEventSuppressor.stop()
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
            stopACK05Process()
            genericHIDRuntime.stop()
            genericHIDNativeEventSuppressor.stop()
            genericRuntimeStartedForCapture = false
            status = .stopped
            return
        }

        genericRuntimeStartedForCapture = false
        var failure: String?
        do {
            try startGenericHIDNativeEventSuppressorIfEnabled()
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

    private func startGenericHIDNativeEventSuppressorIfEnabled() throws {
        guard !genericHIDSuppressionDisabledForDiagnostics else { return }
        if !genericHIDNativeEventSuppressor.isRunning {
            try genericHIDNativeEventSuppressor.start()
        }
    }

    private func startGenericHIDRuntimeWithHandoffRetry() throws {
        let maximumAttempts = 16
        let retryInterval: TimeInterval = 0.10

        for attempt in 1...maximumAttempts {
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
                Thread.sleep(forTimeInterval: retryInterval)
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
            Task { @MainActor in
                guard let self, self.process === terminatedProcess else { return }
                self.process = nil
                guard !self.isShortcutCaptureActive else { return }
                let detail = Self.errorDetail(from: errorPipe)
                    ?? L10n.text("cli.exited", exitStatus)
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

    private func stopACK05Process() {
        guard let process else { return }
        self.process = nil
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }

    private static func errorDetail(from pipe: Pipe) -> String? {
        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let output = String(data: data, encoding: .utf8)
        else { return nil }
        let firstLine = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.isEmpty })
        if firstLine?.localizedCaseInsensitiveContains("HID access was denied") == true {
            return L10n.text("cli.inputPermission")
        }
        return firstLine
    }

    func restart(mode: RekordboxMappingMode, group: Int) {
        start(mode: mode, group: group)
    }

    func stop() {
        isShortcutCaptureActive = false
        genericRuntimeStartedForCapture = false
        genericHIDRuntime.endCapture()
        genericHIDRuntime.stop()
        genericHIDNativeEventSuppressor.stop()
        stopACK05Process()
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

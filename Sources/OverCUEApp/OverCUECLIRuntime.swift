import Foundation
import OverCUECore

@MainActor
final class OverCUECLIRuntime {
    enum Status: Equatable {
        case stopped
        case starting
        case running
        case failed(String)

        var displayText: String {
            switch self {
            case .stopped: "ACK05停止中"
            case .starting: "ACK05起動中"
            case .running: "ACK05入力待機中"
            case let .failed(message): "ACK05起動失敗: \(message)"
            }
        }
    }

    var onStatusChanged: ((Status) -> Void)?

    private var process: Process?
    private(set) var status: Status = .stopped {
        didSet { onStatusChanged?(status) }
    }

    func start(mode: RekordboxMappingMode) {
        stop()
        status = .starting

        guard let launch = launchConfiguration(mode: mode) else {
            status = .failed("overcue-cliが見つかりません")
            return
        }

        let process = Process()
        process.executableURL = launch.executableURL
        process.arguments = launch.arguments
        process.currentDirectoryURL = launch.currentDirectoryURL
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] terminatedProcess in
            let exitStatus = terminatedProcess.terminationStatus
            Task { @MainActor in
                guard let self, self.process === terminatedProcess else { return }
                self.process = nil
                if exitStatus == 0 {
                    self.status = .stopped
                } else {
                    self.status = .failed("overcue-cliが終了しました（\(exitStatus)）")
                }
            }
        }

        do {
            try process.run()
            self.process = process
            status = .running
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func restart(mode: RekordboxMappingMode) {
        start(mode: mode)
    }

    func stop() {
        guard let process else {
            status = .stopped
            return
        }
        self.process = nil
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        status = .stopped
    }

    private func launchConfiguration(mode: RekordboxMappingMode) -> LaunchConfiguration? {
        let arguments = [
            "--output", "mouse",
            "--rekordbox-mode", mode.rawValue,
            "--no-accessibility-prompt",
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

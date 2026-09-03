import Foundation
import OverCUECore

struct GenericHIDShortcutBinding: Identifiable, Equatable {
    let logicalDeviceID: String
    let deviceName: String
    let input: GenericHIDInputBindingKey
    let target: ActionTarget

    var id: String {
        "\(logicalDeviceID):\(input.overCUEStableSortKey)"
    }

    var label: String {
        "\(deviceName) · \(input.overCUEDisplayName)"
    }
}

/// Generic HID adapter for the existing Shortcuts capture lifecycle.
///
/// Shortcuts remains the only mapping editor. ACK05 uses its existing direct
/// capture monitor. Generic HID never opens a second manager for Learn: the
/// already-running Generic HID runtime temporarily intercepts the first
/// persistable descriptor to the unified Learn session owner.
@MainActor
final class GenericHIDShortcutCaptureModel: ObservableObject {
    @Published private(set) var bindingsByTarget: [String: [GenericHIDShortcutBinding]] = [:]
    @Published private(set) var isCapturing = false
    @Published private(set) var captureEntryID: String?
    @Published private(set) var captureMessage: String?
    @Published private(set) var errorMessage: String?

    private var learnSession = UnifiedShortcutLearnSession()
    private var finishingCapture = false
    private let diagnosticsEnabled = ProcessInfo.processInfo.environment[
        "OVERCUE_GENERIC_HID_DIAGNOSTICS"
    ] == "1"

    func reload(shortcutModel: ShortcutSettingsModel) {
        do {
            let configuration = try OverCUEConfigurationFileStore.readCurrent(
                at: OverCUEAppConfigurationLocation.url
            )
            guard shortcutModel.availablePresetGroups.indices.contains(shortcutModel.selectedGroup - 1)
            else {
                bindingsByTarget = [:]
                return
            }
            let editorPresetID = shortcutModel.availablePresetGroups[
                shortcutModel.selectedGroup - 1
            ].id
            var result: [String: [GenericHIDShortcutBinding]] = [:]

            let scopes = GenericHIDShortcutEditorScopeResolver.scopes(
                configuration: configuration,
                profileName: configuration.defaultProfile,
                editorPresetID: editorPresetID
            )
            for scope in scopes {
                guard let logicalDevice = configuration.logicalDevices[scope.logicalDeviceID]
                else { continue }
                let mapping = try GenericHIDMappingStore.mapping(
                    logicalDeviceID: scope.logicalDeviceID,
                    presetID: scope.presetID
                )
                diagnosticLog(
                    "reload logical=\(scope.logicalDeviceID) preset=\(scope.presetID) mappings=\(mapping.count)"
                )
                for (input, target) in mapping {
                    result[target.configurationValue, default: []].append(
                        GenericHIDShortcutBinding(
                            logicalDeviceID: scope.logicalDeviceID,
                            deviceName: logicalDevice.name,
                            input: input,
                            target: target
                        )
                    )
                }
            }

            for key in result.keys {
                result[key]?.sort { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            }
            bindingsByTarget = result
            errorMessage = nil
        } catch {
            bindingsByTarget = [:]
            errorMessage = error.localizedDescription
            diagnosticLog("reload failed error=\(error.localizedDescription)")
        }
    }

    func labels(for entry: RekordboxShortcutEntry) -> [String] {
        bindingsByTarget[target(for: entry).configurationValue, default: []].map(\.label)
    }

    func isConfigured(_ entry: RekordboxShortcutEntry) -> Bool {
        !labels(for: entry).isEmpty
    }

    func beginUnifiedCapture(
        for entry: RekordboxShortcutEntry,
        shortcutModel: ShortcutSettingsModel
    ) {
        guard !isCapturing else {
            diagnosticLog("begin rejected: another unified Learn session is active")
            return
        }
        finishingCapture = false
        errorMessage = nil

        guard shortcutModel.availablePresetGroups.indices.contains(shortcutModel.selectedGroup - 1)
        else {
            errorMessage = "Preset is not available."
            diagnosticLog("begin rejected: selected preset unavailable")
            return
        }

        let editorPresetID = shortcutModel.availablePresetGroups[
            shortcutModel.selectedGroup - 1
        ].id
        let captureTarget = target(for: entry)
        guard learnSession.begin(editorPresetID: editorPresetID, target: captureTarget) != nil
        else {
            errorMessage = "Another Learn session is already active."
            diagnosticLog("begin rejected: session owner is not terminal")
            return
        }
        captureEntryID = entry.id
        captureMessage = L10n.text("message.capturePrompt")
        isCapturing = true
        diagnosticLog(
            "begin entry=\(entry.commandID) target=\(captureTarget.configurationValue) editorPreset=\(editorPresetID)"
        )

        let availability = shortcutModel.beginUnifiedCapture(
            for: entry,
            onGenericHIDCaptured: { [weak self, weak shortcutModel] logicalDeviceID, input in
                guard let self, let shortcutModel else { return }
                self.commitGenericCapture(
                    logicalDeviceID: logicalDeviceID,
                    input: input,
                    shortcutModel: shortcutModel
                )
            },
            claimACK05: { [weak self] in
                self?.claimACK05Capture() ?? false
            },
            onACK05Completed: { [weak self, weak shortcutModel] error in
                guard let self, let shortcutModel else { return }
                self.completeACK05Capture(error: error, shortcutModel: shortcutModel)
            }
        )
        for backend in availability.startedBackends {
            learnSession.backendStarted(backend)
        }
        for (backend, error) in availability.errors {
            learnSession.backendFailed(backend)
            diagnosticLog("backend unavailable backend=\(backend.rawValue) error=\(error)")
        }
        if !learnSession.hasAvailableBackend {
            errorMessage = availability.errors.values.sorted().joined(separator: " ")
            learnSession.cancel()
            shortcutModel.endUnifiedCapture()
            finishCapture()
        }
    }

    func cancelUnifiedCapture(shortcutModel: ShortcutSettingsModel) {
        diagnosticLog("cancel requested")
        finishingCapture = true
        learnSession.cancel()
        shortcutModel.endUnifiedCapture()
        finishCapture()
    }

    func removeBindings(
        for entry: RekordboxShortcutEntry,
        shortcutModel: ShortcutSettingsModel
    ) {
        guard shortcutModel.availablePresetGroups.indices.contains(shortcutModel.selectedGroup - 1)
        else { return }
        let editorPresetID = shortcutModel.availablePresetGroups[
            shortcutModel.selectedGroup - 1
        ].id
        let target = target(for: entry)
        do {
            let configuration = try OverCUEConfigurationFileStore.readCurrent(
                at: OverCUEAppConfigurationLocation.url
            )
            let scopes = GenericHIDShortcutEditorScopeResolver.scopes(
                configuration: configuration,
                profileName: configuration.defaultProfile,
                editorPresetID: editorPresetID
            )
            try GenericHIDMappingStore.removeTarget(
                logicalDeviceIDs: Set(scopes.map(\.logicalDeviceID)),
                presetID: editorPresetID,
                target: target
            )
            reload(shortcutModel: shortcutModel)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitGenericCapture(
        logicalDeviceID: String,
        input: GenericHIDInputBindingKey,
        shortcutModel: ShortcutSettingsModel
    ) {
        guard !finishingCapture else {
            diagnosticLog("commit ignored: finishingCapture=true")
            return
        }
        guard let context = learnSession.claim(by: .genericHID) else {
            diagnosticLog("commit ignored: Generic HID did not win the session")
            return
        }
        finishingCapture = true
        diagnosticLog(
            "commit logical=\(logicalDeviceID) editorPreset=\(context.editorPresetID) target=\(context.target.configurationValue) input=\(input.overCUEStableSortKey)"
        )

        var persistenceError: String?
        do {
            let configuration = try OverCUEConfigurationFileStore.readCurrent(
                at: OverCUEAppConfigurationLocation.url
            )
            guard configuration.profiles[configuration.defaultProfile]?.presetGroup(
                id: context.editorPresetID
            ) != nil else {
                throw GenericHIDShortcutCaptureError.editorPresetRemoved
            }
            try GenericHIDMappingStore.assign(
                logicalDeviceID: logicalDeviceID,
                presetID: context.editorPresetID,
                input: input,
                target: context.target
            )
            errorMessage = nil
            diagnosticLog("assign success")
        } catch {
            persistenceError = error.localizedDescription
            diagnosticLog("assign failed error=\(error.localizedDescription)")
        }

        learnSession.complete(by: .genericHID)
        shortcutModel.endUnifiedCapture()
        reload(shortcutModel: shortcutModel)
        if let persistenceError { errorMessage = persistenceError }
        finishCapture()
    }

    private enum GenericHIDShortcutCaptureError: LocalizedError {
        case editorPresetRemoved

        var errorDescription: String? {
            switch self {
            case .editorPresetRemoved:
                return "The editor Preset selected when Learn started no longer exists."
            }
        }
    }

    private func claimACK05Capture() -> Bool {
        let won = learnSession.claim(by: .ack05) != nil
        diagnosticLog("ACK05 claim won=\(won)")
        return won
    }

    private func completeACK05Capture(
        error: String?,
        shortcutModel: ShortcutSettingsModel
    ) {
        guard !finishingCapture else { return }
        finishingCapture = true
        if let error { errorMessage = error }
        learnSession.complete(by: .ack05)
        shortcutModel.endUnifiedCapture()
        reload(shortcutModel: shortcutModel)
        if let error { errorMessage = error }
        finishCapture()
    }

    private func finishCapture() {
        diagnosticLog("finish")
        captureEntryID = nil
        captureMessage = nil
        isCapturing = false
        finishingCapture = false
    }

    private func diagnosticLog(_ message: @autoclosure () -> String) {
        guard diagnosticsEnabled else { return }
        print("[GenericHIDCapture] \(message())")
    }

    private func target(for entry: RekordboxShortcutEntry) -> ActionTarget {
        if entry.commandID.hasPrefix("overcue:"),
           let action = ActionID(rawValue: String(entry.commandID.dropFirst("overcue:".count))) {
            return .action(action)
        }
        return RekordboxActionAdapter.target(for: entry.commandID)
    }
}

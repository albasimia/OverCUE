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
/// persistable descriptor and reports it through the capture broker.
@MainActor
final class GenericHIDShortcutCaptureModel: ObservableObject {
    @Published private(set) var bindingsByTarget: [String: [GenericHIDShortcutBinding]] = [:]
    @Published private(set) var isCapturing = false
    @Published private(set) var captureEntryID: String?
    @Published private(set) var captureMessage: String?
    @Published private(set) var errorMessage: String?

    private var capturedTarget: ActionTarget?
    private var capturedFallbackPresetID: String?
    private var finishingCapture = false
    private var runtimeStatusSuppressed = false
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
            let fallbackPresetID = shortcutModel.availablePresetGroups[
                shortcutModel.selectedGroup - 1
            ].id
            var result: [String: [GenericHIDShortcutBinding]] = [:]

            for (logicalDeviceID, logicalDevice) in configuration.logicalDevices.sorted(by: { $0.key < $1.key }) {
                guard logicalDevice.profileName == configuration.defaultProfile,
                      configuration.physicalDeviceBindings.contains(where: {
                          $0.logicalDeviceID == logicalDeviceID && $0.kind == .genericHID
                      })
                else { continue }

                let presetID = configuration.assignedPresetID(for: logicalDeviceID)
                    ?? fallbackPresetID
                let mapping = try GenericHIDMappingStore.mapping(
                    logicalDeviceID: logicalDeviceID,
                    presetID: presetID
                )
                diagnosticLog(
                    "reload logical=\(logicalDeviceID) preset=\(presetID) mappings=\(mapping.count)"
                )
                for (input, target) in mapping {
                    result[target.configurationValue, default: []].append(
                        GenericHIDShortcutBinding(
                            logicalDeviceID: logicalDeviceID,
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
        finishingCapture = false
        errorMessage = nil

        guard shortcutModel.availablePresetGroups.indices.contains(shortcutModel.selectedGroup - 1)
        else {
            errorMessage = "Preset is not available."
            diagnosticLog("begin rejected: selected preset unavailable")
            return
        }

        let fallbackPresetID = shortcutModel.availablePresetGroups[
            shortcutModel.selectedGroup - 1
        ].id
        capturedTarget = target(for: entry)
        capturedFallbackPresetID = fallbackPresetID
        captureEntryID = entry.id
        captureMessage = L10n.text("message.capturePrompt")
        isCapturing = true
        beginRuntimeStatusSuppressionIfNeeded()
        diagnosticLog(
            "begin entry=\(entry.commandID) target=\(target(for: entry).configurationValue) fallbackPreset=\(fallbackPresetID)"
        )

        GenericHIDShortcutCaptureBroker.shared.prepare { [weak self, weak shortcutModel] logicalDeviceID, input in
            guard let self, let shortcutModel else { return }
            self.diagnosticLog(
                "broker captured logical=\(logicalDeviceID) input=\(input.overCUEStableSortKey)"
            )
            self.commitGenericCapture(
                logicalDeviceID: logicalDeviceID,
                input: input,
                shortcutModel: shortcutModel
            )
        }

        // This is the existing ACK05 Shortcuts capture entry point. Its
        // runtimeBridge.stop() call consumes the broker and switches Generic HID
        // into capture mode without closing the already-running manager.
        shortcutModel.beginCapture(for: entry)
        diagnosticLog("begin ACK05 capture active=\(shortcutModel.isCapturing)")
        if !shortcutModel.isCapturing {
            diagnosticLog("begin abort: ACK05 capture did not stay active")
            GenericHIDShortcutCaptureBroker.shared.cancelPrepared()
            finishCapture(shortcutModel: shortcutModel)
        }
    }

    /// ACK05 completion happens inside ShortcutSettingsModel. When its existing
    /// capture session ends, the runtime bridge also leaves Generic HID capture
    /// mode and resumes ACK05 without reopening Generic HID.
    func shortcutCaptureDidChange(
        isCapturing shortcutIsCapturing: Bool,
        shortcutModel: ShortcutSettingsModel
    ) {
        guard isCapturing else { return }
        diagnosticLog(
            "shortcut capture changed shortcutActive=\(shortcutIsCapturing) finishing=\(finishingCapture)"
        )
        guard !shortcutIsCapturing, !finishingCapture else { return }
        finishCapture(shortcutModel: shortcutModel)
    }

    func cancelUnifiedCapture(shortcutModel: ShortcutSettingsModel) {
        diagnosticLog("cancel requested")
        finishingCapture = true
        GenericHIDShortcutCaptureBroker.shared.cancelPrepared()
        if shortcutModel.isCapturing {
            shortcutModel.cancelCapture()
        }
        finishCapture(shortcutModel: shortcutModel)
    }

    func removeBindings(
        for entry: RekordboxShortcutEntry,
        shortcutModel: ShortcutSettingsModel
    ) {
        guard shortcutModel.availablePresetGroups.indices.contains(shortcutModel.selectedGroup - 1)
        else { return }
        let fallbackPresetID = shortcutModel.availablePresetGroups[
            shortcutModel.selectedGroup - 1
        ].id
        let target = target(for: entry)
        do {
            let configuration = try OverCUEConfigurationFileStore.readCurrent(
                at: OverCUEAppConfigurationLocation.url
            )
            let logicalDeviceIDs = Set(configuration.physicalDeviceBindings.compactMap { binding -> String? in
                guard binding.kind == .genericHID,
                      configuration.logicalDevices[binding.logicalDeviceID]?.profileName
                        == configuration.defaultProfile
                else { return nil }
                return binding.logicalDeviceID
            })
            for logicalDeviceID in logicalDeviceIDs {
                let presetID = configuration.assignedPresetID(for: logicalDeviceID)
                    ?? fallbackPresetID
                try GenericHIDMappingStore.removeTarget(
                    logicalDeviceIDs: [logicalDeviceID],
                    presetID: presetID,
                    target: target
                )
            }
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
        guard let target = capturedTarget else {
            diagnosticLog("commit ignored: capturedTarget=nil")
            return
        }
        guard let fallbackPresetID = capturedFallbackPresetID else {
            diagnosticLog("commit ignored: fallbackPreset=nil")
            return
        }
        finishingCapture = true

        let latestConfiguration = try? OverCUEConfigurationFileStore.readCurrent(
            at: OverCUEAppConfigurationLocation.url
        )
        let assignedPresetID = latestConfiguration?.assignedPresetID(for: logicalDeviceID)
        let presetID = assignedPresetID ?? fallbackPresetID
        diagnosticLog(
            "commit logical=\(logicalDeviceID) assignedPreset=\(assignedPresetID ?? "nil") resolvedPreset=\(presetID) target=\(target.configurationValue) input=\(input.overCUEStableSortKey)"
        )

        do {
            try GenericHIDMappingStore.assign(
                logicalDeviceID: logicalDeviceID,
                presetID: presetID,
                input: input,
                target: target
            )
            errorMessage = nil
            let persistedCount = (try? GenericHIDMappingStore.mapping(
                logicalDeviceID: logicalDeviceID,
                presetID: presetID
            ).count) ?? -1
            diagnosticLog("assign success persistedMappings=\(persistedCount)")
        } catch {
            errorMessage = error.localizedDescription
            diagnosticLog("assign failed error=\(error.localizedDescription)")
        }

        // Existing cancelCapture tears down ACK05 capture and calls
        // runtimeBridge.start(). The bridge recognizes the active unified
        // capture and resumes ACK05 only; Generic HID stays continuously open.
        if shortcutModel.isCapturing {
            diagnosticLog("commit cancelling ACK05 capture to resume runtime")
            shortcutModel.cancelCapture()
        }
        reload(shortcutModel: shortcutModel)
        finishCapture(shortcutModel: shortcutModel)
    }

    private func finishCapture(shortcutModel: ShortcutSettingsModel) {
        diagnosticLog("finish")
        GenericHIDShortcutCaptureBroker.shared.cancelPrepared()
        endRuntimeStatusSuppressionIfNeeded()
        capturedTarget = nil
        capturedFallbackPresetID = nil
        captureEntryID = nil
        captureMessage = nil
        isCapturing = false
        finishingCapture = false
    }

    private func beginRuntimeStatusSuppressionIfNeeded() {
        guard !runtimeStatusSuppressed else { return }
        OverCUERuntimeStatusDeliveryGate.shared.beginSuppression()
        runtimeStatusSuppressed = true
        diagnosticLog("runtime status suppression ON")
    }

    private func endRuntimeStatusSuppressionIfNeeded() {
        guard runtimeStatusSuppressed else { return }
        OverCUERuntimeStatusDeliveryGate.shared.endSuppression()
        runtimeStatusSuppressed = false
        diagnosticLog("runtime status suppression OFF")
    }

    private func diagnosticLog(_ message: String) {
        guard diagnosticsEnabled else { return }
        print("[GenericHIDCapture] \(message)")
    }

    private func target(for entry: RekordboxShortcutEntry) -> ActionTarget {
        if entry.commandID.hasPrefix("overcue:"),
           let action = ActionID(rawValue: String(entry.commandID.dropFirst("overcue:".count))) {
            return .action(action)
        }
        return RekordboxActionAdapter.target(for: entry.commandID)
    }
}

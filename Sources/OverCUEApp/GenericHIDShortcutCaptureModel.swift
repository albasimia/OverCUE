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
/// already-running exclusive Generic HID runtime temporarily intercepts the
/// first persistable descriptor and reports it through the capture broker.
@MainActor
final class GenericHIDShortcutCaptureModel: ObservableObject {
    @Published private(set) var bindingsByTarget: [String: [GenericHIDShortcutBinding]] = [:]
    @Published private(set) var isCapturing = false
    @Published private(set) var captureEntryID: String?
    @Published private(set) var captureMessage: String?
    @Published private(set) var errorMessage: String?

    private var capturedTarget: ActionTarget?
    private var capturedPresetID: String?
    private var finishingCapture = false

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
            let presetID = shortcutModel.availablePresetGroups[shortcutModel.selectedGroup - 1].id
            var result: [String: [GenericHIDShortcutBinding]] = [:]

            for (logicalDeviceID, logicalDevice) in configuration.logicalDevices.sorted(by: { $0.key < $1.key }) {
                guard logicalDevice.profileName == configuration.defaultProfile,
                      configuration.physicalDeviceBindings.contains(where: {
                          $0.logicalDeviceID == logicalDeviceID && $0.kind == .genericHID
                      })
                else { continue }

                let mapping = try GenericHIDMappingStore.mapping(
                    logicalDeviceID: logicalDeviceID,
                    presetID: presetID
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
            return
        }

        let presetID = shortcutModel.availablePresetGroups[shortcutModel.selectedGroup - 1].id
        capturedTarget = target(for: entry)
        capturedPresetID = presetID
        captureEntryID = entry.id
        captureMessage = L10n.text("message.capturePrompt")
        isCapturing = true

        GenericHIDShortcutCaptureBroker.shared.prepare { [weak self, weak shortcutModel] logicalDeviceID, input in
            guard let self, let shortcutModel else { return }
            self.commitGenericCapture(
                logicalDeviceID: logicalDeviceID,
                input: input,
                shortcutModel: shortcutModel
            )
        }

        // This is the existing ACK05 Shortcuts capture entry point. Its
        // runtimeBridge.stop() call consumes the broker and switches Generic HID
        // into capture mode without closing its exclusive IOHIDManager.
        shortcutModel.beginCapture(for: entry)
        if !shortcutModel.isCapturing {
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
        guard !shortcutIsCapturing, !finishingCapture else { return }
        finishCapture(shortcutModel: shortcutModel)
    }

    func cancelUnifiedCapture(shortcutModel: ShortcutSettingsModel) {
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
        let presetID = shortcutModel.availablePresetGroups[shortcutModel.selectedGroup - 1].id
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
            try GenericHIDMappingStore.removeTarget(
                logicalDeviceIDs: logicalDeviceIDs,
                presetID: presetID,
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
        guard !finishingCapture,
              let target = capturedTarget,
              let presetID = capturedPresetID
        else { return }
        finishingCapture = true

        do {
            try GenericHIDMappingStore.assign(
                logicalDeviceID: logicalDeviceID,
                presetID: presetID,
                input: input,
                target: target
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        // Existing cancelCapture tears down ACK05 capture and calls
        // runtimeBridge.start(). The bridge recognizes the active unified
        // capture and resumes ACK05 only; Generic HID stays continuously open.
        if shortcutModel.isCapturing {
            shortcutModel.cancelCapture()
        }
        reload(shortcutModel: shortcutModel)
        finishCapture(shortcutModel: shortcutModel)
    }

    private func finishCapture(shortcutModel: ShortcutSettingsModel) {
        GenericHIDShortcutCaptureBroker.shared.cancelPrepared()
        capturedTarget = nil
        capturedPresetID = nil
        captureEntryID = nil
        captureMessage = nil
        isCapturing = false
        finishingCapture = false
    }

    private func target(for entry: RekordboxShortcutEntry) -> ActionTarget {
        if entry.commandID.hasPrefix("overcue:"),
           let action = ActionID(rawValue: String(entry.commandID.dropFirst("overcue:".count))) {
            return .action(action)
        }
        return RekordboxActionAdapter.target(for: entry.commandID)
    }
}

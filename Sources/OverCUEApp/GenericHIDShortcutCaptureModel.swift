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
/// Shortcuts remains the only mapping editor. The existing ACK05 capture owns
/// the overall edit session; Generic HID monitors run alongside it while the
/// normal runtime is disabled. Whichever physical input is captured first wins,
/// then both capture adapters are stopped before runtime is restored.
@MainActor
final class GenericHIDShortcutCaptureModel: ObservableObject {
    @Published private(set) var bindingsByTarget: [String: [GenericHIDShortcutBinding]] = [:]
    @Published private(set) var isCapturing = false
    @Published private(set) var captureEntryID: String?
    @Published private(set) var captureMessage: String?
    @Published private(set) var errorMessage: String?

    private var monitors: [String: GenericHIDLearnMonitor] = [:]
    private var capturedTarget: ActionTarget?
    private var capturedPresetID: String?
    private var restoreBridgeAfterCapture = false
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
        cancelGenericMonitors()
        finishingCapture = false
        errorMessage = nil

        guard shortcutModel.availablePresetGroups.indices.contains(shortcutModel.selectedGroup - 1)
        else {
            errorMessage = "Preset is not available."
            return
        }

        let presetID = shortcutModel.availablePresetGroups[shortcutModel.selectedGroup - 1].id
        let target = target(for: entry)
        let wasEnabled = shortcutModel.isBridgeEnabled
        restoreBridgeAfterCapture = wasEnabled
        if wasEnabled {
            shortcutModel.setBridgeEnabled(false)
        }

        // Reuse the existing Shortcuts ACK05 capture session instead of creating
        // a second mapping workflow. Runtime remains disabled until either ACK05
        // or Generic HID wins the capture.
        shortcutModel.beginCapture(for: entry)
        capturedTarget = target
        capturedPresetID = presetID
        captureEntryID = entry.id
        isCapturing = shortcutModel.isCapturing
        captureMessage = L10n.text("message.capturePrompt")

        do {
            let configuration = try OverCUEConfigurationFileStore.readCurrent(
                at: OverCUEAppConfigurationLocation.url
            )
            let bindings = configuration.physicalDeviceBindings
                .filter { binding in
                    guard binding.kind == .genericHID,
                          binding.serialNumber != nil,
                          let logical = configuration.logicalDevices[binding.logicalDeviceID]
                    else { return false }
                    return logical.profileName == configuration.defaultProfile
                }
                .sorted { lhs, rhs in lhs.logicalDeviceID < rhs.logicalDeviceID }

            for binding in bindings {
                // One Generic HID binding per Logical Device is the supported
                // registration shape. Ignore duplicate physical records here so
                // a single device cannot be seized twice during capture.
                guard monitors[binding.logicalDeviceID] == nil else { continue }
                let logicalDeviceID = binding.logicalDeviceID
                let monitor = GenericHIDLearnMonitor(binding: binding)
                monitor.onCaptured = { [weak self, weak shortcutModel] input in
                    Task { @MainActor in
                        guard let self, let shortcutModel else { return }
                        self.commitGenericCapture(
                            logicalDeviceID: logicalDeviceID,
                            input: input,
                            shortcutModel: shortcutModel
                        )
                    }
                }
                do {
                    try monitor.start()
                    monitors[logicalDeviceID] = monitor
                } catch {
                    // ACK05 capture can still continue if one Generic HID is
                    // unavailable. Surface the hardware error without destroying
                    // the unified edit session.
                    errorMessage = error.localizedDescription
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Call when ShortcutSettingsModel.isCapturing changes. ACK05 completion
    /// happens inside ShortcutSettingsModel, so this closes any parallel Generic
    /// HID monitors before restoring the runtime bridge.
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
        cancelGenericMonitors()
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

        cancelGenericMonitors()
        if shortcutModel.isCapturing {
            // The bridge is intentionally disabled for the whole unified capture,
            // so cancelCapture only tears down the ACK05 monitor here; it cannot
            // race a runtime restart against the Generic HID release.
            shortcutModel.cancelCapture()
        }
        reload(shortcutModel: shortcutModel)
        finishCapture(shortcutModel: shortcutModel)
    }

    private func finishCapture(shortcutModel: ShortcutSettingsModel) {
        cancelGenericMonitors()
        capturedTarget = nil
        capturedPresetID = nil
        captureEntryID = nil
        captureMessage = nil
        isCapturing = false
        finishingCapture = false

        if restoreBridgeAfterCapture {
            restoreBridgeAfterCapture = false
            shortcutModel.setBridgeEnabled(true)
        }
    }

    private func cancelGenericMonitors() {
        for monitor in monitors.values {
            monitor.stop()
        }
        monitors = [:]
    }

    private func target(for entry: RekordboxShortcutEntry) -> ActionTarget {
        if entry.commandID.hasPrefix("overcue:"),
           let action = ActionID(rawValue: String(entry.commandID.dropFirst("overcue:".count))) {
            return .action(action)
        }
        return RekordboxActionAdapter.target(for: entry.commandID)
    }
}

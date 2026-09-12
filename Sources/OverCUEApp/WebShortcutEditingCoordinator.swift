import Foundation
import OverCUECore

struct WebShortcutEditorCommand: Decodable {
    enum Action: String, Decodable {
        case selectEntry
        case selectKey
        case selectDial
        case setPreset
        case addPreset
        case renamePreset
        case deletePreset
        case setMode
        case reload
        case beginLearn
        case cancelLearn
        case removeBindings
        case confirmOverwrite
        case cancelOverwrite
        case rotateDevice
        case setLanguage
    }

    let action: Action
    let entryID: String?
    let keyID: String?
    let direction: String?
    let presetID: String?
    let mode: String?
    let name: String?
    let language: String?
}

struct WebShortcutPresetOption: Encodable {
    let id: String
    let name: String
    let order: Int
    let mode: String?
}

struct WebShortcutAssignmentSummary: Encodable {
    let functionName: String
    let shortcut: String?
}

struct WebShortcutKeySummary: Encodable {
    let id: String
    let assignment: WebShortcutAssignmentSummary?
    let pressed: Bool
    let selected: Bool
    let highlighted: Bool
}

struct WebShortcutDialSummary: Encodable {
    let direction: String
    let assignment: WebShortcutAssignmentSummary?
    let active: Bool
    let selected: Bool
    let highlighted: Bool
}

struct WebShortcutEntrySummary: Encodable {
    let id: String
    let commandID: String
    let description: String
    let shortcut: String
    let category: String
    let isInternal: Bool
    let configured: Bool
    let bindings: [String]
}

struct WebShortcutCaptureSummary: Encodable {
    let isCapturing: Bool
    let entryID: String?
    let message: String?
    let error: String?
    let overwriteMessage: String?
}

struct WebLanguageOption: Encodable {
    let id: String
    let name: String
}

struct WebLocalizationSummary: Encodable {
    let language: String
    let languages: [WebLanguageOption]
    let strings: [String: String]
}

struct WebShortcutEditorPanel: Encodable {
    let deviceKind: String
    let deviceName: String
    let rotationQuarterTurns: Int
    let presetID: String?
    let presetName: String?
    let presetOrder: Int?
    let presets: [WebShortcutPresetOption]
    let mode: String
    let mappingName: String
    let mappingFileName: String?
    let mappingError: String?
    let selectedEntryID: String?
    let selectedKeyID: String?
    let selectedDialDirection: String?
    let keys: [WebShortcutKeySummary]
    let dial: [WebShortcutDialSummary]
    let entries: [WebShortcutEntrySummary]
    let capture: WebShortcutCaptureSummary
    let localization: WebLocalizationSummary
}

struct WebShortcutLiveKeySummary: Encodable {
    let id: String
    let pressed: Bool
}

struct WebShortcutLiveDialSummary: Encodable {
    let direction: String
    let active: Bool
}

struct WebShortcutLiveState: Encodable {
    let keys: [WebShortcutLiveKeySummary]
    let dial: [WebShortcutLiveDialSummary]
    let capture: WebShortcutCaptureSummary
}

@MainActor
final class WebShortcutEditingCoordinator {
    private let genericHIDModel = GenericHIDShortcutCaptureModel()
    private var loadedGenericPresetID: String?

    func hasActiveCapture(shortcutModel: ShortcutSettingsModel) -> Bool {
        shortcutModel.isCapturing || genericHIDModel.isCapturing
    }

    func makePanel(shortcutModel: ShortcutSettingsModel) -> WebShortcutEditorPanel {
        ensureGenericBindingsLoaded(shortcutModel: shortcutModel)

        let preset = selectedPreset(shortcutModel)
        let ack05Name = ack05DeviceName(shortcutModel: shortcutModel)
        let highlightedKeys = shortcutModel.highlightedKeys
        let highlightedDialDirections = shortcutModel.highlightedDialDirections

        let keys = ACK05Key.allCases.map { key in
            WebShortcutKeySummary(
                id: key.rawValue,
                assignment: shortcutModel.deviceAssignment(to: key).map {
                    WebShortcutAssignmentSummary(
                        functionName: $0.functionName,
                        shortcut: $0.shortcut
                    )
                },
                pressed: shortcutModel.pressedDeviceKeys.contains(key),
                selected: shortcutModel.selectedDeviceKey == key,
                highlighted: highlightedKeys.contains(key)
            )
        }

        let dial = dialDirections(shortcutModel: shortcutModel).map { direction, value in
            WebShortcutDialSummary(
                direction: value,
                assignment: shortcutModel.dialAssignment(direction).map {
                    WebShortcutAssignmentSummary(
                        functionName: $0.functionName,
                        shortcut: $0.shortcut
                    )
                },
                active: shortcutModel.activeDialDirection == direction,
                selected: shortcutModel.selectedDialDirection == direction,
                highlighted: highlightedDialDirections.contains(direction)
            )
        }

        let internalIDs = Set(shortcutModel.internalEntries.map(\.id))
        let entries = (shortcutModel.internalEntries + shortcutModel.entries).map { entry in
            let ack05Bindings = shortcutModel.bindingLabels(for: entry).map {
                "\(ack05Name) · \($0)"
            }
            let genericBindings = genericHIDModel.labels(for: entry)
            return WebShortcutEntrySummary(
                id: entry.id,
                commandID: entry.commandID,
                description: entry.description.trimmingCharacters(in: .whitespacesAndNewlines),
                shortcut: entry.shortcut,
                category: internalIDs.contains(entry.id)
                    ? "OverCUE"
                    : RekordboxShortcutCategory.category(for: entry.commandID).rawValue,
                isInternal: internalIDs.contains(entry.id),
                configured: !ack05Bindings.isEmpty || !genericBindings.isEmpty,
                bindings: (ack05Bindings + genericBindings).sorted {
                    $0.localizedStandardCompare($1) == .orderedAscending
                }
            )
        }

        return WebShortcutEditorPanel(
            deviceKind: "ack05",
            deviceName: ack05Name,
            rotationQuarterTurns: shortcutModel.rotationQuarterTurns,
            presetID: preset?.id,
            presetName: preset?.name,
            presetOrder: preset?.order,
            presets: shortcutModel.availablePresetGroups.map {
                WebShortcutPresetOption(
                    id: $0.id,
                    name: $0.name,
                    order: $0.order,
                    mode: $0.mapping.rekordboxMode?.rawValue
                )
            },
            mode: shortcutModel.mode.rawValue,
            mappingName: shortcutModel.mappingName,
            mappingFileName: shortcutModel.mappingURL?.lastPathComponent,
            mappingError: shortcutModel.errorMessage,
            selectedEntryID: shortcutModel.selectedEntryID,
            selectedKeyID: shortcutModel.selectedDeviceKey?.rawValue,
            selectedDialDirection: shortcutModel.selectedDialDirection?.rawValue,
            keys: keys,
            dial: dial,
            entries: entries,
            capture: captureSummary(shortcutModel: shortcutModel),
            localization: localizationSummary()
        )
    }

    func makeLiveState(shortcutModel: ShortcutSettingsModel) -> WebShortcutLiveState {
        WebShortcutLiveState(
            keys: ACK05Key.allCases.map { key in
                WebShortcutLiveKeySummary(
                    id: key.rawValue,
                    pressed: shortcutModel.pressedDeviceKeys.contains(key)
                )
            },
            dial: dialDirections(shortcutModel: shortcutModel).map { direction, value in
                WebShortcutLiveDialSummary(
                    direction: value,
                    active: shortcutModel.activeDialDirection == direction
                )
            },
            capture: captureSummary(shortcutModel: shortcutModel)
        )
    }

    func perform(
        _ command: WebShortcutEditorCommand,
        shortcutModel: ShortcutSettingsModel
    ) async throws {
        switch command.action {
        case .selectEntry:
            let entry = try requireEntry(id: command.entryID, shortcutModel: shortcutModel)
            shortcutModel.select(entry)

        case .selectKey:
            guard let rawKey = command.keyID?.lowercased(),
                  let key = ACK05Key(rawValue: rawKey)
            else { throw WebShortcutEditingError.invalidKey }
            shortcutModel.selectDeviceKey(key)

        case .selectDial:
            guard let rawDirection = command.direction,
                  let direction = DialDirection(rawValue: rawDirection)
            else { throw WebShortcutEditingError.invalidDialDirection }
            shortcutModel.selectDial(direction)

        case .setPreset:
            guard let presetID = command.presetID,
                  let index = shortcutModel.availablePresetGroups.firstIndex(where: { $0.id == presetID })
            else { throw WebShortcutEditingError.presetMissing }
            guard !hasActiveCapture(shortcutModel: shortcutModel) else {
                throw WebShortcutEditingError.captureInProgress
            }
            shortcutModel.setGroup(index + 1)
            reloadGenericBindings(shortcutModel: shortcutModel)

        case .addPreset:
            guard !hasActiveCapture(shortcutModel: shortcutModel) else {
                throw WebShortcutEditingError.captureInProgress
            }
            guard let name = command.name else { throw WebShortcutEditingError.invalidPresetName }
            let result = try presetMutation {
                try PresetGroupStore.add(name: name, mode: shortcutModel.mode)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak shortcutModel] in
                guard let self, let shortcutModel else { return }
                shortcutModel.setGroup(result.index)
                self.reloadGenericBindings(shortcutModel: shortcutModel)
            }

        case .renamePreset:
            guard !hasActiveCapture(shortcutModel: shortcutModel) else {
                throw WebShortcutEditingError.captureInProgress
            }
            guard let presetID = command.presetID else { throw WebShortcutEditingError.presetMissing }
            guard let name = command.name else { throw WebShortcutEditingError.invalidPresetName }
            try presetMutation {
                try PresetGroupStore.rename(id: presetID, name: name)
            }

        case .deletePreset:
            guard !hasActiveCapture(shortcutModel: shortcutModel) else {
                throw WebShortcutEditingError.captureInProgress
            }
            guard let presetID = command.presetID else { throw WebShortcutEditingError.presetMissing }
            _ = try presetMutation {
                try PresetGroupStore.delete(id: presetID)
            }

        case .setMode:
            guard let rawMode = command.mode,
                  let mode = RekordboxMappingMode(rawValue: rawMode)
            else { throw WebShortcutEditingError.invalidMode }
            guard !hasActiveCapture(shortcutModel: shortcutModel) else {
                throw WebShortcutEditingError.captureInProgress
            }
            await shortcutModel.setMode(mode)
            reloadGenericBindings(shortcutModel: shortcutModel)

        case .reload:
            guard !hasActiveCapture(shortcutModel: shortcutModel) else {
                throw WebShortcutEditingError.captureInProgress
            }
            shortcutModel.reloadAndRestartBridge()
            reloadGenericBindings(shortcutModel: shortcutModel)

        case .beginLearn:
            let entry = try requireEntry(id: command.entryID, shortcutModel: shortcutModel)
            guard !hasActiveCapture(shortcutModel: shortcutModel) else {
                throw WebShortcutEditingError.captureInProgress
            }
            genericHIDModel.beginUnifiedCapture(for: entry, shortcutModel: shortcutModel)

        case .cancelLearn:
            if genericHIDModel.isCapturing {
                genericHIDModel.cancelUnifiedCapture(shortcutModel: shortcutModel)
            } else if shortcutModel.isCapturing {
                shortcutModel.cancelCapture()
            }
            reloadGenericBindings(shortcutModel: shortcutModel)

        case .removeBindings:
            let entry = try requireEntry(id: command.entryID, shortcutModel: shortcutModel)
            guard !hasActiveCapture(shortcutModel: shortcutModel) else {
                throw WebShortcutEditingError.captureInProgress
            }
            await genericHIDModel.removeBindings(for: entry, shortcutModel: shortcutModel)
            await shortcutModel.removeBindings(for: entry)
            reloadGenericBindings(shortcutModel: shortcutModel)

        case .confirmOverwrite:
            if genericHIDModel.overwriteConfirmation != nil {
                await genericHIDModel.confirmOverwrite(shortcutModel: shortcutModel)
            } else if shortcutModel.overwriteConfirmation != nil {
                await shortcutModel.confirmOverwrite()
            } else {
                throw WebShortcutEditingError.noOverwriteConfirmation
            }
            reloadGenericBindings(shortcutModel: shortcutModel)

        case .cancelOverwrite:
            if genericHIDModel.overwriteConfirmation != nil {
                genericHIDModel.cancelOverwrite(shortcutModel: shortcutModel)
            } else if shortcutModel.overwriteConfirmation != nil {
                shortcutModel.cancelOverwrite()
            } else {
                throw WebShortcutEditingError.noOverwriteConfirmation
            }
            reloadGenericBindings(shortcutModel: shortcutModel)

        case .rotateDevice:
            guard !hasActiveCapture(shortcutModel: shortcutModel) else {
                throw WebShortcutEditingError.captureInProgress
            }
            shortcutModel.rotateDevice()

        case .setLanguage:
            guard !hasActiveCapture(shortcutModel: shortcutModel) else {
                throw WebShortcutEditingError.captureInProgress
            }
            guard let rawLanguage = command.language,
                  let language = AppLanguage(rawValue: rawLanguage)
            else { throw WebShortcutEditingError.invalidLanguage }
            AppLocalization.shared.setLanguage(language)
        }
    }

    private func captureSummary(shortcutModel: ShortcutSettingsModel) -> WebShortcutCaptureSummary {
        WebShortcutCaptureSummary(
            isCapturing: hasActiveCapture(shortcutModel: shortcutModel),
            entryID: genericHIDModel.captureEntryID ?? shortcutModel.editingEntryID,
            message: genericHIDModel.captureMessage ?? shortcutModel.captureMessage,
            error: genericHIDModel.errorMessage ?? shortcutModel.captureError,
            overwriteMessage: genericHIDModel.overwriteConfirmation?.message
                ?? shortcutModel.overwriteConfirmation?.message
        )
    }

    private func localizationSummary() -> WebLocalizationSummary {
        let localization = AppLocalization.shared
        return WebLocalizationSummary(
            language: localization.language.rawValue,
            languages: AppLanguage.allCases.map {
                WebLanguageOption(id: $0.rawValue, name: $0.nativeName)
            },
            strings: localization.currentTable
        )
    }

    private func dialDirections(
        shortcutModel _: ShortcutSettingsModel
    ) -> [(DialDirection, String)] {
        [
            (.counterclockwise, "counterclockwise"),
            (.clockwise, "clockwise"),
        ]
    }

    private func selectedPreset(_ shortcutModel: ShortcutSettingsModel) -> OverCUEPresetGroup? {
        guard shortcutModel.availablePresetGroups.indices.contains(shortcutModel.selectedGroup - 1)
        else { return nil }
        return shortcutModel.availablePresetGroups[shortcutModel.selectedGroup - 1]
    }

    private func ack05DeviceName(shortcutModel: ShortcutSettingsModel) -> String {
        guard let configuration = try? OverCUEConfigurationFileStore.readCurrent(
            at: OverCUEAppConfigurationLocation.url
        ) else { return "ACK05" }

        if let logicalDeviceID = shortcutModel.runtimeLogicalDeviceID,
           let logicalDevice = configuration.logicalDevices[logicalDeviceID] {
            let name = logicalDevice.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }

        let ack05LogicalDeviceIDs = Set(
            configuration.physicalDeviceBindings.compactMap { binding in
                binding.kind == .ack05 ? binding.logicalDeviceID : nil
            }
        )
        if ack05LogicalDeviceIDs.count == 1,
           let logicalDeviceID = ack05LogicalDeviceIDs.first,
           let logicalDevice = configuration.logicalDevices[logicalDeviceID] {
            let name = logicalDevice.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return "ACK05"
    }

    private func requireEntry(
        id: String?,
        shortcutModel: ShortcutSettingsModel
    ) throws -> RekordboxShortcutEntry {
        guard let id else { throw WebShortcutEditingError.entryMissing }
        guard let entry = (shortcutModel.internalEntries + shortcutModel.entries)
            .first(where: { $0.id == id })
        else { throw WebShortcutEditingError.entryMissing }
        return entry
    }

    private func ensureGenericBindingsLoaded(shortcutModel: ShortcutSettingsModel) {
        let presetID = selectedPreset(shortcutModel)?.id
        guard loadedGenericPresetID != presetID else { return }
        reloadGenericBindings(shortcutModel: shortcutModel)
    }

    private func reloadGenericBindings(shortcutModel: ShortcutSettingsModel) {
        genericHIDModel.reload(shortcutModel: shortcutModel)
        loadedGenericPresetID = selectedPreset(shortcutModel)?.id
    }

    private func presetMutation<Result>(_ operation: () throws -> Result) throws -> Result {
        do {
            return try operation()
        } catch let error as PresetGroupStoreError {
            throw WebShortcutEditingError.presetMutationFailed(error.localizedDescription)
        }
    }
}

enum WebShortcutEditingError: LocalizedError {
    case entryMissing
    case invalidKey
    case invalidDialDirection
    case presetMissing
    case invalidPresetName
    case invalidMode
    case invalidLanguage
    case captureInProgress
    case noOverwriteConfirmation
    case deviceIdentifyInProgress
    case presetMutationFailed(String)

    var errorDescription: String? {
        switch self {
        case .entryMissing:
            "Shortcut entry is not available."
        case .invalidKey:
            "ACK05 key is invalid."
        case .invalidDialDirection:
            "Dial direction is invalid."
        case .presetMissing:
            "Preset is not available."
        case .invalidPresetName:
            "Preset name is required."
        case .invalidMode:
            "rekordbox mode is invalid."
        case .invalidLanguage:
            "Display language is invalid."
        case .captureInProgress:
            "Finish or cancel Learn before changing this setting."
        case .noOverwriteConfirmation:
            "There is no pending overwrite confirmation."
        case .deviceIdentifyInProgress:
            "Finish or cancel device identification before starting Learn."
        case let .presetMutationFailed(message):
            message
        }
    }
}

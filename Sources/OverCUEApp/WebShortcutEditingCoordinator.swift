import Foundation
import OverCUECore

struct WebShortcutEditorCommand: Decodable {
    enum Action: String, Decodable {
        case selectEntry
        case selectKey
        case selectDial
        case setPreset
        case setMode
        case reload
        case beginLearn
        case cancelLearn
        case removeBindings
        case confirmOverwrite
        case cancelOverwrite
        case rotateDevice
    }

    let action: Action
    let entryID: String?
    let keyID: String?
    let direction: String?
    let presetID: String?
    let mode: String?
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
}

@MainActor
final class WebShortcutEditingCoordinator {
    private let genericHIDModel = GenericHIDShortcutCaptureModel()
    private var loadedGenericPresetID: String?

    func makePanel(shortcutModel: ShortcutSettingsModel) -> WebShortcutEditorPanel {
        ensureGenericBindingsLoaded(shortcutModel: shortcutModel)

        let preset = selectedPreset(shortcutModel)
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

        let dialDirections: [(DialDirection, String)] = [
            (.counterclockwise, "counterclockwise"),
            (.clockwise, "clockwise"),
        ]
        let dial = dialDirections.map { direction, value in
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
            let ack05Bindings = shortcutModel.bindingLabels(for: entry)
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
            deviceName: "ACK05",
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
            capture: WebShortcutCaptureSummary(
                isCapturing: shortcutModel.isCapturing || genericHIDModel.isCapturing,
                entryID: genericHIDModel.captureEntryID ?? shortcutModel.editingEntryID,
                message: genericHIDModel.captureMessage ?? shortcutModel.captureMessage,
                error: genericHIDModel.errorMessage ?? shortcutModel.captureError,
                overwriteMessage: shortcutModel.overwriteConfirmation?.message
            )
        )
    }

    func perform(
        _ command: WebShortcutEditorCommand,
        shortcutModel: ShortcutSettingsModel
    ) throws {
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
            guard !isCapturing(shortcutModel) else {
                throw WebShortcutEditingError.captureInProgress
            }
            shortcutModel.setGroup(index + 1)
            reloadGenericBindings(shortcutModel: shortcutModel)

        case .setMode:
            guard let rawMode = command.mode,
                  let mode = RekordboxMappingMode(rawValue: rawMode)
            else { throw WebShortcutEditingError.invalidMode }
            guard !isCapturing(shortcutModel) else {
                throw WebShortcutEditingError.captureInProgress
            }
            shortcutModel.setMode(mode)
            reloadGenericBindings(shortcutModel: shortcutModel)

        case .reload:
            guard !isCapturing(shortcutModel) else {
                throw WebShortcutEditingError.captureInProgress
            }
            shortcutModel.reloadAndRestartBridge()
            reloadGenericBindings(shortcutModel: shortcutModel)

        case .beginLearn:
            let entry = try requireEntry(id: command.entryID, shortcutModel: shortcutModel)
            guard !isCapturing(shortcutModel) else {
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
            guard !isCapturing(shortcutModel) else {
                throw WebShortcutEditingError.captureInProgress
            }
            genericHIDModel.removeBindings(for: entry, shortcutModel: shortcutModel)
            shortcutModel.removeBindings(for: entry)
            reloadGenericBindings(shortcutModel: shortcutModel)

        case .confirmOverwrite:
            guard shortcutModel.overwriteConfirmation != nil else {
                throw WebShortcutEditingError.noOverwriteConfirmation
            }
            shortcutModel.confirmOverwrite()

        case .cancelOverwrite:
            guard shortcutModel.overwriteConfirmation != nil else {
                throw WebShortcutEditingError.noOverwriteConfirmation
            }
            shortcutModel.cancelOverwrite()

        case .rotateDevice:
            guard !isCapturing(shortcutModel) else {
                throw WebShortcutEditingError.captureInProgress
            }
            shortcutModel.rotateDevice()
        }
    }

    private func selectedPreset(_ shortcutModel: ShortcutSettingsModel) -> OverCUEPresetGroup? {
        guard shortcutModel.availablePresetGroups.indices.contains(shortcutModel.selectedGroup - 1)
        else { return nil }
        return shortcutModel.availablePresetGroups[shortcutModel.selectedGroup - 1]
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

    private func isCapturing(_ shortcutModel: ShortcutSettingsModel) -> Bool {
        shortcutModel.isCapturing || genericHIDModel.isCapturing
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
}

enum WebShortcutEditingError: LocalizedError {
    case entryMissing
    case invalidKey
    case invalidDialDirection
    case presetMissing
    case invalidMode
    case captureInProgress
    case noOverwriteConfirmation

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
        case .invalidMode:
            "rekordbox mode is invalid."
        case .captureInProgress:
            "Finish or cancel Learn before changing this setting."
        case .noOverwriteConfirmation:
            "There is no pending overwrite confirmation."
        }
    }
}

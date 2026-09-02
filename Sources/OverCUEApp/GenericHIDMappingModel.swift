import Foundation
import OverCUECore

struct GenericHIDActionChoice: Identifiable, Equatable {
    let id: String
    let target: ActionTarget
    let name: String
    let shortcut: String?
    let category: String

    var searchText: String {
        [name, shortcut ?? "", target.configurationValue, category]
            .joined(separator: " ")
    }
}

struct GenericHIDMappingRow: Identifiable, Equatable {
    let input: GenericHIDInputBindingKey
    let target: ActionTarget
    let targetName: String

    var id: String { input.overCUEStableSortKey }
}

@MainActor
final class GenericHIDMappingModel: ObservableObject {
    @Published private(set) var presetOptions: [OverCUEPresetGroup] = []
    @Published var selectedPresetID: String? {
        didSet {
            guard selectedPresetID != oldValue else { return }
            reloadActionChoices()
            reloadRows()
        }
    }
    @Published private(set) var rows: [GenericHIDMappingRow] = []
    @Published private(set) var actionChoices: [GenericHIDActionChoice] = []
    @Published private(set) var isLearning = false
    @Published private(set) var message: String?
    @Published private(set) var errorMessage: String?

    private let loader = RekordboxKeyMappingLoader()
    private var configuration: OverCUEConfiguration = .defaultValue
    private var logicalDeviceID: String?
    private var binding: OverCUEPhysicalDeviceBinding?
    private var profileName: String?
    private var learnMonitor: GenericHIDLearnMonitor?

    func configure(device: LogicalDeviceRow) {
        cancelLearn()
        logicalDeviceID = device.id
        binding = device.binding
        profileName = device.profileName
        reloadConfiguration(preferredPresetID: selectedPresetID)
    }

    func refresh() {
        reloadConfiguration(preferredPresetID: selectedPresetID)
    }

    func beginLearn(target: ActionTarget) throws {
        guard let binding,
              binding.kind == .genericHID,
              let logicalDeviceID,
              let presetID = selectedPresetID
        else {
            throw GenericHIDLearnMonitorError.missingPersistentIdentity
        }

        cancelLearn()
        message = L10n.text("genericHID.learn.prompt")
        errorMessage = nil
        isLearning = true

        let monitor = GenericHIDLearnMonitor(binding: binding)
        monitor.onCaptured = { [weak self] input in
            Task { @MainActor in
                guard let self else { return }
                do {
                    try GenericHIDMappingStore.assign(
                        logicalDeviceID: logicalDeviceID,
                        presetID: presetID,
                        input: input,
                        target: target
                    )
                    self.learnMonitor?.stop()
                    self.learnMonitor = nil
                    self.isLearning = false
                    self.message = L10n.text("genericHID.learn.saved")
                    self.errorMessage = nil
                    self.reloadRows()
                } catch {
                    self.learnMonitor?.stop()
                    self.learnMonitor = nil
                    self.isLearning = false
                    self.message = nil
                    self.errorMessage = L10n.text(
                        "genericHID.saveFailed",
                        error.localizedDescription
                    )
                }
            }
        }

        do {
            try monitor.start()
            learnMonitor = monitor
        } catch {
            isLearning = false
            message = nil
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func cancelLearn() {
        learnMonitor?.stop()
        learnMonitor = nil
        isLearning = false
        if message == L10n.text("genericHID.learn.prompt") {
            message = nil
        }
    }

    func remove(_ row: GenericHIDMappingRow) {
        guard let logicalDeviceID,
              let presetID = selectedPresetID
        else { return }
        do {
            try GenericHIDMappingStore.remove(
                logicalDeviceID: logicalDeviceID,
                presetID: presetID,
                input: row.input
            )
            message = nil
            errorMessage = nil
            reloadRows()
        } catch {
            errorMessage = L10n.text("genericHID.saveFailed", error.localizedDescription)
        }
    }

    private func reloadConfiguration(preferredPresetID: String?) {
        do {
            configuration = try OverCUEConfigurationFileStore.readCurrent(
                at: OverCUEAppConfigurationLocation.url
            )
            guard let logicalDeviceID,
                  let logicalDevice = configuration.logicalDevices[logicalDeviceID],
                  let profile = configuration.profiles[logicalDevice.profileName]
            else {
                presetOptions = []
                selectedPresetID = nil
                rows = []
                actionChoices = []
                return
            }
            profileName = logicalDevice.profileName
            presetOptions = profile.orderedPresetGroups
            let assignedPresetID = configuration.assignedPresetID(for: logicalDeviceID)
            let candidate = preferredPresetID ?? assignedPresetID
            if let candidate, presetOptions.contains(where: { $0.id == candidate }) {
                if selectedPresetID != candidate {
                    selectedPresetID = candidate
                } else {
                    reloadActionChoices()
                    reloadRows()
                }
            } else {
                let first = presetOptions.first?.id
                if selectedPresetID != first {
                    selectedPresetID = first
                } else {
                    reloadActionChoices()
                    reloadRows()
                }
            }
            errorMessage = nil
        } catch {
            presetOptions = []
            selectedPresetID = nil
            rows = []
            actionChoices = []
            errorMessage = L10n.text("genericHID.loadFailed", error.localizedDescription)
        }
    }

    private func reloadActionChoices() {
        guard let profileName,
              let profile = configuration.profiles[profileName],
              let presetID = selectedPresetID,
              let presetIndex = profile.orderedPresetGroups.firstIndex(where: { $0.id == presetID })
        else {
            actionChoices = []
            return
        }
        let group = presetIndex + 1
        let mode = profile.mapping(for: group).rekordboxMode ?? .performance

        var choices: [GenericHIDActionChoice] = []
        do {
            let loaded = try loader.load(mode: mode)
            choices.append(contentsOf: loaded.mapping.entries.map { entry in
                let target = RekordboxActionAdapter.target(for: entry.commandID)
                return GenericHIDActionChoice(
                    id: "rekordbox:\(target.configurationValue):\(entry.index)",
                    target: target,
                    name: entry.description.trimmingCharacters(in: .whitespacesAndNewlines),
                    shortcut: entry.shortcut,
                    category: RekordboxShortcutCategory.category(for: entry.commandID).rawValue
                )
            })
        } catch {
            errorMessage = L10n.text("genericHID.actionLoadFailed", error.localizedDescription)
        }

        let internalActions: [(ActionID, String)] = [
            (.captureWaveformPosition, "internal.capture"),
            (.jogSearchLeft, "internal.jogSearchLeft"),
            (.jogSearchRight, "internal.jogSearchRight"),
            (.cycleGroup, "internal.cycleAscending"),
            (.cycleGroupBackward, "internal.cycleDescending"),
            (.toggleRekordboxMode, "internal.toggleMode"),
        ]
        choices.insert(contentsOf: internalActions.map { action, key in
            GenericHIDActionChoice(
                id: "internal:\(action.rawValue)",
                target: .action(action),
                name: L10n.text(key),
                shortcut: nil,
                category: "OverCUE"
            )
        }, at: 0)
        actionChoices = choices
    }

    private func reloadRows() {
        guard let logicalDeviceID,
              let presetID = selectedPresetID
        else {
            rows = []
            return
        }
        do {
            let mapping = try GenericHIDMappingStore.mapping(
                logicalDeviceID: logicalDeviceID,
                presetID: presetID
            )
            rows = mapping.map { input, target in
                GenericHIDMappingRow(
                    input: input,
                    target: target,
                    targetName: actionChoices.first(where: { $0.target == target })?.name
                        ?? target.displayName
                )
            }
            .sorted { $0.input.overCUEStableSortKey < $1.input.overCUEStableSortKey }
            if errorMessage?.hasPrefix("Generic HID") == true {
                errorMessage = nil
            }
        } catch {
            rows = []
            errorMessage = L10n.text("genericHID.loadFailed", error.localizedDescription)
        }
    }
}

import Foundation
import OverCUECore

struct ShortcutSection: Identifiable, Equatable {
    let category: RekordboxShortcutCategory
    let entries: [RekordboxShortcutEntry]

    var id: RekordboxShortcutCategory { category }
}

enum ACK05Binding: Hashable {
    case key(ACK05Key)
    case chord(KeyChord)
    case dial(DialDirection)
    case dialChord(DialChord)

    var keys: Set<ACK05Key> {
        switch self {
        case let .key(key): [key]
        case let .chord(chord): Set(chord.keys)
        case .dial: []
        case let .dialChord(chord): Set(chord.keys)
        }
    }

    var label: String {
        switch self {
        case let .key(key): return key.rawValue.uppercased()
        case let .chord(chord): return chord.label
        case .dial(.clockwise): return "DIAL →"
        case .dial(.counterclockwise): return "DIAL ←"
        case let .dialChord(chord):
            let dial = chord.direction == .clockwise ? "DIAL →" : "DIAL ←"
            return (chord.keys.map { $0.rawValue.uppercased() } + [dial]).joined(separator: " + ")
        }
    }
}

struct ACK05DeviceAssignment {
    let functionName: String
    let shortcut: String?
}

enum ToastStyle {
    case error
    case success
    case info
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let style: ToastStyle
}

enum ToastPresentationConfiguration {
    // Keep the toast implementation available, but use the inline status area
    // below the search field as the sole message presentation for now.
    static let isEnabled = false
}

private enum PendingAssignment {
    case keys(entryID: String, keys: [ACK05Key])
    case dial(entryID: String, direction: DialDirection, heldKeys: [ACK05Key])
}

struct OverwriteConfirmation: Identifiable {
    let id = UUID()
    let message: String
}

struct UnifiedShortcutCaptureAvailability {
    var startedBackends: Set<UnifiedShortcutLearnBackend> = []
    var errors: [UnifiedShortcutLearnBackend: String] = [:]
}

private final class SendableObserverToken: @unchecked Sendable {
    let value: any NSObjectProtocol

    init(_ value: any NSObjectProtocol) {
        self.value = value
    }
}

@MainActor
final class ShortcutSettingsModel: ObservableObject {
    @Published private(set) var mode: RekordboxMappingMode = .export
    @Published var searchText = ""
    @Published var mappingName = L10n.text("message.loading")
    @Published var mappingURL: URL?
    @Published var entries: [RekordboxShortcutEntry] = []
    @Published var selectedEntryID: String?
    @Published private(set) var selectedGroup = 1
    @Published var rotationQuarterTurns = 1
    @Published var selectedDeviceKey: ACK05Key?
    @Published var selectedDialDirection: DialDirection?
    @Published var errorMessage: String?
    @Published private(set) var bindingsByTarget: [String: [ACK05Binding]] = [:]
    @Published private(set) var editingEntryID: String?
    @Published private(set) var captureMessage: String?
    @Published private(set) var captureError: String?
    @Published private(set) var bridgeStatus: OverCUECLIRuntime.Status = .stopped
    @Published private(set) var isBridgeEnabled = true
    @Published private(set) var toast: ToastMessage?
    @Published private(set) var runtimeMode: RekordboxMappingMode = .export
    @Published private(set) var runtimeGroup = 1
    @Published private(set) var runtimeDeviceID: String?
    @Published private(set) var runtimeLogicalDeviceID: String?
    @Published private(set) var runtimeProfileName: String?
    @Published var overwriteConfirmation: OverwriteConfirmation?
    @Published private(set) var pressedDeviceKeys: Set<ACK05Key> = []
    @Published private(set) var activeDialDirection: DialDirection?

    var availablePresetGroups: [OverCUEPresetGroup] {
        configuration.profiles[configuration.defaultProfile]?.orderedPresetGroups ?? []
    }

    private let loader = RekordboxKeyMappingLoader()
    private let runtimeBridge = OverCUECLIRuntime()
    private let configurationURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/OverCUE/config.json")
    private var configuration: OverCUEConfiguration = .defaultValue
    private var persistedConfiguration: OverCUEConfiguration = .defaultValue
    private var inputMonitor: ACK05InputMonitor?
    private var previousCaptureKeys: Set<ACK05Key> = []
    private var capturedKeyOrder: [ACK05Key] = []
    private var captureDeviceLock = PhysicalDeviceCaptureLock()
    private var toastDismissTask: Task<Void, Never>?
    private var dialHighlightTask: Task<Void, Never>?
    private var runtimeStatusObserver: SendableObserverToken?
    private var inputStatusObserver: SendableObserverToken?
    private var configurationChangedObserver: SendableObserverToken?
    private var pendingAssignment: PendingAssignment?
    private var selectedPresetGroupID: String?
    private var runtimeStateRegistry = OverCUERuntimeStateRegistry()
    private var capturePresetGroupID: String?
    private var captureTarget: ActionTarget?
    private var captureEntryDescription: String?
    private var ack05OwnsUnifiedSession = false
    private var claimACK05Capture: (() -> Bool)?
    private var completeACK05Capture: ((String?) -> Void)?

    var internalEntries: [RekordboxShortcutEntry] {
        [
            internalEntry(-1, action: .captureWaveformPosition, key: "internal.capture"),
            internalEntry(-2, action: .jogSearchLeft, key: "internal.jogSearchLeft"),
            internalEntry(-3, action: .jogSearchRight, key: "internal.jogSearchRight"),
            internalEntry(-4, action: .cycleGroup, key: "internal.cycleAscending"),
            internalEntry(-5, action: .cycleGroupBackward, key: "internal.cycleDescending"),
            internalEntry(-6, action: .toggleRekordboxMode, key: "internal.toggleMode"),
        ]
    }

    init() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "deviceRotationClockwiseDefaultV2") {
            rotationQuarterTurns = defaults.integer(forKey: "deviceRotationQuarterTurns") % 4
        } else {
            rotationQuarterTurns = 1
            defaults.set(rotationQuarterTurns, forKey: "deviceRotationQuarterTurns")
            defaults.set(true, forKey: "deviceRotationClockwiseDefaultV2")
        }
        if defaults.object(forKey: "ack05BridgeEnabled") == nil {
            isBridgeEnabled = true
            defaults.set(true, forKey: "ack05BridgeEnabled")
        } else {
            isBridgeEnabled = defaults.bool(forKey: "ack05BridgeEnabled")
        }
        if let savedMode = defaults.string(forKey: "rekordboxMappingMode"),
           let restoredMode = RekordboxMappingMode(rawValue: savedMode) {
            mode = restoredMode
        }
        runtimeMode = mode
        runtimeStatusObserver = SendableObserverToken(
            DistributedNotificationCenter.default().addObserver(
                forName: OverCUERuntimeStatusNotification.name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let modeValue = notification.userInfo?[OverCUERuntimeStatusNotification.modeKey] as? String,
                      let mode = RekordboxMappingMode(rawValue: modeValue),
                      let group = notification.userInfo?[OverCUERuntimeStatusNotification.groupKey] as? Int,
                      let rawScope = notification.userInfo?[OverCUERuntimeStatusNotification.scopeKey] as? String,
                      OverCUERuntimeNotificationScope(rawValue: rawScope) == .device,
                      let deviceID = notification.userInfo?[OverCUERuntimeStatusNotification.deviceIDKey]
                        as? String,
                      let profileName = notification.userInfo?[OverCUERuntimeStatusNotification.profileNameKey]
                        as? String
                else { return }
                let logicalDeviceID = notification.userInfo?[
                    OverCUERuntimeStatusNotification.logicalDeviceIDKey
                ] as? String
                let connected = notification.userInfo?[
                    OverCUERuntimeStatusNotification.connectedKey
                ] as? Bool ?? true
                let presetGroupID = notification.userInfo?[
                    OverCUERuntimeStatusNotification.presetGroupIDKey
                ] as? String
                Task { @MainActor in
                    self?.applyRuntimeStatus(
                        mode: mode,
                        group: group,
                        presetGroupID: presetGroupID,
                        deviceID: deviceID,
                        logicalDeviceID: logicalDeviceID,
                        profileName: profileName,
                        connected: connected
                    )
                }
            }
        )
        inputStatusObserver = SendableObserverToken(
            DistributedNotificationCenter.default().addObserver(
                forName: OverCUEInputStatusNotification.name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let rawKeys = notification.userInfo?[OverCUEInputStatusNotification.keysKey]
                    as? [String] ?? []
                let includesKeyState = notification.userInfo?[OverCUEInputStatusNotification.keysKey] != nil
                let keys = Set(rawKeys.compactMap { ACK05Key(rawValue: $0.lowercased()) })
                let direction = (notification.userInfo?[OverCUEInputStatusNotification.dialDirectionKey]
                    as? String).flatMap(DialDirection.init(rawValue:))
                let deviceID = notification.userInfo?[OverCUEInputStatusNotification.deviceIDKey]
                    as? String
                Task { @MainActor in
                    guard let self else { return }
                    guard deviceID == nil || deviceID == self.runtimeDeviceID else { return }
                    if includesKeyState {
                        self.pressedDeviceKeys = keys
                    }
                    if let direction {
                        self.showDialInput(direction)
                    }
                }
            }
        )
        configurationChangedObserver = SendableObserverToken(
            DistributedNotificationCenter.default().addObserver(
                forName: OverCUEConfigurationChangedNotification.name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.refreshConfigurationFromDisk() else { return }
                    self.mode = self.configuredMode(for: self.selectedGroup)
                    self.rebuildBindings()
                    self.reload()
                }
            }
        )
        runtimeBridge.onStatusChanged = { [weak self] status in
            self?.bridgeStatus = status
            if case let .failed(message) = status {
                self?.showToast(message, style: .error, durationNanoseconds: 8_000_000_000)
            }
        }
        loadConfiguration()
        reload()
        startRuntimeIfEnabled()
    }

    deinit {
        toastDismissTask?.cancel()
        dialHighlightTask?.cancel()
        if let runtimeStatusObserver {
            DistributedNotificationCenter.default().removeObserver(runtimeStatusObserver.value)
        }
        if let inputStatusObserver {
            DistributedNotificationCenter.default().removeObserver(inputStatusObserver.value)
        }
        if let configurationChangedObserver {
            DistributedNotificationCenter.default().removeObserver(configurationChangedObserver.value)
        }
    }

    var runtimeModeLabel: String { runtimeMode == .export ? "E" : "P" }

    private func internalEntry(
        _ index: Int,
        action: ActionID,
        key: String
    ) -> RekordboxShortcutEntry {
        RekordboxShortcutEntry(
            index: index,
            commandID: "overcue:\(action.rawValue)",
            description: L10n.text(key),
            shortcut: "OverCUE"
        )
    }

    func showToast(_ text: String, style: ToastStyle, durationNanoseconds: UInt64 = 4_000_000_000) {
        guard ToastPresentationConfiguration.isEnabled else { return }
        toastDismissTask?.cancel()
        toast = ToastMessage(text: text, style: style)
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: durationNanoseconds)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func dismissToast() {
        toastDismissTask?.cancel()
        toastDismissTask = nil
        toast = nil
    }

    var sections: [ShortcutSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? entries : entries.filter { entry in
            entry.description.localizedCaseInsensitiveContains(query)
                || entry.shortcut.localizedCaseInsensitiveContains(query)
                || entry.commandID.localizedCaseInsensitiveContains(query)
                || bindingLabels(for: entry).contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
        let grouped = Dictionary(grouping: filtered) {
            RekordboxShortcutCategory.category(for: $0.commandID)
        }
        return RekordboxShortcutCategory.allCases.compactMap { category in
            guard let categoryEntries = grouped[category], !categoryEntries.isEmpty else { return nil }
            return ShortcutSection(category: category, entries: categoryEntries)
        }
    }

    var filteredInternalEntries: [RekordboxShortcutEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return internalEntries }
        return internalEntries.filter {
            $0.description.localizedCaseInsensitiveContains(query)
                || bindingLabels(for: $0).contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    private var allEntries: [RekordboxShortcutEntry] { internalEntries + entries }

    var selectedEntry: RekordboxShortcutEntry? {
        guard let selectedEntryID else { return nil }
        return allEntries.first { $0.id == selectedEntryID }
    }

    var highlightedKeys: Set<ACK05Key> {
        guard let entry = selectedEntry else { return [] }
        return Set(bindingsByTarget[bindingKey(for: entry), default: []].flatMap(\.keys))
    }

    var highlightedDialDirections: Set<DialDirection> {
        guard let entry = selectedEntry else { return [] }
        return Set(bindingsByTarget[bindingKey(for: entry), default: []].compactMap { binding in
            switch binding {
            case let .dial(direction): direction
            case let .dialChord(chord): chord.direction
            case .key, .chord: nil
            }
        })
    }

    var isCapturing: Bool { editingEntryID != nil }

    func reload() {
        do {
            let loaded = try loader.load(mode: mode)
            mappingName = loaded.mapping.name
            mappingURL = loaded.url
            entries = loaded.mapping.entries
            errorMessage = nil

            if let selectedEntryID, allEntries.contains(where: { $0.id == selectedEntryID }) { return }
            selectedEntryID = initialSelection(in: entries)?.id
        } catch {
            mappingName = L10n.text("message.loadFailureName")
            mappingURL = nil
            entries = []
            selectedEntryID = nil
            errorMessage = error.localizedDescription
        }
    }

    func reloadAndRestartBridge() {
        reload()
        guard !isCapturing else { return }
        restartRuntimeIfEnabled()
        if let errorMessage {
            showToast(L10n.text("message.loadFailed", errorMessage), style: .error)
        } else {
            showToast(L10n.text("message.reloadSuccess"), style: .success)
        }
    }

    func setMode(_ newMode: RekordboxMappingMode) {
        guard mode != newMode else { return }
        saveMode(newMode, for: selectedGroup)
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: "rekordboxMappingMode")
        selectedEntryID = nil
        selectedDeviceKey = nil
        selectedDialDirection = nil
        captureMessage = nil
        captureError = nil
        reload()
        showToast(L10n.text("message.modeUpdated", newMode.displayName), style: .success)
    }

    func setBridgeEnabled(_ enabled: Bool) {
        guard isBridgeEnabled != enabled else { return }
        isBridgeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "ack05BridgeEnabled")
        if enabled {
            guard !isCapturing else { return }
            clearRuntimeDeviceScope()
            startRuntimeBridge()
            showToast(L10n.text("message.inputEnabled"), style: .info)
        } else {
            runtimeBridge.stop()
            pressedDeviceKeys = []
            activeDialDirection = nil
            showToast(L10n.text("message.inputStopped"), style: .info)
        }
    }

    /// Device identification needs exclusive access to the physical input, but
    /// it must not change the user's persisted Controller Input preference.
    func pauseRuntimeForDeviceIdentification() {
        guard isBridgeEnabled else { return }
        runtimeBridge.stop()
        pressedDeviceKeys = []
        activeDialDirection = nil
    }

    func resumeRuntimeAfterDeviceIdentification() {
        guard isBridgeEnabled, !isCapturing else { return }
        clearRuntimeDeviceScope()
        startRuntimeBridge()
    }

    func shutdown() {
        stopCaptureMonitor()
        runtimeBridge.stop()
    }

    func select(_ entry: RekordboxShortcutEntry) {
        selectedEntryID = entry.id
        selectedDeviceKey = highlightedKeys.sorted(by: keyOrder).first
        selectedDialDirection = highlightedDialDirections.sorted(by: dialDirectionOrder).first
    }

    func selectDeviceKey(_ key: ACK05Key) {
        selectedDeviceKey = key
        selectedDialDirection = nil
        let targetKey = assignedTargetKey(to: key)
        guard let targetKey,
              let entry = allEntries.first(where: { bindingKey(for: $0) == targetKey })
        else {
            selectedEntryID = nil
            return
        }
        selectedEntryID = entry.id
    }

    func selectDial(_ direction: DialDirection) {
        selectedDeviceKey = nil
        selectedDialDirection = direction
        guard let targetKey = assignedTargetKey(to: direction),
              let entry = allEntries.first(where: { bindingKey(for: $0) == targetKey })
        else {
            selectedEntryID = nil
            return
        }
        selectedEntryID = entry.id
    }

    func setGroup(_ group: Int) {
        guard availablePresetGroups.indices.contains(group - 1), selectedGroup != group else { return }
        refreshConfigurationFromDisk()
        guard availablePresetGroups.indices.contains(group - 1) else { return }
        selectedGroup = group
        selectedPresetGroupID = availablePresetGroups[group - 1].id
        mode = configuredMode(for: group)
        UserDefaults.standard.set(mode.rawValue, forKey: "rekordboxMappingMode")
        selectedDeviceKey = nil
        selectedDialDirection = nil
        rebuildBindings()
        selectedEntryID = nil
        reload()
        showToast(
            L10n.text("message.groupSwitched", presetName(for: group), mode.displayName),
            style: .info
        )
    }

    func rotateDevice() {
        rotationQuarterTurns = (rotationQuarterTurns + 1) % 4
        UserDefaults.standard.set(rotationQuarterTurns, forKey: "deviceRotationQuarterTurns")
    }

    func deviceAssignment(to key: ACK05Key) -> ACK05DeviceAssignment? {
        guard let targetKey = assignedTargetKey(to: key),
              let target = ActionTarget(configurationValue: targetKey)
        else { return nil }
        let entry = allEntries.first { bindingKey(for: $0) == targetKey }
        return ACK05DeviceAssignment(
            functionName: entry?.description.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? target.displayName,
            shortcut: entry?.shortcut
        )
    }

    func dialAssignment(_ direction: DialDirection) -> ACK05DeviceAssignment? {
        guard let targetKey = assignedTargetKey(to: direction),
              let target = ActionTarget(configurationValue: targetKey)
        else { return nil }
        let entry = allEntries.first { bindingKey(for: $0) == targetKey }
        return ACK05DeviceAssignment(
            functionName: entry?.description.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? target.displayName,
            shortcut: entry?.shortcut
        )
    }

    private func assignedTargetKey(to direction: DialDirection) -> String? {
        let directTarget = bindingsByTarget
            .sorted(by: { $0.key < $1.key })
            .first(where: { $0.value.contains(.dial(direction)) })?.key
        if let directTarget { return directTarget }

        let preferredTarget = selectedEntry.flatMap { entry in
            let targetKey = bindingKey(for: entry)
            return bindingsByTarget[targetKey]?.contains(where: {
                if case let .dialChord(chord) = $0 { return chord.direction == direction }
                return false
            }) == true ? targetKey : nil
        }
        return preferredTarget
    }

    private func showDialInput(_ direction: DialDirection) {
        dialHighlightTask?.cancel()
        activeDialDirection = direction
        dialHighlightTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            self?.activeDialDirection = nil
        }
    }

    private func assignedTargetKey(to key: ACK05Key) -> String? {
        let singleKeyTarget = bindingsByTarget
            .sorted(by: { $0.key < $1.key })
            .first(where: { $0.value.contains(.key(key)) })?.key
        if let singleKeyTarget {
            return singleKeyTarget
        }

        let preferredCommandID = selectedEntry.flatMap { entry in
            let targetKey = bindingKey(for: entry)
            return bindingsByTarget[targetKey]?.contains(where: { $0.keys.contains(key) }) == true
                ? targetKey
                : nil
        }
        return preferredCommandID ?? bindingsByTarget
            .sorted(by: { $0.key < $1.key })
            .first(where: { $0.value.contains(where: { $0.keys.contains(key) }) })?.key
    }

    func bindingLabels(for entry: RekordboxShortcutEntry) -> [String] {
        bindingsByTarget[bindingKey(for: entry), default: []]
            .sorted(by: bindingOrder)
            .map(\.label)
    }

    func isConfigured(_ entry: RekordboxShortcutEntry) -> Bool {
        !bindingsByTarget[bindingKey(for: entry), default: []].isEmpty
    }

    func beginUnifiedCapture(
        for entry: RekordboxShortcutEntry,
        onGenericHIDCaptured: @escaping (String, GenericHIDInputBindingKey) -> Void,
        claimACK05: @escaping () -> Bool,
        onACK05Completed: @escaping (String?) -> Void
    ) -> UnifiedShortcutCaptureAvailability {
        stopCaptureMonitor()
        select(entry)
        capturePresetGroupID = selectedPresetGroupID ?? (
            availablePresetGroups.indices.contains(selectedGroup - 1)
                ? availablePresetGroups[selectedGroup - 1].id
                : nil
        )
        captureTarget = target(for: entry)
        captureEntryDescription = entry.description.trimmingCharacters(in: .whitespacesAndNewlines)
        claimACK05Capture = claimACK05
        completeACK05Capture = onACK05Completed
        ack05OwnsUnifiedSession = false
        previousCaptureKeys = []
        capturedKeyOrder = []
        captureError = nil
        captureMessage = L10n.text("message.capturePrompt")
        showToast(
            captureMessage ?? L10n.text("message.waitingInput"),
            style: .info,
            durationNanoseconds: 6_000_000_000
        )

        var availability = UnifiedShortcutCaptureAvailability()
        do {
            try runtimeBridge.beginShortcutCapture(onGenericHIDCaptured: onGenericHIDCaptured)
            availability.startedBackends.insert(.genericHID)
        } catch {
            availability.errors[.genericHID] = error.localizedDescription
        }

        let monitor = ACK05InputMonitor()
        monitor.onConnectionChanged = { [weak self] deviceID, connected in
            guard let self else { return }
            Task { @MainActor in
                if connected {
                    if self.captureDeviceLock.deviceID == nil {
                        self.captureMessage = L10n.text("message.capturePrompt")
                    }
                } else if self.captureDeviceLock.deviceDisconnected(deviceID) {
                    self.captureError = L10n.text("message.captureDeviceDisconnected")
                    let message = self.captureError
                    self.finishACK05Capture(message)
                } else if self.captureDeviceLock.deviceID == nil {
                    self.captureMessage = L10n.text("message.waitingDevice")
                }
            }
        }
        monitor.onPressedKeysChanged = { [weak self] deviceID, keys in
            guard let self else { return }
            Task { @MainActor in
                let accepted = keys.isEmpty
                    ? self.captureDeviceLock.acceptsStateChange(from: deviceID)
                    : self.captureDeviceLock.acceptsInput(from: deviceID)
                guard accepted else { return }
                if !keys.isEmpty, !self.ack05OwnsUnifiedSession {
                    guard self.claimACK05Capture?() ?? true else { return }
                    self.ack05OwnsUnifiedSession = true
                }
                guard self.ack05OwnsUnifiedSession else { return }
                self.pressedDeviceKeys = keys
                self.handleCapturedKeys(keys)
            }
        }
        monitor.onDialTurned = { [weak self] deviceID, direction in
            guard let self else { return }
            Task { @MainActor in
                guard self.captureDeviceLock.acceptsInput(from: deviceID) else { return }
                guard self.ack05OwnsUnifiedSession
                        || (self.claimACK05Capture?() ?? true)
                else { return }
                self.ack05OwnsUnifiedSession = true
                self.showDialInput(direction)
                self.commitDialCapture(direction, heldKeys: self.capturedKeyOrder)
            }
        }

        do {
            try monitor.start()
            inputMonitor = monitor
            editingEntryID = entry.id
            availability.startedBackends.insert(.ack05)
        } catch {
            editingEntryID = nil
            captureMessage = nil
            captureError = error.localizedDescription
            availability.errors[.ack05] = error.localizedDescription
        }
        return availability
    }

    func endUnifiedCapture() {
        stopCaptureMonitor()
        let initialGroup = 1
        runtimeBridge.endShortcutCapture(
            mode: configuredMode(for: initialGroup),
            group: initialGroup,
            resumeRuntime: isBridgeEnabled
        )
    }

    func cancelCapture() {
        endUnifiedCapture()
        showToast(L10n.text("message.editCancelled"), style: .info)
    }

    func removeBindings(for entry: RekordboxShortcutEntry) {
        guard var profile = configuration.profiles[configuration.defaultProfile] else { return }
        let target = target(for: entry)
        let editedGroup = isGroupCycle(target) ? 1 : selectedGroup
        var mapping = profile.storedMapping(for: editedGroup)
        let targetKey = bindingKey(for: entry)
        for (rawKey, value) in mapping.keyMap where value == targetKey {
            mapping.keyMap[rawKey] = "unassigned"
        }
        for (rawChord, value) in mapping.chordMap where value == targetKey {
            mapping.chordMap.removeValue(forKey: rawChord)
        }
        for (direction, value) in mapping.dialMap where value == targetKey {
            mapping.dialMap.removeValue(forKey: direction)
        }
        for (rawChord, value) in mapping.dialChordMap where value == targetKey {
            mapping.dialChordMap.removeValue(forKey: rawChord)
        }
        profile.setMapping(mapping, for: editedGroup)
        configuration.profiles[configuration.defaultProfile] = profile

        do {
            try saveConfiguration()
            rebuildBindings()
            selectedDeviceKey = nil
            selectedDialDirection = nil
            captureError = nil
            captureMessage = L10n.text(
                "message.bindingRemoved",
                entry.description.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            showToast(captureMessage ?? L10n.text("message.removed"), style: .success)
            restartRuntimeIfEnabled()
        } catch {
            captureMessage = nil
            captureError = L10n.text("message.saveFailed", error.localizedDescription)
            showToast(captureError ?? error.localizedDescription, style: .error)
        }
    }

    private func handleCapturedKeys(_ keys: Set<ACK05Key>) {
        guard editingEntryID != nil else { return }
        let newlyPressed = keys.subtracting(previousCaptureKeys).sorted(by: keyOrder)
        for key in newlyPressed where !capturedKeyOrder.contains(key) {
            capturedKeyOrder.append(key)
        }
        previousCaptureKeys = keys

        if !capturedKeyOrder.isEmpty {
            captureMessage = L10n.text(
                "message.inputCaptured",
                capturedKeyOrder.map { $0.rawValue.uppercased() }.joined(separator: " + ")
            )
        }
        guard keys.isEmpty, !capturedKeyOrder.isEmpty else { return }
        commitCapture()
    }

    private func commitCapture(allowOverwrite: Bool = false) {
        guard let target = captureTarget,
              let entryDescription = captureEntryDescription,
              let editedGroup = captureGroup,
              var profile = configuration.profiles[configuration.defaultProfile]
        else {
            captureError = L10n.text("message.profileMissing")
            cancelCaptureKeepingError()
            return
        }

        let targetKey = target.configurationValue
        if let conflict = keyAssignmentConflict(
            keys: capturedKeyOrder,
            target: target,
            profile: profile,
            selectedGroup: editedGroup
        ) {
            if case .occupied = conflict.kind, !allowOverwrite {
                requestOverwrite(
                    conflict: conflict,
                    target: target,
                    assignment: .keys(entryID: editingEntryID ?? "", keys: capturedKeyOrder)
                )
                return
            } else if !allowOverwrite || !isOccupied(conflict) {
                rejectConflict(conflict, target: target)
                return
            }
        }
        let mappingGroup = isGroupCycle(target) ? 1 : editedGroup
        var mapping = profile.storedMapping(for: mappingGroup)
        for (rawKey, value) in mapping.keyMap where value == targetKey {
            mapping.keyMap[rawKey] = "unassigned"
        }
        for (rawChord, value) in mapping.chordMap where value == targetKey {
            mapping.chordMap.removeValue(forKey: rawChord)
        }
        for (direction, value) in mapping.dialMap where value == targetKey {
            mapping.dialMap.removeValue(forKey: direction)
        }
        for (rawChord, value) in mapping.dialChordMap where value == targetKey {
            mapping.dialChordMap.removeValue(forKey: rawChord)
        }

        switch capturedKeyOrder.count {
        case 1:
            mapping.keyMap[capturedKeyOrder[0].rawValue.uppercased()] = targetKey
        case 2...ACK05Key.allCases.count:
            let chord = capturedKeyOrder.map { $0.rawValue.uppercased() }.joined(separator: "+")
            mapping.chordMap[chord] = targetKey
        default:
            return
        }

        profile.setMapping(mapping, for: mappingGroup)
        configuration.profiles[configuration.defaultProfile] = profile
        do {
            try saveConfiguration()
            rebuildBindings()
            selectedEntryID = editingEntryID
            selectedDeviceKey = highlightedKeys.sorted(by: keyOrder).first
            selectedDialDirection = nil
            captureError = nil
            captureMessage = L10n.text(
                "message.bindingSet",
                entryDescription,
                capturedKeyOrder.map { $0.rawValue.uppercased() }.joined(separator: " + ")
            )
            showToast(captureMessage ?? L10n.text("message.bindingUpdated"), style: .success)
            finishACK05Capture(nil)
        } catch {
            captureError = L10n.text("message.saveFailed", error.localizedDescription)
            showToast(captureError ?? error.localizedDescription, style: .error)
            let message = captureError
            finishACK05Capture(message)
        }
    }

    private func commitDialCapture(
        _ direction: DialDirection,
        heldKeys: [ACK05Key],
        allowOverwrite: Bool = false
    ) {
        guard let target = captureTarget,
              let entryDescription = captureEntryDescription,
              let editedGroup = captureGroup,
              var profile = configuration.profiles[configuration.defaultProfile]
        else { return }

        if let conflict = dialAssignmentConflict(
            direction: direction,
            heldKeys: heldKeys,
            target: target,
            profile: profile,
            selectedGroup: editedGroup
        ) {
            if case .occupied = conflict.kind, !allowOverwrite {
                requestOverwrite(
                    conflict: conflict,
                    target: target,
                    assignment: .dial(
                        entryID: editingEntryID ?? "",
                        direction: direction,
                        heldKeys: heldKeys
                    )
                )
                return
            } else if !allowOverwrite || !isOccupied(conflict) {
                rejectConflict(conflict, target: target)
                return
            }
        }
        let targetKey = target.configurationValue
        let mappingGroup = isGroupCycle(target) ? 1 : editedGroup
        var mapping = profile.storedMapping(for: mappingGroup)
        for (rawDirection, value) in mapping.dialMap where value == targetKey {
            mapping.dialMap.removeValue(forKey: rawDirection)
        }
        for (rawChord, value) in mapping.dialChordMap where value == targetKey {
            mapping.dialChordMap.removeValue(forKey: rawChord)
        }
        let inputLabel: String
        if heldKeys.isEmpty {
            mapping.dialMap[direction.rawValue] = targetKey
            inputLabel = direction == .clockwise ? "DIAL →" : "DIAL ←"
        } else {
            let chord = DialChord(keys: heldKeys, direction: direction)!
            mapping.dialChordMap[chord.label] = targetKey
            inputLabel = ACK05PhysicalInput.dialChord(chord).label
        }
        profile.setMapping(mapping, for: mappingGroup)
        configuration.profiles[configuration.defaultProfile] = profile

        do {
            try saveConfiguration()
            rebuildBindings()
            selectedEntryID = editingEntryID
            selectedDeviceKey = highlightedKeys.sorted(by: keyOrder).first
            selectedDialDirection = direction
            captureError = nil
            captureMessage = L10n.text("message.bindingSet", entryDescription, inputLabel)
            showToast(captureMessage ?? L10n.text("message.dialUpdated"), style: .success)
            finishACK05Capture(nil)
        } catch {
            captureError = L10n.text("message.saveFailed", error.localizedDescription)
            showToast(captureError ?? error.localizedDescription, style: .error)
            let message = captureError
            finishACK05Capture(message)
        }
    }

    private func keyAssignmentConflict(
        keys: [ACK05Key],
        target: ActionTarget,
        profile: OverCUEProfile,
        selectedGroup: Int
    ) -> ActionMappingConflict? {
        guard !keys.isEmpty else { return nil }
        let input: ACK05PhysicalInput = keys.count == 1
            ? .key(keys[0])
            : .chord(KeyChord(keys: keys)!)
        return ActionMappingConflictDetector.conflict(
            for: input,
            target: target,
            profile: profile,
            selectedGroup: selectedGroup
        )
    }

    private func dialAssignmentConflict(
        direction: DialDirection,
        heldKeys: [ACK05Key],
        target: ActionTarget,
        profile: OverCUEProfile,
        selectedGroup: Int
    ) -> ActionMappingConflict? {
        let input: ACK05PhysicalInput = heldKeys.isEmpty
            ? .dial(direction)
            : .dialChord(DialChord(keys: heldKeys, direction: direction)!)
        return ActionMappingConflictDetector.conflict(
            for: input,
            target: target,
            profile: profile,
            selectedGroup: selectedGroup
        )
    }

    private func isOccupied(_ conflict: ActionMappingConflict) -> Bool {
        if case .occupied = conflict.kind { return true }
        return false
    }

    private func requestOverwrite(
        conflict: ActionMappingConflict,
        target: ActionTarget,
        assignment: PendingAssignment
    ) {
        inputMonitor?.stop()
        inputMonitor = nil
        let message = L10n.text(
            "message.overwriteQuestion",
            conflictMessage(conflict, target: target),
            actionDisplayName(target)
        )
        pendingAssignment = assignment
        overwriteConfirmation = OverwriteConfirmation(message: message)
    }

    private func rejectConflict(_ conflict: ActionMappingConflict, target: ActionTarget) {
        let message = conflictMessage(conflict, target: target)
        captureError = message
        showToast(message, style: .error, durationNanoseconds: 7_000_000_000)
        cancelCaptureKeepingError()
    }

    func confirmOverwrite() {
        guard let pending = pendingAssignment else { return }
        pendingAssignment = nil
        overwriteConfirmation = nil
        switch pending {
        case let .keys(entryID, keys):
            editingEntryID = entryID
            capturedKeyOrder = keys
            commitCapture(allowOverwrite: true)
        case let .dial(entryID, direction, heldKeys):
            editingEntryID = entryID
            capturedKeyOrder = heldKeys
            commitDialCapture(direction, heldKeys: heldKeys, allowOverwrite: true)
        }
    }

    func cancelOverwrite() {
        overwriteConfirmation = nil
        pendingAssignment = nil
        finishACK05Capture(L10n.text("message.overwriteCancelled"))
        showToast(L10n.text("message.overwriteCancelled"), style: .info)
    }

    private func conflictMessage(_ conflict: ActionMappingConflict, target: ActionTarget) -> String {
        let groupSuffix = isGroupCycle(target)
            ? L10n.text("conflict.groupSuffix", conflict.group)
            : ""
        switch conflict.kind {
        case let .occupied(existing):
            return L10n.text(
                "conflict.occupied",
                conflict.input.label,
                groupSuffix,
                actionDisplayName(existing)
            )
        case let .longPressTargetUsesChord(chord, chordTarget):
            return L10n.text(
                "conflict.longChord",
                conflict.input.label,
                chord.label,
                actionDisplayName(target),
                actionDisplayName(chordTarget)
            )
        case let .chordUsesLongPressModifier(key, existing):
            return L10n.text(
                "conflict.chordLong",
                conflict.input.label,
                key.rawValue.uppercased(),
                actionDisplayName(existing)
            )
        case let .longPressTargetUsesDialChord(chord, chordTarget):
            return L10n.text(
                "conflict.longDial",
                conflict.input.label,
                ACK05PhysicalInput.dialChord(chord).label,
                actionDisplayName(target),
                actionDisplayName(chordTarget)
            )
        case let .dialChordUsesLongPressModifier(key, existing):
            return L10n.text(
                "conflict.dialLong",
                conflict.input.label,
                key.rawValue.uppercased(),
                actionDisplayName(existing)
            )
        }
    }

    private func actionDisplayName(_ target: ActionTarget) -> String {
        return allEntries.first(where: { self.target(for: $0) == target })?
            .description.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? target.displayName
    }

    private func isGroupCycle(_ target: ActionTarget) -> Bool {
        target.semanticAction?.isGroupCycle == true
    }

    private func cancelCaptureKeepingError() {
        finishACK05Capture(captureError)
    }

    private var captureGroup: Int? {
        guard let capturePresetGroupID else { return nil }
        return availablePresetGroups.firstIndex(where: { $0.id == capturePresetGroupID }).map { $0 + 1 }
    }

    private func finishACK05Capture(_ errorMessage: String?) {
        let completion = completeACK05Capture
        stopCaptureMonitor()
        if let completion {
            completion(errorMessage)
        } else {
            startRuntimeIfEnabled()
        }
    }

    private func stopCaptureMonitor() {
        inputMonitor?.stop()
        inputMonitor = nil
        pendingAssignment = nil
        overwriteConfirmation = nil
        editingEntryID = nil
        captureMessage = nil
        previousCaptureKeys = []
        capturedKeyOrder = []
        captureDeviceLock.reset()
        pressedDeviceKeys = []
        activeDialDirection = nil
        capturePresetGroupID = nil
        captureTarget = nil
        captureEntryDescription = nil
        ack05OwnsUnifiedSession = false
        claimACK05Capture = nil
        completeACK05Capture = nil
    }

    private func startRuntimeIfEnabled() {
        guard isBridgeEnabled else {
            runtimeBridge.stop()
            return
        }
        clearRuntimeDeviceScope()
        startRuntimeBridge()
    }

    private func restartRuntimeIfEnabled() {
        guard isBridgeEnabled else {
            runtimeBridge.stop()
            return
        }
        clearRuntimeDeviceScope()
        let initialGroup = 1
        runtimeBridge.restart(mode: configuredMode(for: initialGroup), group: initialGroup)
    }

    private func startRuntimeBridge() {
        let initialGroup = 1
        runtimeBridge.start(mode: configuredMode(for: initialGroup), group: initialGroup)
    }

    private func clearRuntimeDeviceScope() {
        runtimeStateRegistry = OverCUERuntimeStateRegistry()
        runtimeDeviceID = nil
        runtimeLogicalDeviceID = nil
        runtimeProfileName = nil
    }

    private func saveConfiguration() throws {
        let localConfiguration = configuration
        let baseConfiguration = persistedConfiguration
        configuration = try OverCUEConfigurationFileStore.updateCurrent(
            at: configurationURL,
            fallback: localConfiguration
        ) { remoteConfiguration in
            remoteConfiguration = OverCUEConfigurationMerger.merge(
                base: baseConfiguration,
                local: localConfiguration,
                remote: remoteConfiguration
            )
        }
        persistedConfiguration = configuration
    }

    @discardableResult
    private func refreshConfigurationFromDisk() -> Bool {
        do {
            let currentPresetID = availablePresetGroups.indices.contains(selectedGroup - 1)
                ? availablePresetGroups[selectedGroup - 1].id
                : nil
            let preservedPresetID = selectedPresetGroupID ?? currentPresetID
            let remote = try OverCUEConfigurationFileStore.readCurrent(at: configurationURL)
            let reconciled = OverCUEConfigurationSnapshotSynchronizer.reconcile(
                configuration: configuration,
                persistedConfiguration: persistedConfiguration,
                remote: remote
            )
            configuration = reconciled.configuration
            persistedConfiguration = reconciled.persistedConfiguration
            if let preservedPresetID,
               let index = availablePresetGroups.firstIndex(where: { $0.id == preservedPresetID }) {
                selectedGroup = index + 1
                selectedPresetGroupID = preservedPresetID
            } else {
                selectedGroup = 1
                selectedPresetGroupID = availablePresetGroups.first?.id
            }
            return true
        } catch {
            return false
        }
    }

    private func loadConfiguration() {
        if let data = try? Data(contentsOf: configurationURL),
           let decoded = try? JSONDecoder().decode(OverCUEConfiguration.self, from: data) {
            if decoded.version < OverCUEConfiguration.currentVersion {
                let fallbackMigration = ActionConfigurationMigrator
                    .migrateToCurrentVersion(decoded).configuration
                do {
                    let result = try OverCUEConfigurationFileStore.migrateCurrentIfNeeded(
                        at: configurationURL
                    ) { latestData, _ in
                        let latest = try JSONDecoder().decode(
                            OverCUEConfiguration.self,
                            from: latestData
                        )
                        return ActionConfigurationMigrator
                            .migrateToCurrentVersion(latest).configuration
                    }
                    configuration = result.configuration
                    if let originalData = result.originalData,
                       let sourceVersion = result.sourceVersion {
                        let backupURL = configurationURL.deletingLastPathComponent()
                            .appendingPathComponent("config.v\(sourceVersion).backup.json")
                        if !FileManager.default.fileExists(atPath: backupURL.path) {
                            try? originalData.write(to: backupURL, options: .atomic)
                        }
                    }
                } catch {
                    configuration = fallbackMigration
                }
            } else if decoded.version == OverCUEConfiguration.currentVersion {
                configuration = decoded
            } else {
                configuration = .defaultValue
            }
        } else {
            configuration = .defaultValue
        }
        persistedConfiguration = configuration
        normalizeGroupSettings(defaultMode: mode)
        selectedPresetGroupID = availablePresetGroups.first?.id
        mode = configuredMode(for: selectedGroup)
        runtimeMode = mode
        runtimeGroup = selectedGroup
        rebuildBindings()
    }

    private func normalizeGroupSettings(defaultMode: RekordboxMappingMode) {
        var changed = false
        for profileName in configuration.profiles.keys.sorted() {
            guard var profile = configuration.profiles[profileName] else { continue }
            for group in profile.presetGroups.indices.map({ $0 + 1 }) {
                var mapping = profile.storedMapping(for: group)
                if mapping.rekordboxMode == nil {
                    mapping.rekordboxMode = defaultMode
                    changed = true
                }
                profile.setMapping(mapping, for: group)
            }
            configuration.profiles[profileName] = profile
        }
        if changed { try? saveConfiguration() }
    }

    private func configuredMode(for group: Int) -> RekordboxMappingMode {
        configuration.profiles[configuration.defaultProfile]?
            .mapping(for: group).rekordboxMode ?? mode
    }

    private func presetName(for group: Int) -> String {
        guard availablePresetGroups.indices.contains(group - 1) else { return "Preset" }
        return availablePresetGroups[group - 1].name
    }

    private func saveMode(_ newMode: RekordboxMappingMode, for group: Int) {
        guard var profile = configuration.profiles[configuration.defaultProfile] else { return }
        var mapping = profile.storedMapping(for: group)
        mapping.rekordboxMode = newMode
        profile.setMapping(mapping, for: group)
        configuration.profiles[configuration.defaultProfile] = profile
        do {
            try saveConfiguration()
            OverCUEConfigurationChangedNotification.post()
        } catch {
            showToast(L10n.text("message.modeSaveFailed", error.localizedDescription), style: .error)
        }
    }

    private func applyRuntimeStatus(
        mode newMode: RekordboxMappingMode,
        group: Int,
        presetGroupID: String?,
        deviceID: String,
        logicalDeviceID: String?,
        profileName: String,
        connected: Bool
    ) {
        guard profileName == configuration.defaultProfile else { return }
        let resolvedGroup: Int
        if let presetGroupID,
           let index = availablePresetGroups.firstIndex(where: { $0.id == presetGroupID }) {
            resolvedGroup = index + 1
        } else {
            resolvedGroup = group
        }
        guard !connected || availablePresetGroups.indices.contains(resolvedGroup - 1) else { return }
        let previousFocusedState = runtimeStateRegistry.focusedState
        let nextState = runtimeStateRegistry.apply(
            mode: newMode,
            group: resolvedGroup,
            presetGroupID: presetGroupID,
            deviceID: deviceID,
            logicalDeviceID: logicalDeviceID,
            profileName: profileName,
            defaultProfileName: configuration.defaultProfile,
            connected: connected
        )
        guard let nextState else {
            runtimeDeviceID = nil
            runtimeLogicalDeviceID = nil
            runtimeProfileName = nil
            pressedDeviceKeys = []
            activeDialDirection = nil
            return
        }
        let didChange = previousFocusedState != nextState
        runtimeMode = nextState.mode
        runtimeGroup = nextState.group
        runtimeDeviceID = nextState.target.deviceID
        runtimeLogicalDeviceID = nextState.target.logicalDeviceID
        runtimeProfileName = nextState.target.profileName
        guard didChange else { return }
        showToast(
            L10n.text(
                "message.runtimeState",
                nextState.mode.displayName,
                presetName(for: nextState.group)
            ),
            style: .info
        )
    }

    private func rebuildBindings() {
        guard let profile = configuration.profiles[configuration.defaultProfile] else {
            bindingsByTarget = [:]
            return
        }
        let mapping = profile.mapping(for: selectedGroup)
        let keysByName = Dictionary(uniqueKeysWithValues: ACK05Key.allCases.map {
            ($0.rawValue.uppercased(), $0)
        })
        var result: [String: [ACK05Binding]] = [:]

        for (rawKey, value) in mapping.keyMap {
            guard value != "unassigned",
                  let key = keysByName[rawKey.uppercased()],
                  ActionTarget(configurationValue: value) != nil
            else { continue }
            result[value, default: []].append(.key(key))
        }
        for (rawChord, value) in mapping.chordMap {
            let names = rawChord.uppercased().replacingOccurrences(of: " ", with: "").split(separator: "+")
            let chordKeys = names.compactMap { keysByName[String($0)] }
            guard let chord = KeyChord(keys: chordKeys),
                  ActionTarget(configurationValue: value) != nil
            else { continue }
            result[value, default: []].append(.chord(chord))
        }
        for (rawDirection, value) in mapping.dialMap {
            guard let direction = DialDirection(rawValue: rawDirection),
                  ActionTarget(configurationValue: value) != nil
            else { continue }
            result[value, default: []].append(.dial(direction))
        }
        for (rawChord, value) in mapping.dialChordMap {
            guard let chord = parsedDialChord(rawChord),
                  ActionTarget(configurationValue: value) != nil
            else { continue }
            result[value, default: []].append(.dialChord(chord))
        }
        bindingsByTarget = result
    }

    private func parsedDialChord(_ rawChord: String) -> DialChord? {
        let components = rawChord.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .split(separator: "+")
            .map(String.init)
        guard let rawDirection = components.last else { return nil }
        let direction: DialDirection
        switch rawDirection {
        case "DIAL_RIGHT", "RIGHT", "CLOCKWISE": direction = .clockwise
        case "DIAL_LEFT", "LEFT", "COUNTERCLOCKWISE": direction = .counterclockwise
        default: return nil
        }
        let keysByName = Dictionary(uniqueKeysWithValues: ACK05Key.allCases.map {
            ($0.rawValue.uppercased(), $0)
        })
        let keys = components.dropLast().compactMap { keysByName[$0] }
        guard keys.count == components.count - 1 else { return nil }
        return DialChord(keys: keys, direction: direction)
    }

    private func target(for entry: RekordboxShortcutEntry) -> ActionTarget {
        if entry.commandID.hasPrefix("overcue:"),
           let action = ActionID(rawValue: String(entry.commandID.dropFirst("overcue:".count))) {
            return .action(action)
        }
        return RekordboxActionAdapter.target(for: entry.commandID)
    }

    private func bindingKey(for entry: RekordboxShortcutEntry) -> String {
        target(for: entry).configurationValue
    }

    private func initialSelection(in entries: [RekordboxShortcutEntry]) -> RekordboxShortcutEntry? {
        for key in ACK05Key.allCases {
            let targetKey = bindingsByTarget
                .first(where: { $0.value.contains(.key(key)) })?.key
            if let targetKey,
               let entry = allEntries.first(where: { bindingKey(for: $0) == targetKey }) {
                return entry
            }
        }
        return entries.first
    }

    private func bindingOrder(_ lhs: ACK05Binding, _ rhs: ACK05Binding) -> Bool {
        lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
    }

    private func keyOrder(_ lhs: ACK05Key, _ rhs: ACK05Key) -> Bool {
        guard let left = ACK05Key.allCases.firstIndex(of: lhs),
              let right = ACK05Key.allCases.firstIndex(of: rhs)
        else { return lhs.rawValue < rhs.rawValue }
        return left < right
    }

    private func dialDirectionOrder(_ lhs: DialDirection, _ rhs: DialDirection) -> Bool {
        let order: [DialDirection] = [.counterclockwise, .clockwise]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

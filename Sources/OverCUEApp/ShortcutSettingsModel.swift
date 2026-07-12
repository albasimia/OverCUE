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
    @Published var overwriteConfirmation: OverwriteConfirmation?
    @Published private(set) var pressedDeviceKeys: Set<ACK05Key> = []
    @Published private(set) var activeDialDirection: DialDirection?

    private let loader = RekordboxKeyMappingLoader()
    private let runtimeBridge = OverCUECLIRuntime()
    private let configurationURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/OverCUE/config.json")
    private var configuration: OverCUEConfiguration = .defaultValue
    private var inputMonitor: ACK05InputMonitor?
    private var previousCaptureKeys: Set<ACK05Key> = []
    private var capturedKeyOrder: [ACK05Key] = []
    private var toastDismissTask: Task<Void, Never>?
    private var dialHighlightTask: Task<Void, Never>?
    private var runtimeStatusObserver: SendableObserverToken?
    private var inputStatusObserver: SendableObserverToken?
    private var pendingAssignment: PendingAssignment?

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
                      let group = notification.userInfo?[OverCUERuntimeStatusNotification.groupKey] as? Int
                else { return }
                Task { @MainActor in
                    self?.applyRuntimeStatus(mode: mode, group: group)
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
                Task { @MainActor in
                    guard let self else { return }
                    if includesKeyState {
                        self.pressedDeviceKeys = keys
                    }
                    if let direction {
                        self.showDialInput(direction)
                    }
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
        let wasCapturing = isCapturing
        if isCapturing {
            stopCaptureMonitor()
        }
        saveMode(newMode, for: selectedGroup)
        mode = newMode
        runtimeMode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: "rekordboxMappingMode")
        selectedEntryID = nil
        selectedDeviceKey = nil
        selectedDialDirection = nil
        captureMessage = nil
        captureError = nil
        reload()
        if wasCapturing { startRuntimeIfEnabled() }
        postRuntimeControl(group: selectedGroup, mode: newMode)
        showToast(L10n.text("message.modeUpdated", newMode.displayName), style: .success)
    }

    func setBridgeEnabled(_ enabled: Bool) {
        guard isBridgeEnabled != enabled else { return }
        isBridgeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "ack05BridgeEnabled")
        if enabled {
            guard !isCapturing else { return }
            runtimeMode = mode
            runtimeGroup = selectedGroup
            runtimeBridge.start(mode: mode, group: selectedGroup)
            showToast(L10n.text("message.inputEnabled"), style: .info)
        } else {
            runtimeBridge.stop()
            pressedDeviceKeys = []
            activeDialDirection = nil
            showToast(L10n.text("message.inputStopped"), style: .info)
        }
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
        guard (1...4).contains(group), selectedGroup != group else { return }
        let wasCapturing = isCapturing
        if wasCapturing { stopCaptureMonitor() }
        selectedGroup = group
        mode = configuredMode(for: group)
        runtimeGroup = group
        runtimeMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "rekordboxMappingMode")
        selectedDeviceKey = nil
        selectedDialDirection = nil
        rebuildBindings()
        selectedEntryID = nil
        reload()
        if wasCapturing { startRuntimeIfEnabled() }
        postRuntimeControl(group: group, mode: mode)
        showToast(L10n.text("message.groupSwitched", group, mode.displayName), style: .info)
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

    func beginCapture(for entry: RekordboxShortcutEntry) {
        stopCaptureMonitor()
        runtimeBridge.stop()

        select(entry)
        editingEntryID = entry.id
        previousCaptureKeys = []
        capturedKeyOrder = []
        captureError = nil
        captureMessage = L10n.text("message.capturePrompt")
        showToast(
            captureMessage ?? L10n.text("message.waitingInput"),
            style: .info,
            durationNanoseconds: 6_000_000_000
        )

        let monitor = ACK05InputMonitor()
        monitor.onConnectionChanged = { [weak self] connected in
            guard let self else { return }
            Task { @MainActor in
                self.captureMessage = connected
                    ? L10n.text("message.capturePrompt")
                    : L10n.text("message.waitingDevice")
            }
        }
        monitor.onPressedKeysChanged = { [weak self] keys in
            guard let self else { return }
            Task { @MainActor in
                self.pressedDeviceKeys = keys
                self.handleCapturedKeys(keys)
            }
        }
        monitor.onDialTurned = { [weak self] direction in
            guard let self else { return }
            Task { @MainActor in
                self.showDialInput(direction)
                self.commitDialCapture(direction, heldKeys: self.capturedKeyOrder)
            }
        }

        do {
            try monitor.start()
            inputMonitor = monitor
        } catch {
            editingEntryID = nil
            captureMessage = nil
            captureError = error.localizedDescription
            showToast(error.localizedDescription, style: .error)
            startRuntimeIfEnabled()
        }
    }

    func cancelCapture() {
        stopCaptureMonitor()
        startRuntimeIfEnabled()
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
        guard let editingEntryID,
              let entry = allEntries.first(where: { $0.id == editingEntryID }),
              var profile = configuration.profiles[configuration.defaultProfile]
        else {
            captureError = L10n.text("message.profileMissing")
            cancelCaptureKeepingError()
            return
        }

        let target = target(for: entry)
        let targetKey = target.configurationValue
        if let conflict = keyAssignmentConflict(
            keys: capturedKeyOrder,
            target: target,
            profile: profile
        ) {
            if case .occupied = conflict.kind, !allowOverwrite {
                requestOverwrite(
                    conflict: conflict,
                    target: target,
                    assignment: .keys(entryID: entry.id, keys: capturedKeyOrder)
                )
                return
            } else if !allowOverwrite || !isOccupied(conflict) {
                rejectConflict(conflict, target: target)
                return
            }
        }
        let editedGroup = isGroupCycle(target) ? 1 : selectedGroup
        var mapping = profile.storedMapping(for: editedGroup)
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

        profile.setMapping(mapping, for: editedGroup)
        configuration.profiles[configuration.defaultProfile] = profile
        do {
            try saveConfiguration()
            rebuildBindings()
            selectedEntryID = entry.id
            selectedDeviceKey = highlightedKeys.sorted(by: keyOrder).first
            selectedDialDirection = nil
            captureError = nil
            captureMessage = L10n.text(
                "message.bindingSet",
                entry.description.trimmingCharacters(in: .whitespacesAndNewlines),
                capturedKeyOrder.map { $0.rawValue.uppercased() }.joined(separator: " + ")
            )
            showToast(captureMessage ?? L10n.text("message.bindingUpdated"), style: .success)
            inputMonitor?.stop()
            inputMonitor = nil
            self.editingEntryID = nil
            previousCaptureKeys = []
            capturedKeyOrder = []
            startRuntimeIfEnabled()
        } catch {
            captureError = L10n.text("message.saveFailed", error.localizedDescription)
            showToast(captureError ?? error.localizedDescription, style: .error)
            cancelCaptureKeepingError()
        }
    }

    private func commitDialCapture(
        _ direction: DialDirection,
        heldKeys: [ACK05Key],
        allowOverwrite: Bool = false
    ) {
        guard let editingEntryID,
              let entry = allEntries.first(where: { $0.id == editingEntryID }),
              var profile = configuration.profiles[configuration.defaultProfile]
        else { return }

        let target = target(for: entry)
        if let conflict = dialAssignmentConflict(
            direction: direction,
            heldKeys: heldKeys,
            target: target,
            profile: profile
        ) {
            if case .occupied = conflict.kind, !allowOverwrite {
                requestOverwrite(
                    conflict: conflict,
                    target: target,
                    assignment: .dial(entryID: entry.id, direction: direction, heldKeys: heldKeys)
                )
                return
            } else if !allowOverwrite || !isOccupied(conflict) {
                rejectConflict(conflict, target: target)
                return
            }
        }
        let targetKey = target.configurationValue
        let editedGroup = isGroupCycle(target) ? 1 : selectedGroup
        var mapping = profile.storedMapping(for: editedGroup)
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
        profile.setMapping(mapping, for: editedGroup)
        configuration.profiles[configuration.defaultProfile] = profile

        do {
            try saveConfiguration()
            rebuildBindings()
            selectedEntryID = entry.id
            selectedDeviceKey = highlightedKeys.sorted(by: keyOrder).first
            selectedDialDirection = direction
            captureError = nil
            captureMessage = L10n.text("message.bindingSet", entry.description, inputLabel)
            showToast(captureMessage ?? L10n.text("message.dialUpdated"), style: .success)
            inputMonitor?.stop()
            inputMonitor = nil
            self.editingEntryID = nil
            previousCaptureKeys = []
            capturedKeyOrder = []
            startRuntimeIfEnabled()
        } catch {
            captureError = L10n.text("message.saveFailed", error.localizedDescription)
            showToast(captureError ?? error.localizedDescription, style: .error)
            cancelCaptureKeepingError()
        }
    }

    private func keyAssignmentConflict(
        keys: [ACK05Key],
        target: ActionTarget,
        profile: OverCUEProfile
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
        profile: OverCUEProfile
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
        stopCaptureMonitor()
        startRuntimeIfEnabled()
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
        guard case let .action(action) = target else { return false }
        return action.isGroupCycle
    }

    private func cancelCaptureKeepingError() {
        stopCaptureMonitor()
        startRuntimeIfEnabled()
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
        pressedDeviceKeys = []
        activeDialDirection = nil
    }

    private func startRuntimeIfEnabled() {
        guard isBridgeEnabled else {
            runtimeBridge.stop()
            return
        }
        runtimeMode = mode
        runtimeGroup = selectedGroup
        runtimeBridge.start(mode: mode, group: selectedGroup)
    }

    private func restartRuntimeIfEnabled() {
        guard isBridgeEnabled else {
            runtimeBridge.stop()
            return
        }
        runtimeMode = mode
        runtimeGroup = selectedGroup
        runtimeBridge.restart(mode: mode, group: selectedGroup)
    }

    private func saveConfiguration() throws {
        let directory = configurationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: configurationURL, options: .atomic)
    }

    private func loadConfiguration() {
        if let data = try? Data(contentsOf: configurationURL),
           let decoded = try? JSONDecoder().decode(OverCUEConfiguration.self, from: data) {
            if decoded.version < OverCUEConfiguration.currentVersion {
                let backupURL = configurationURL.deletingLastPathComponent()
                    .appendingPathComponent("config.v\(decoded.version).backup.json")
                if !FileManager.default.fileExists(atPath: backupURL.path) {
                    try? data.write(to: backupURL, options: .atomic)
                }
                configuration = ActionConfigurationMigrator.migrateToCurrentVersion(decoded).configuration
                try? saveConfiguration()
            } else {
                configuration = decoded
            }
        } else {
            configuration = .defaultValue
        }
        normalizeGroupModes(defaultMode: mode)
        mode = configuredMode(for: selectedGroup)
        runtimeMode = mode
        runtimeGroup = selectedGroup
        rebuildBindings()
    }

    private func normalizeGroupModes(defaultMode: RekordboxMappingMode) {
        var changed = false
        for profileName in configuration.profiles.keys.sorted() {
            guard var profile = configuration.profiles[profileName] else { continue }
            for group in 1...4 {
                var mapping = profile.storedMapping(for: group)
                if mapping.rekordboxMode == nil {
                    mapping.rekordboxMode = defaultMode
                    profile.setMapping(mapping, for: group)
                    changed = true
                }
            }
            configuration.profiles[profileName] = profile
        }
        if changed { try? saveConfiguration() }
    }

    private func configuredMode(for group: Int) -> RekordboxMappingMode {
        configuration.profiles[configuration.defaultProfile]?
            .mapping(for: group).rekordboxMode ?? mode
    }

    private func saveMode(_ newMode: RekordboxMappingMode, for group: Int) {
        guard var profile = configuration.profiles[configuration.defaultProfile] else { return }
        var mapping = profile.storedMapping(for: group)
        mapping.rekordboxMode = newMode
        profile.setMapping(mapping, for: group)
        configuration.profiles[configuration.defaultProfile] = profile
        do {
            try saveConfiguration()
        } catch {
            showToast(L10n.text("message.modeSaveFailed", error.localizedDescription), style: .error)
        }
    }

    private func applyRuntimeStatus(mode newMode: RekordboxMappingMode, group: Int) {
        guard (1...4).contains(group) else { return }
        let didChange = runtimeMode != newMode || runtimeGroup != group
        runtimeMode = newMode
        runtimeGroup = group
        guard didChange else { return }

        selectedGroup = group
        mode = newMode
        saveMode(newMode, for: group)
        UserDefaults.standard.set(newMode.rawValue, forKey: "rekordboxMappingMode")
        selectedDeviceKey = nil
        selectedDialDirection = nil
        selectedEntryID = nil
        rebuildBindings()
        reload()
        showToast(L10n.text("message.runtimeState", newMode.displayName, group), style: .info)
    }

    private func postRuntimeControl(group: Int, mode: RekordboxMappingMode) {
        guard isBridgeEnabled else { return }
        DistributedNotificationCenter.default().postNotificationName(
            OverCUERuntimeControlNotification.name,
            object: nil,
            userInfo: [
                OverCUERuntimeControlNotification.groupKey: group,
                OverCUERuntimeControlNotification.modeKey: mode.rawValue,
            ],
            deliverImmediately: true
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

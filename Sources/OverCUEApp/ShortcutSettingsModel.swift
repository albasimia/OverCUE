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

    var keys: Set<ACK05Key> {
        switch self {
        case let .key(key): [key]
        case let .chord(chord): [chord.modifier, chord.trigger]
        }
    }

    var label: String {
        switch self {
        case let .key(key): key.rawValue.uppercased()
        case let .chord(chord): chord.label
        }
    }
}

@MainActor
final class ShortcutSettingsModel: ObservableObject {
    @Published private(set) var mode: RekordboxMappingMode = .export
    @Published var searchText = ""
    @Published var mappingName = "読み込み中…"
    @Published var mappingURL: URL?
    @Published var entries: [RekordboxShortcutEntry] = []
    @Published var selectedEntryID: String?
    @Published var selectedGroup = 1
    @Published var rotationQuarterTurns = 1
    @Published var selectedDeviceKey: ACK05Key?
    @Published var errorMessage: String?
    @Published private(set) var bindingsByCommandID: [String: [ACK05Binding]] = [:]
    @Published private(set) var editingEntryID: String?
    @Published private(set) var captureMessage: String?
    @Published private(set) var captureError: String?
    @Published private(set) var bridgeStatus: OverCUECLIRuntime.Status = .stopped
    @Published private(set) var isBridgeEnabled = true

    private let loader = RekordboxKeyMappingLoader()
    private let runtimeBridge = OverCUECLIRuntime()
    private let configurationURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/OverCUE/config.json")
    private var configuration: OverCUEConfiguration = .defaultValue
    private var inputMonitor: ACK05InputMonitor?
    private var previousCaptureKeys: Set<ACK05Key> = []
    private var capturedKeyOrder: [ACK05Key] = []

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
        runtimeBridge.onStatusChanged = { [weak self] status in
            self?.bridgeStatus = status
        }
        loadConfiguration()
        reload()
        startRuntimeIfEnabled()
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

    var selectedEntry: RekordboxShortcutEntry? {
        guard let selectedEntryID else { return nil }
        return entries.first { $0.id == selectedEntryID }
    }

    var highlightedKeys: Set<ACK05Key> {
        guard selectedGroup == 1, let commandID = selectedEntry?.commandID else { return [] }
        return Set(bindingsByCommandID[commandID, default: []].flatMap(\.keys))
    }

    var isCapturing: Bool { editingEntryID != nil }

    func reload() {
        do {
            let loaded = try loader.load(mode: mode)
            mappingName = loaded.mapping.name
            mappingURL = loaded.url
            entries = loaded.mapping.entries
            errorMessage = nil

            if let selectedEntryID, entries.contains(where: { $0.id == selectedEntryID }) { return }
            selectedEntryID = initialSelection(in: entries)?.id
        } catch {
            mappingName = "読み込み失敗"
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
    }

    func setMode(_ newMode: RekordboxMappingMode) {
        guard mode != newMode else { return }
        if isCapturing {
            stopCaptureMonitor()
        }
        runtimeBridge.stop()
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: "rekordboxMappingMode")
        selectedEntryID = nil
        selectedDeviceKey = nil
        captureMessage = nil
        captureError = nil
        reload()
        startRuntimeIfEnabled()
    }

    func setBridgeEnabled(_ enabled: Bool) {
        guard isBridgeEnabled != enabled else { return }
        isBridgeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "ack05BridgeEnabled")
        if enabled {
            guard !isCapturing else { return }
            runtimeBridge.start(mode: mode)
        } else {
            runtimeBridge.stop()
        }
    }

    func shutdown() {
        stopCaptureMonitor()
        runtimeBridge.stop()
    }

    func select(_ entry: RekordboxShortcutEntry) {
        selectedEntryID = entry.id
        selectedDeviceKey = highlightedKeys.sorted(by: keyOrder).first
    }

    func selectDeviceKey(_ key: ACK05Key) {
        selectedDeviceKey = key
        guard selectedGroup == 1 else { return }
        let commandID = bindingsByCommandID
            .sorted(by: { $0.key < $1.key })
            .first(where: { $0.value.contains(where: { $0.keys.contains(key) }) })?.key
        guard let commandID,
              let entry = entries.first(where: { $0.commandID == commandID })
        else { return }
        selectedEntryID = entry.id
    }

    func rotateDevice() {
        rotationQuarterTurns = (rotationQuarterTurns + 1) % 4
        UserDefaults.standard.set(rotationQuarterTurns, forKey: "deviceRotationQuarterTurns")
    }

    func shortcutAssigned(to key: ACK05Key) -> RekordboxShortcutEntry? {
        guard selectedGroup == 1 else { return nil }
        let preferredCommandID = selectedEntry.flatMap { entry in
            bindingsByCommandID[entry.commandID]?.contains(where: { $0.keys.contains(key) }) == true
                ? entry.commandID
                : nil
        }
        let commandID = preferredCommandID ?? bindingsByCommandID
            .sorted(by: { $0.key < $1.key })
            .first(where: { $0.value.contains(where: { $0.keys.contains(key) }) })?.key
        guard let commandID else { return nil }
        return entries.first { $0.commandID == commandID }
    }

    func bindingLabels(for entry: RekordboxShortcutEntry) -> [String] {
        bindingsByCommandID[entry.commandID, default: []]
            .sorted(by: bindingOrder)
            .map(\.label)
    }

    func isConfigured(_ entry: RekordboxShortcutEntry) -> Bool {
        !bindingsByCommandID[entry.commandID, default: []].isEmpty
    }

    func beginCapture(for entry: RekordboxShortcutEntry) {
        stopCaptureMonitor()
        guard selectedGroup == 1 else {
            captureError = "キーマップ編集は現在グループ1に対応しています。"
            return
        }

        runtimeBridge.stop()

        select(entry)
        editingEntryID = entry.id
        previousCaptureKeys = []
        capturedKeyOrder = []
        captureError = nil
        captureMessage = "ACK05で1つのボタン、または2つのボタンを順に押してください。"

        let monitor = ACK05InputMonitor()
        monitor.onConnectionChanged = { [weak self] connected in
            guard let self else { return }
            Task { @MainActor in
                self.captureMessage = connected
                    ? "ACK05で1つのボタン、または2つのボタンを順に押してください。"
                    : "ACK05の接続を待っています…"
            }
        }
        monitor.onPressedKeysChanged = { [weak self] keys in
            guard let self else { return }
            Task { @MainActor in self.handleCapturedKeys(keys) }
        }

        do {
            try monitor.start()
            inputMonitor = monitor
        } catch {
            editingEntryID = nil
            captureMessage = nil
            captureError = error.localizedDescription
            startRuntimeIfEnabled()
        }
    }

    func cancelCapture() {
        stopCaptureMonitor()
        startRuntimeIfEnabled()
    }

    func removeBindings(for entry: RekordboxShortcutEntry) {
        guard var profile = configuration.profiles[configuration.defaultProfile] else { return }
        for (rawKey, value) in profile.keyMap where commandID(for: value) == entry.commandID {
            profile.keyMap[rawKey] = "unassigned"
        }
        for (rawChord, value) in profile.chordMap where commandID(for: value) == entry.commandID {
            profile.chordMap.removeValue(forKey: rawChord)
        }
        configuration.profiles[configuration.defaultProfile] = profile

        do {
            try saveConfiguration()
            rebuildBindings()
            selectedDeviceKey = nil
            captureError = nil
            captureMessage = "\(entry.description.trimmingCharacters(in: .whitespacesAndNewlines)) のACK05割り当てを削除しました。"
            restartRuntimeIfEnabled()
        } catch {
            captureMessage = nil
            captureError = "設定を保存できませんでした: \(error.localizedDescription)"
        }
    }

    private func handleCapturedKeys(_ keys: Set<ACK05Key>) {
        guard editingEntryID != nil else { return }
        let newlyPressed = keys.subtracting(previousCaptureKeys).sorted(by: keyOrder)
        for key in newlyPressed where !capturedKeyOrder.contains(key) {
            capturedKeyOrder.append(key)
        }
        previousCaptureKeys = keys

        if capturedKeyOrder.count > 2 {
            captureError = "複合キーは2ボタンまでです。もう一度編集を開始してください。"
            cancelCaptureKeepingError()
            return
        }

        if !capturedKeyOrder.isEmpty {
            captureMessage = "入力: \(capturedKeyOrder.map { $0.rawValue.uppercased() }.joined(separator: " + ")) — ボタンを離すと保存します。"
        }
        guard keys.isEmpty, !capturedKeyOrder.isEmpty else { return }
        commitCapture()
    }

    private func commitCapture() {
        guard let editingEntryID,
              let entry = entries.first(where: { $0.id == editingEntryID }),
              var profile = configuration.profiles[configuration.defaultProfile]
        else {
            captureError = "設定の保存先プロファイルが見つかりません。"
            cancelCaptureKeepingError()
            return
        }

        let target = RekordboxActionAdapter.target(for: entry.commandID)
        for (rawKey, value) in profile.keyMap where commandID(for: value) == entry.commandID {
            profile.keyMap[rawKey] = "unassigned"
        }
        for (rawChord, value) in profile.chordMap where commandID(for: value) == entry.commandID {
            profile.chordMap.removeValue(forKey: rawChord)
        }

        switch capturedKeyOrder.count {
        case 1:
            profile.keyMap[capturedKeyOrder[0].rawValue.uppercased()] = target.configurationValue
        case 2:
            let chord = "\(capturedKeyOrder[0].rawValue.uppercased())+\(capturedKeyOrder[1].rawValue.uppercased())"
            profile.chordMap[chord] = target.configurationValue
        default:
            return
        }

        configuration.profiles[configuration.defaultProfile] = profile
        do {
            try saveConfiguration()
            rebuildBindings()
            selectedEntryID = entry.id
            selectedDeviceKey = highlightedKeys.sorted(by: keyOrder).first
            captureError = nil
            captureMessage = "\(entry.description.trimmingCharacters(in: .whitespacesAndNewlines)) を \(capturedKeyOrder.map { $0.rawValue.uppercased() }.joined(separator: " + ")) に設定しました。"
            inputMonitor?.stop()
            inputMonitor = nil
            self.editingEntryID = nil
            previousCaptureKeys = []
            capturedKeyOrder = []
            startRuntimeIfEnabled()
        } catch {
            captureError = "設定を保存できませんでした: \(error.localizedDescription)"
            cancelCaptureKeepingError()
        }
    }

    private func cancelCaptureKeepingError() {
        stopCaptureMonitor()
        startRuntimeIfEnabled()
    }

    private func stopCaptureMonitor() {
        inputMonitor?.stop()
        inputMonitor = nil
        editingEntryID = nil
        captureMessage = nil
        previousCaptureKeys = []
        capturedKeyOrder = []
    }

    private func startRuntimeIfEnabled() {
        guard isBridgeEnabled else {
            runtimeBridge.stop()
            return
        }
        runtimeBridge.start(mode: mode)
    }

    private func restartRuntimeIfEnabled() {
        guard isBridgeEnabled else {
            runtimeBridge.stop()
            return
        }
        runtimeBridge.restart(mode: mode)
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
            configuration = decoded
        } else {
            configuration = .defaultValue
        }
        rebuildBindings()
    }

    private func rebuildBindings() {
        guard let profile = configuration.profiles[configuration.defaultProfile] else {
            bindingsByCommandID = [:]
            return
        }
        let keysByName = Dictionary(uniqueKeysWithValues: ACK05Key.allCases.map {
            ($0.rawValue.uppercased(), $0)
        })
        var result: [String: [ACK05Binding]] = [:]

        for (rawKey, value) in profile.keyMap {
            guard value != "unassigned",
                  let key = keysByName[rawKey.uppercased()],
                  let commandID = commandID(for: value)
            else { continue }
            result[commandID, default: []].append(.key(key))
        }
        for (rawChord, value) in profile.chordMap {
            let names = rawChord.uppercased().replacingOccurrences(of: " ", with: "").split(separator: "+")
            guard names.count == 2,
                  let modifier = keysByName[String(names[0])],
                  let trigger = keysByName[String(names[1])],
                  modifier != trigger,
                  let commandID = commandID(for: value)
            else { continue }
            result[commandID, default: []].append(.chord(KeyChord(modifier: modifier, trigger: trigger)))
        }
        bindingsByCommandID = result
    }

    private func commandID(for configurationValue: String) -> String? {
        guard let target = ActionTarget(configurationValue: configurationValue) else { return nil }
        return RekordboxActionAdapter.commandID(for: target)
    }

    private func initialSelection(in entries: [RekordboxShortcutEntry]) -> RekordboxShortcutEntry? {
        for key in ACK05Key.allCases {
            let commandID = bindingsByCommandID
                .first(where: { $0.value.contains(.key(key)) })?.key
            if let commandID, let entry = entries.first(where: { $0.commandID == commandID }) { return entry }
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
}

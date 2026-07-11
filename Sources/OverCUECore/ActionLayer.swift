public enum ActionID: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case hotCue1 = "hot_cue_1"
    case hotCue2 = "hot_cue_2"
    case hotCue3 = "hot_cue_3"
    case deleteHotCue1 = "delete_hot_cue_1"
    case deleteHotCue2 = "delete_hot_cue_2"
    case deleteHotCue3 = "delete_hot_cue_3"
    case setMemoryCue = "set_memory_cue"
    case deleteMemoryCue = "delete_memory_cue"
    case callNextMemoryCue = "call_next_memory_cue"
    case callPreviousMemoryCue = "call_previous_memory_cue"
    case jumpForward = "jump_forward"
    case jumpBackward = "jump_backward"
    case quantize = "quantize"
    case cue = "cue"
    case playPause = "play_pause"
    case captureWaveformPosition = "capture_waveform_position"
    case jogSearchLeft = "jog_search_left"
    case jogSearchRight = "jog_search_right"
    case cycleGroup = "cycle_group"
    case cycleGroupBackward = "cycle_group_backward"
    case toggleRekordboxMode = "toggle_rekordbox_mode"

    public var displayName: String {
        switch self {
        case .hotCue1: "Hot Cue A"
        case .hotCue2: "Hot Cue B"
        case .hotCue3: "Hot Cue C"
        case .deleteHotCue1: "Delete Hot Cue A"
        case .deleteHotCue2: "Delete Hot Cue B"
        case .deleteHotCue3: "Delete Hot Cue C"
        case .setMemoryCue: "Set Memory Cue"
        case .deleteMemoryCue: "Delete Memory Cue"
        case .callNextMemoryCue: "Call Next Memory Cue"
        case .callPreviousMemoryCue: "Call Previous Memory Cue"
        case .jumpForward: "Jump Forward"
        case .jumpBackward: "Jump Backward"
        case .quantize: "Quantize"
        case .cue: "Cue"
        case .playPause: "Play/Pause"
        case .captureWaveformPosition: "Capture Waveform Position"
        case .jogSearchLeft: "Jog Search Left"
        case .jogSearchRight: "Jog Search Right"
        case .cycleGroup: "Cycle Group Ascending 1–4"
        case .cycleGroupBackward: "Cycle Group Descending 4–1"
        case .toggleRekordboxMode: "Toggle EXPORT / PERFORMANCE"
        }
    }

    public var behavior: ActionBehavior {
        switch self {
        case .cue: .hold
        case .jumpForward, .jumpBackward: .acceleratingRepeat
        case .captureWaveformPosition, .jogSearchLeft, .jogSearchRight,
             .cycleGroup, .cycleGroupBackward, .toggleRekordboxMode: .internalCommand
        default: .trigger
        }
    }

    public var isGroupCycle: Bool {
        self == .cycleGroup || self == .cycleGroupBackward
    }

    public init?(legacyDisplayName: String) {
        guard let action = Self.allCases.first(where: { $0.displayName == legacyDisplayName }) else {
            return nil
        }
        self = action
    }
}

public enum ActionBehavior: Equatable, Sendable {
    case trigger
    case hold
    case acceleratingRepeat
    case internalCommand
}

public enum ActionTarget: Equatable, Hashable, Sendable {
    case action(ActionID)
    case rekordboxCommand(String)

    public init?(configurationValue: String) {
        if let action = ActionID(rawValue: configurationValue) {
            self = .action(action)
        } else if configurationValue.hasPrefix("rekordbox:") {
            let commandID = String(configurationValue.dropFirst("rekordbox:".count))
            guard !commandID.isEmpty else { return nil }
            self = .rekordboxCommand(commandID)
        } else {
            return nil
        }
    }

    public var configurationValue: String {
        switch self {
        case let .action(action): action.rawValue
        case let .rekordboxCommand(commandID): "rekordbox:\(commandID)"
        }
    }

    public var behavior: ActionBehavior {
        switch self {
        case let .action(action): action.behavior
        case .rekordboxCommand: .trigger
        }
    }

    public var displayName: String {
        switch self {
        case let .action(action): action.displayName
        case let .rekordboxCommand(commandID): "rekordbox \(commandID)"
        }
    }
}

public enum ActionPhase: Equatable, Sendable {
    case triggered
    case pressed
    case released
    case repeated
}

public struct ActionEvent: Equatable, Sendable {
    public let target: ActionTarget
    public let phase: ActionPhase
    public let sourceKey: ACK05Key?
    public let sourceLabel: String

    public init(
        action: ActionID,
        phase: ActionPhase,
        sourceKey: ACK05Key?,
        sourceLabel: String
    ) {
        target = .action(action)
        self.phase = phase
        self.sourceKey = sourceKey
        self.sourceLabel = sourceLabel
    }


    public init(
        target: ActionTarget,
        phase: ActionPhase,
        sourceKey: ACK05Key?,
        sourceLabel: String
    ) {
        self.target = target
        self.phase = phase
        self.sourceKey = sourceKey
        self.sourceLabel = sourceLabel
    }

    public var action: ActionID? {
        guard case let .action(action) = target else { return nil }
        return action
    }
}

public struct KeyChord: Equatable, Hashable, Sendable {
    public let keys: [ACK05Key]

    public init(modifier: ACK05Key, trigger: ACK05Key) {
        keys = [modifier, trigger]
    }

    public init?(keys: [ACK05Key]) {
        guard keys.count >= 2,
              keys.count <= ACK05Key.allCases.count,
              Set(keys).count == keys.count
        else { return nil }
        self.keys = keys
    }

    public var modifier: ACK05Key { keys[0] }
    public var trigger: ACK05Key { keys[keys.count - 1] }
    public var modifiers: ArraySlice<ACK05Key> { keys.dropLast() }

    public var label: String {
        keys.map { $0.rawValue.uppercased() }.joined(separator: "+")
    }
}

public struct DialChord: Equatable, Hashable, Sendable {
    public let keys: [ACK05Key]
    public let direction: DialDirection

    public init?(keys: [ACK05Key], direction: DialDirection) {
        guard !keys.isEmpty,
              keys.count <= ACK05Key.allCases.count,
              Set(keys).count == keys.count
        else { return nil }
        self.keys = keys
        self.direction = direction
    }

    public var label: String {
        let dial = direction == .clockwise ? "DIAL_RIGHT" : "DIAL_LEFT"
        return (keys.map { $0.rawValue.uppercased() } + [dial]).joined(separator: "+")
    }
}

public struct ActionMapping: Equatable, Sendable {
    public let keys: [ACK05Key: ActionTarget]
    public let chords: [KeyChord: ActionTarget]
    public let dial: [DialDirection: ActionTarget]
    public let dialChords: [DialChord: ActionTarget]

    public init(
        keys: [ACK05Key: ActionID],
        chords: [KeyChord: ActionID],
        dial: [DialDirection: ActionID] = [:],
        dialChords: [DialChord: ActionID] = [:]
    ) {
        self.keys = keys.mapValues(ActionTarget.action)
        self.chords = chords.mapValues(ActionTarget.action)
        self.dial = dial.mapValues(ActionTarget.action)
        self.dialChords = dialChords.mapValues(ActionTarget.action)
    }

    public init(
        keys: [ACK05Key: ActionTarget],
        chords: [KeyChord: ActionTarget],
        dial: [DialDirection: ActionTarget] = [:],
        dialChords: [DialChord: ActionTarget] = [:]
    ) {
        self.keys = keys
        self.chords = chords
        self.dial = dial
        self.dialChords = dialChords
    }

    public var modifierKeys: Set<ACK05Key> {
        Set(chords.keys.flatMap(\.modifiers) + dialChords.keys.flatMap(\.keys))
    }
}

public struct InputActionResolver: Equatable, Sendable {
    public private(set) var pressedKeys: Set<ACK05Key> = []
    private var usedChordModifiers: Set<ACK05Key> = []
    private var suppressedChordTriggers: Set<ACK05Key> = []
    private var activeHoldKeys: Set<ACK05Key> = []

    public init() {}

    public mutating func handle(
        pressedKeys nextPressedKeys: Set<ACK05Key>,
        mapping: ActionMapping
    ) -> [ActionEvent] {
        let newlyPressed = nextPressedKeys.subtracting(pressedKeys)
        let released = pressedKeys.subtracting(nextPressedKeys)
        var events: [ActionEvent] = []

        var consumedChordTriggers: Set<ACK05Key> = []
        for chord in mapping.chords.keys.sorted(by: {
            if $0.keys.count != $1.keys.count { return $0.keys.count > $1.keys.count }
            return $0.label < $1.label
        })
        where newlyPressed.contains(chord.trigger)
            && Set(chord.keys).isSubset(of: nextPressedKeys)
            && !consumedChordTriggers.contains(chord.trigger) {
            guard let target = mapping.chords[chord] else { continue }
            events.append(
                ActionEvent(
                    target: target,
                    phase: .triggered,
                    sourceKey: chord.trigger,
                    sourceLabel: chord.label
                )
            )
            usedChordModifiers.formUnion(chord.modifiers)
            suppressedChordTriggers.insert(chord.trigger)
            consumedChordTriggers.insert(chord.trigger)
        }

        for key in ACK05Key.allCases where newlyPressed.contains(key) {
            if mapping.modifierKeys.contains(key) { continue }
            if suppressedChordTriggers.contains(key) { continue }
            guard let target = mapping.keys[key] else { continue }
            let phase: ActionPhase = target.behavior == .hold || target.behavior == .acceleratingRepeat
                ? .pressed
                : .triggered
            events.append(event(target: target, phase: phase, key: key))
            if target.behavior == .hold {
                activeHoldKeys.insert(key)
            }
        }

        for key in released where activeHoldKeys.remove(key) != nil {
            guard let target = mapping.keys[key] else { continue }
            events.append(event(target: target, phase: .released, key: key))
        }

        for modifier in released where mapping.modifierKeys.contains(modifier) {
            if !usedChordModifiers.contains(modifier),
               !suppressedChordTriggers.contains(modifier),
               let target = mapping.keys[modifier] {
                events.append(event(target: target, phase: .triggered, key: modifier))
            }
        }

        usedChordModifiers.subtract(released)
        suppressedChordTriggers.subtract(released)
        pressedKeys = nextPressedKeys
        return events
    }

    public func repeatedEvent(for key: ACK05Key, mapping: ActionMapping) -> ActionEvent? {
        guard pressedKeys.contains(key),
              let target = mapping.keys[key],
              target.behavior == .acceleratingRepeat
        else {
            return nil
        }
        return event(target: target, phase: .repeated, key: key)
    }

    public mutating func dialEvent(
        for direction: DialDirection,
        mapping: ActionMapping
    ) -> ActionEvent? {
        let candidates = mapping.dialChords.keys
            .filter { $0.direction == direction && Set($0.keys).isSubset(of: pressedKeys) }
            .sorted {
                if $0.keys.count != $1.keys.count { return $0.keys.count > $1.keys.count }
                return $0.label < $1.label
            }
        guard let chord = candidates.first, let target = mapping.dialChords[chord] else { return nil }
        usedChordModifiers.formUnion(chord.keys)
        return ActionEvent(
            target: target,
            phase: .triggered,
            sourceKey: nil,
            sourceLabel: chord.label.replacingOccurrences(of: "_", with: " ")
        )
    }

    public mutating func reset(mapping: ActionMapping) -> [ActionEvent] {
        let releases = activeHoldKeys.compactMap { key -> ActionEvent? in
            guard let target = mapping.keys[key] else { return nil }
            return event(target: target, phase: .released, key: key)
        }
        pressedKeys = []
        usedChordModifiers = []
        suppressedChordTriggers = []
        activeHoldKeys = []
        return releases
    }

    private func event(target: ActionTarget, phase: ActionPhase, key: ACK05Key) -> ActionEvent {
        ActionEvent(
            target: target,
            phase: phase,
            sourceKey: key,
            sourceLabel: key.rawValue.uppercased()
        )
    }
}

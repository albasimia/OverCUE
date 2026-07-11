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
        }
    }

    public var behavior: ActionBehavior {
        switch self {
        case .cue: .hold
        case .jumpForward, .jumpBackward: .acceleratingRepeat
        case .captureWaveformPosition: .internalCommand
        default: .trigger
        }
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

public enum ActionPhase: Equatable, Sendable {
    case triggered
    case pressed
    case released
    case repeated
}

public struct ActionEvent: Equatable, Sendable {
    public let action: ActionID
    public let phase: ActionPhase
    public let sourceKey: ACK05Key?
    public let sourceLabel: String

    public init(
        action: ActionID,
        phase: ActionPhase,
        sourceKey: ACK05Key?,
        sourceLabel: String
    ) {
        self.action = action
        self.phase = phase
        self.sourceKey = sourceKey
        self.sourceLabel = sourceLabel
    }
}

public struct KeyChord: Equatable, Hashable, Sendable {
    public let modifier: ACK05Key
    public let trigger: ACK05Key

    public init(modifier: ACK05Key, trigger: ACK05Key) {
        self.modifier = modifier
        self.trigger = trigger
    }

    public var label: String {
        "\(modifier.rawValue.uppercased())+\(trigger.rawValue.uppercased())"
    }
}

public struct ActionMapping: Equatable, Sendable {
    public let keys: [ACK05Key: ActionID]
    public let chords: [KeyChord: ActionID]

    public init(keys: [ACK05Key: ActionID], chords: [KeyChord: ActionID]) {
        self.keys = keys
        self.chords = chords
    }

    public var modifierKeys: Set<ACK05Key> {
        Set(chords.keys.map(\.modifier))
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

        for chord in mapping.chords.keys.sorted(by: { $0.label < $1.label })
        where newlyPressed.contains(chord.trigger)
            && nextPressedKeys.contains(chord.modifier) {
            guard let action = mapping.chords[chord] else { continue }
            events.append(
                ActionEvent(
                    action: action,
                    phase: .triggered,
                    sourceKey: chord.trigger,
                    sourceLabel: chord.label
                )
            )
            usedChordModifiers.insert(chord.modifier)
            suppressedChordTriggers.insert(chord.trigger)
        }

        for key in ACK05Key.allCases where newlyPressed.contains(key) {
            if mapping.modifierKeys.contains(key) { continue }
            if suppressedChordTriggers.contains(key) { continue }
            guard let action = mapping.keys[key] else { continue }
            let phase: ActionPhase = action.behavior == .hold || action.behavior == .acceleratingRepeat
                ? .pressed
                : .triggered
            events.append(event(action: action, phase: phase, key: key))
            if action.behavior == .hold {
                activeHoldKeys.insert(key)
            }
        }

        for key in released where activeHoldKeys.remove(key) != nil {
            guard let action = mapping.keys[key] else { continue }
            events.append(event(action: action, phase: .released, key: key))
        }

        for modifier in released where mapping.modifierKeys.contains(modifier) {
            if !usedChordModifiers.contains(modifier),
               !suppressedChordTriggers.contains(modifier),
               let action = mapping.keys[modifier] {
                events.append(event(action: action, phase: .triggered, key: modifier))
            }
        }

        usedChordModifiers.subtract(released)
        suppressedChordTriggers.subtract(released)
        pressedKeys = nextPressedKeys
        return events
    }

    public func repeatedEvent(for key: ACK05Key, mapping: ActionMapping) -> ActionEvent? {
        guard pressedKeys.contains(key),
              let action = mapping.keys[key],
              action.behavior == .acceleratingRepeat
        else {
            return nil
        }
        return event(action: action, phase: .repeated, key: key)
    }

    public mutating func reset(mapping: ActionMapping) -> [ActionEvent] {
        let releases = activeHoldKeys.compactMap { key -> ActionEvent? in
            guard let action = mapping.keys[key] else { return nil }
            return event(action: action, phase: .released, key: key)
        }
        pressedKeys = []
        usedChordModifiers = []
        suppressedChordTriggers = []
        activeHoldKeys = []
        return releases
    }

    private func event(action: ActionID, phase: ActionPhase, key: ACK05Key) -> ActionEvent {
        ActionEvent(
            action: action,
            phase: phase,
            sourceKey: key,
            sourceLabel: key.rawValue.uppercased()
        )
    }
}

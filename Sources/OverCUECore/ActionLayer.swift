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
    public let keys: [ACK05Key: ActionTarget]
    public let chords: [KeyChord: ActionTarget]

    public init(keys: [ACK05Key: ActionID], chords: [KeyChord: ActionID]) {
        self.keys = keys.mapValues(ActionTarget.action)
        self.chords = chords.mapValues(ActionTarget.action)
    }

    public init(keys: [ACK05Key: ActionTarget], chords: [KeyChord: ActionTarget]) {
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
            guard let target = mapping.chords[chord] else { continue }
            events.append(
                ActionEvent(
                    target: target,
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

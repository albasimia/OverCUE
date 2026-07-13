public enum RekordboxActionAdapter {
    public static func commandID(for action: ActionID) -> String? {
        switch action {
        case .hotCue1: "301e"
        case .hotCue2: "301f"
        case .hotCue3: "3020"
        case .deleteHotCue1: "3021"
        case .deleteHotCue2: "3022"
        case .deleteHotCue3: "3023"
        case .setMemoryCue: "3024"
        case .deleteMemoryCue: "303b"
        case .callNextMemoryCue: "3039"
        case .callPreviousMemoryCue: "303a"
        case .jumpForward: "3008"
        case .jumpBackward: "3009"
        case .quantize: "301c"
        case .cue: "3007"
        case .playPause: "3006"
        case .captureWaveformPosition, .jogSearchLeft, .jogSearchRight,
            .cycleGroup, .cycleGroupBackward, .toggleRekordboxMode:
            nil
        }
    }

    public static func commandID(for target: ActionTarget) -> String? {
        switch target {
        case let .action(action): commandID(for: action)
        case let .rekordboxCommand(commandID): commandID
        }
    }

    public static func action(for commandID: String) -> ActionID? {
        ActionID.allCases.first { self.commandID(for: $0) == commandID }
    }

    public static func target(for commandID: String) -> ActionTarget {
        if let action = action(for: commandID) {
            return .action(action)
        }
        return .rekordboxCommand(commandID)
    }
}

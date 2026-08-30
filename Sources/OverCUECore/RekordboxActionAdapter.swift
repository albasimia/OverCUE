import Foundation

public enum RekordboxActionAdapter {
    // rekordbox PERFORMANCE KeyMappings use 30xx...33xx for Decks 1...4.
    // The operation suffix is the single source of truth shared by every deck.
    private static func commandSuffix(for action: ActionID) -> String? {
        switch action {
        case .hotCue1: "1e"
        case .hotCue2: "1f"
        case .hotCue3: "20"
        case .deleteHotCue1: "21"
        case .deleteHotCue2: "22"
        case .deleteHotCue3: "23"
        case .setMemoryCue: "24"
        case .deleteMemoryCue: "3b"
        case .callNextMemoryCue: "39"
        case .callPreviousMemoryCue: "3a"
        case .jumpForward: "08"
        case .jumpBackward: "09"
        case .quantize: "1c"
        case .cue: "07"
        case .playPause: "06"
        case .pitchBendIncrease: "4f"
        case .pitchBendDecrease: "50"
        case .captureWaveformPosition, .jogSearchLeft, .jogSearchRight,
             .cycleGroup, .cycleGroupBackward, .toggleRekordboxMode: nil
        }
    }

    public static func commandID(
        for action: ActionID,
        deck: RekordboxDeck = .deck1
    ) -> String? {
        guard let suffix = commandSuffix(for: action) else { return nil }
        return String(format: "%02x", 0x30 + deck.rawValue - 1) + suffix
    }

    public static func commandID(
        for target: ActionTarget,
        deck: RekordboxDeck = .deck1
    ) -> String? {
        switch target {
        case let .action(action): commandID(for: action, deck: deck)
        case let .rekordboxCommand(commandID): commandID
        }
    }

    public static func action(for commandID: String) -> ActionID? {
        let normalized = commandID.lowercased()
        for deck in RekordboxDeck.allCases {
            if let action = ActionID.allCases.first(where: {
                self.commandID(for: $0, deck: deck) == normalized
            }) {
                return action
            }
        }
        return nil
    }

    public static func target(for commandID: String) -> ActionTarget {
        if let action = action(for: commandID) {
            return .action(action)
        }
        return .rekordboxCommand(commandID)
    }
}

public struct MIDIMessage: Equatable, Sendable {
    public let status: UInt8
    public let data1: UInt8
    public let data2: UInt8

    public init(status: UInt8, data1: UInt8, data2: UInt8) {
        self.status = status
        self.data1 = data1
        self.data2 = data2
    }

    public var bytes: [UInt8] {
        [status, data1, data2]
    }
}

public enum JogCommand: Equatable, Sendable {
    case touchOn
    case touchOff
    case scratch(DialDirection)
}

public struct JogStateMachine: Sendable {
    public private(set) var isTouchActive = false

    public init() {}

    public mutating func rotate(_ direction: DialDirection) -> [JogCommand] {
        var commands: [JogCommand] = []
        if !isTouchActive {
            isTouchActive = true
            commands.append(.touchOn)
        }
        commands.append(.scratch(direction))
        return commands
    }

    public mutating func touchDidTimeout() -> [JogCommand] {
        guard isTouchActive else { return [] }
        isTouchActive = false
        return [.touchOff]
    }
}

public enum DDJSXMIDIProfileError: Error, Equatable {
    case invalidDeck(Int)
}

public struct DDJSXMIDIProfile: Sendable {
    public let deck: Int

    public init(deck: Int = 1) throws {
        guard (1...4).contains(deck) else {
            throw DDJSXMIDIProfileError.invalidDeck(deck)
        }
        self.deck = deck
    }

    public func message(for command: JogCommand) -> MIDIMessage {
        let channelOffset = UInt8(deck - 1)

        switch command {
        case .touchOn:
            return MIDIMessage(status: 0x90 + channelOffset, data1: 0x36, data2: 0x7F)
        case .touchOff:
            return MIDIMessage(status: 0x90 + channelOffset, data1: 0x36, data2: 0x00)
        case .scratch(.clockwise):
            return MIDIMessage(status: 0xB0 + channelOffset, data1: 0x22, data2: 0x41)
        case .scratch(.counterclockwise):
            return MIDIMessage(status: 0xB0 + channelOffset, data1: 0x22, data2: 0x3F)
        }
    }
}

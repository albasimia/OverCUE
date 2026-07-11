import Foundation

public struct RekordboxKeyboardShortcut: Equatable, Sendable {
    public struct Modifiers: OptionSet, Equatable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    public let rawValue: String
    public let keyCode: UInt16
    public let modifiers: Modifiers

    public init(rawValue: String) throws {
        self.rawValue = rawValue
        let components = rawValue
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard let keyName = components.last,
              !keyName.isEmpty,
              let keyCode = Self.keyCodes[keyName]
        else {
            throw RekordboxKeyboardShortcutError.unsupportedShortcut(rawValue)
        }
        self.keyCode = keyCode

        var modifiers: Modifiers = []
        for modifier in components.dropLast() {
            switch modifier {
            case "command", "cmd": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "option", "alt": modifiers.insert(.option)
            case "ctrl", "control": modifiers.insert(.control)
            default: throw RekordboxKeyboardShortcutError.unsupportedModifier(modifier)
            }
        }
        self.modifiers = modifiers
    }

    private static let keyCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5,
        "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39,
        "k": 40, ";": 41, ":": 41, "\\": 42, ",": 43, "<": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, ">": 47,
        "tab": 48, "spacebar": 49, "space": 49, "`": 50,
        "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
        "¥": 93, "cursor left": 123, "cursor right": 124,
        "cursor down": 125, "cursor up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96,
        "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109,
        "f11": 103, "f12": 111, "f13": 105, "f14": 107, "f15": 113,
        "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
    ]
}

public enum RekordboxKeyboardShortcutError: Error, LocalizedError, Equatable {
    case unsupportedShortcut(String)
    case unsupportedModifier(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedShortcut(value): "未対応のrekordboxショートカットです: \(value)"
        case let .unsupportedModifier(value): "未対応のショートカット修飾キーです: \(value)"
        }
    }
}

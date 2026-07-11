public enum ACK05PhysicalInput: Equatable, Sendable {
    case key(ACK05Key)
    case chord(KeyChord)
    case dial(DialDirection)
    case dialChord(DialChord)

    public var label: String {
        switch self {
        case let .key(key): return key.rawValue.uppercased()
        case let .chord(chord):
            return chord.keys.map { $0.rawValue.uppercased() }.joined(separator: " + ")
        case .dial(.clockwise): return "DIAL →"
        case .dial(.counterclockwise): return "DIAL ←"
        case let .dialChord(chord):
            let dial = chord.direction == .clockwise ? "DIAL →" : "DIAL ←"
            return (chord.keys.map { $0.rawValue.uppercased() } + [dial]).joined(separator: " + ")
        }
    }
}

public struct ActionMappingConflict: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case occupied(existing: ActionTarget)
        case longPressTargetUsesChord(chord: KeyChord, chordTarget: ActionTarget)
        case chordUsesLongPressModifier(key: ACK05Key, existing: ActionTarget)
        case longPressTargetUsesDialChord(chord: DialChord, chordTarget: ActionTarget)
        case dialChordUsesLongPressModifier(key: ACK05Key, existing: ActionTarget)
    }

    public let input: ACK05PhysicalInput
    public let group: Int
    public let kind: Kind
}

public enum ActionMappingConflictDetector {
    public static func conflict(
        for input: ACK05PhysicalInput,
        target: ActionTarget,
        profile: OverCUEProfile,
        selectedGroup: Int
    ) -> ActionMappingConflict? {
        let groups = isGroupCycle(target) ? Array(1...4) : [selectedGroup]
        for group in groups {
            let mapping = profile.mapping(for: group)
            if let existing = existingTarget(for: input, mapping: mapping, group: group),
               existing != target {
                return ActionMappingConflict(input: input, group: group, kind: .occupied(existing: existing))
            }

            switch input {
            case let .key(key) where isLongPress(target.behavior):
                for (rawChord, rawAction) in mapping.chordMap.sorted(by: { $0.key < $1.key }) {
                    guard let chord = parseChord(rawChord),
                          chord.modifiers.contains(key),
                          let chordTarget = ActionTarget(configurationValue: rawAction)
                    else { continue }
                    return ActionMappingConflict(
                        input: input,
                        group: group,
                        kind: .longPressTargetUsesChord(chord: chord, chordTarget: chordTarget)
                    )
                }
                for (rawChord, rawAction) in mapping.dialChordMap.sorted(by: { $0.key < $1.key }) {
                    guard let chord = parseDialChord(rawChord),
                          chord.keys.contains(key),
                          let chordTarget = ActionTarget(configurationValue: rawAction)
                    else { continue }
                    return ActionMappingConflict(
                        input: input,
                        group: group,
                        kind: .longPressTargetUsesDialChord(chord: chord, chordTarget: chordTarget)
                    )
                }
            case let .chord(chord):
                for modifier in chord.modifiers {
                    guard let rawAction = effectiveKeyAction(
                        mapping: mapping,
                        key: modifier,
                        group: group
                    ),
                    let existing = ActionTarget(configurationValue: rawAction),
                    isLongPress(existing.behavior)
                    else { continue }
                    return ActionMappingConflict(
                        input: input,
                        group: group,
                        kind: .chordUsesLongPressModifier(key: modifier, existing: existing)
                    )
                }
            case let .dialChord(chord):
                for key in chord.keys {
                    guard let rawAction = effectiveKeyAction(mapping: mapping, key: key, group: group),
                          let existing = ActionTarget(configurationValue: rawAction),
                          isLongPress(existing.behavior)
                    else { continue }
                    return ActionMappingConflict(
                        input: input,
                        group: group,
                        kind: .dialChordUsesLongPressModifier(key: key, existing: existing)
                    )
                }
            default:
                break
            }
        }
        return nil
    }

    private static func isGroupCycle(_ target: ActionTarget) -> Bool {
        guard case let .action(action) = target else { return false }
        return action.isGroupCycle
    }

    private static func existingTarget(
        for input: ACK05PhysicalInput,
        mapping: OverCUEGroupMapping,
        group: Int
    ) -> ActionTarget? {
        let rawAction: String?
        switch input {
        case let .key(key):
            rawAction = effectiveKeyAction(mapping: mapping, key: key, group: group)
        case let .chord(chord):
            rawAction = mapping.chordMap.first(where: {
                parseChord($0.key) == chord
            })?.value
        case let .dial(direction):
            rawAction = mapping.dialMap[direction.rawValue]
        case let .dialChord(chord):
            rawAction = mapping.dialChordMap.first(where: {
                parseDialChord($0.key) == chord
            })?.value
        }
        guard let rawAction, rawAction != "unassigned" else { return nil }
        return ActionTarget(configurationValue: rawAction)
    }

    private static func effectiveKeyAction(
        mapping: OverCUEGroupMapping,
        key: ACK05Key,
        group: Int
    ) -> String? {
        let name = key.rawValue.uppercased()
        return mapping.keyMap[name]
            ?? (group == 1 ? OverCUEProfile.defaultValue.keyMap[name] : nil)
    }

    private static func parseChord(_ rawChord: String) -> KeyChord? {
        let keysByName = Dictionary(uniqueKeysWithValues: ACK05Key.allCases.map {
            ($0.rawValue.uppercased(), $0)
        })
        let names = rawChord.uppercased().replacingOccurrences(of: " ", with: "").split(separator: "+")
        let keys = names.compactMap { keysByName[String($0)] }
        guard keys.count == names.count else { return nil }
        return KeyChord(keys: keys)
    }

    private static func parseDialChord(_ rawChord: String) -> DialChord? {
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

    private static func isLongPress(_ behavior: ActionBehavior) -> Bool {
        behavior == .hold || behavior == .acceleratingRepeat
    }
}

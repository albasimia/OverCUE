public enum DialDirection: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case clockwise
    case counterclockwise

    public var displayName: String {
        switch self {
        case .clockwise: "Dial Right"
        case .counterclockwise: "Dial Left"
        }
    }
}

public enum ACK05Key: String, CaseIterable, Equatable, Hashable, Sendable {
    case k1
    case k2
    case k3
    case k4
    case k5
    case k6
    case k7
    case k8
    case k9
    case k10
}

public enum ACK05Event: Equatable, Sendable {
    case dial(DialDirection)
    case keyDown(ACK05Key)
    case allReleased
}

public struct ACK05ReportDecoder: Sendable {
    public static let reportID: UInt32 = 0x06
    public static let reportLength = 8

    public init() {}

    public func decode(reportID: UInt32, bytes: [UInt8]) -> ACK05Event? {
        guard reportID == Self.reportID,
            bytes.count == Self.reportLength,
            bytes[0] == UInt8(Self.reportID),
            bytes.dropFirst(3).allSatisfy({ $0 == 0 })
        else {
            return nil
        }

        let modifier = bytes[1]
        let usage = bytes[2]

        switch (modifier, usage) {
        case (0x01, 0x57):
            return .dial(.clockwise)
        case (0x01, 0x56):
            return .dial(.counterclockwise)
        case (0x01, 0x12):
            return .keyDown(.k1)
        case (0x01, 0x11):
            return .keyDown(.k2)
        case (0x00, 0x3E):
            return .keyDown(.k3)
        case (0x02, 0x00):
            return .keyDown(.k4)
        case (0x01, 0x00):
            return .keyDown(.k5)
        case (0x04, 0x00):
            return .keyDown(.k6)
        case (0x01, 0x16):
            return .keyDown(.k7)
        case (0x01, 0x1D):
            return .keyDown(.k8)
        case (0x00, 0x2C):
            return .keyDown(.k9)
        case (0x03, 0x1D):
            return .keyDown(.k10)
        case (0x00, 0x00):
            return .allReleased
        default:
            return nil
        }
    }

    public func pressedKeys(reportID: UInt32, bytes: [UInt8]) -> Set<ACK05Key>? {
        guard reportID == Self.reportID,
            bytes.count == Self.reportLength,
            bytes[0] == UInt8(Self.reportID)
        else {
            return nil
        }

        let modifier = bytes[1]
        let usages = Set(bytes.dropFirst(2).filter { $0 != 0 })

        if usages.contains(0x56) || usages.contains(0x57) {
            return nil
        }

        var keys: Set<ACK05Key> = []
        if usages.contains(0x12), modifier & 0x01 != 0 { keys.insert(.k1) }
        if usages.contains(0x11), modifier & 0x01 != 0 { keys.insert(.k2) }
        if usages.contains(0x3E) { keys.insert(.k3) }
        if modifier & 0x02 != 0, !usages.contains(0x1D) { keys.insert(.k4) }
        if modifier == 0x01, usages.isEmpty { keys.insert(.k5) }
        if modifier == 0x04, usages.isEmpty { keys.insert(.k6) }
        if usages.contains(0x16), modifier & 0x01 != 0 { keys.insert(.k7) }
        if usages.contains(0x1D) {
            if modifier & 0x03 == 0x03 {
                keys.insert(.k10)
            } else if modifier & 0x01 != 0 {
                keys.insert(.k8)
            }
        }
        if usages.contains(0x2C) { keys.insert(.k9) }

        return keys
    }

    public func pressedKeys(
        reportID: UInt32,
        bytes: [UInt8],
        previousKeys: Set<ACK05Key>
    ) -> Set<ACK05Key>? {
        guard reportID == Self.reportID,
            bytes.count == Self.reportLength,
            bytes[0] == UInt8(Self.reportID)
        else {
            return nil
        }

        let modifier = bytes[1]
        let usages = Set(bytes.dropFirst(2).filter { $0 != 0 })
        if usages.contains(0x56) || usages.contains(0x57) {
            return nil
        }

        let keys = ACK05Key.allCases
        var best: (keys: Set<ACK05Key>, retained: Int, changes: Int, count: Int, mask: Int)?
        var matches: [(keys: Set<ACK05Key>, mask: Int)] = []

        for mask in 0..<(1 << keys.count) {
            var candidate: Set<ACK05Key> = []
            var candidateModifier: UInt8 = 0
            var candidateUsages: Set<UInt8> = []

            for (index, key) in keys.enumerated() where mask & (1 << index) != 0 {
                candidate.insert(key)
                let signature = Self.signature(for: key)
                candidateModifier |= signature.modifier
                if let usage = signature.usage {
                    candidateUsages.insert(usage)
                }
            }

            guard candidateModifier == modifier, candidateUsages == usages else { continue }
            matches.append((candidate, mask))
            let retained = candidate.intersection(previousKeys).count
            let changes = candidate.symmetricDifference(previousKeys).count
            let score = (candidate, retained, changes, candidate.count, mask)

            if let current = best {
                let isBetter =
                    retained > current.retained
                    || (retained == current.retained && changes < current.changes)
                    || (retained == current.retained && changes == current.changes
                        && candidate.count < current.count)
                    || (retained == current.retained && changes == current.changes
                        && candidate.count == current.count && mask < current.mask)
                if isBetter { best = score }
            } else {
                best = score
            }
        }

        if best?.keys == previousKeys,
            let expanded =
                matches
                .filter({ candidate in
                    previousKeys.isSubset(of: candidate.keys)
                        && candidate.keys.count == previousKeys.count + 1
                        && candidate.keys.subtracting(previousKeys).allSatisfy {
                            Self.signature(for: $0).usage == nil
                        }
                })
                .sorted(by: { $0.mask < $1.mask })
                .first
        {
            return expanded.keys
        }

        return best?.keys
    }

    private static func signature(for key: ACK05Key) -> (modifier: UInt8, usage: UInt8?) {
        switch key {
        case .k1: (0x01, 0x12)
        case .k2: (0x01, 0x11)
        case .k3: (0x00, 0x3E)
        case .k4: (0x02, nil)
        case .k5: (0x01, nil)
        case .k6: (0x04, nil)
        case .k7: (0x01, 0x16)
        case .k8: (0x01, 0x1D)
        case .k9: (0x00, 0x2C)
        case .k10: (0x03, 0x1D)
        }
    }
}

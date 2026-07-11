import Foundation

public struct WaveformPosition: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct OverCUEGroupMapping: Codable, Equatable, Sendable {
    public var keyMap: [String: String]
    public var chordMap: [String: String]
    public var dialMap: [String: String]
    public var dialChordMap: [String: String]
    public var rekordboxMode: RekordboxMappingMode?

    public init(
        keyMap: [String: String] = [:],
        chordMap: [String: String] = [:],
        dialMap: [String: String] = [:],
        dialChordMap: [String: String] = [:],
        rekordboxMode: RekordboxMappingMode? = nil
    ) {
        self.keyMap = keyMap
        self.chordMap = chordMap
        self.dialMap = dialMap
        self.dialChordMap = dialChordMap
        self.rekordboxMode = rekordboxMode
    }

    private enum CodingKeys: String, CodingKey {
        case keyMap, chordMap, dialMap, dialChordMap, rekordboxMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyMap = try container.decodeIfPresent([String: String].self, forKey: .keyMap) ?? [:]
        chordMap = try container.decodeIfPresent([String: String].self, forKey: .chordMap) ?? [:]
        dialMap = try container.decodeIfPresent([String: String].self, forKey: .dialMap) ?? [:]
        dialChordMap = try container.decodeIfPresent([String: String].self, forKey: .dialChordMap) ?? [:]
        rekordboxMode = try container.decodeIfPresent(RekordboxMappingMode.self, forKey: .rekordboxMode)
    }
}

public struct OverCUEProfile: Codable, Equatable, Sendable {
    public var waveformPosition: WaveformPosition?
    public var groupMappings: [String: OverCUEGroupMapping]

    public init(
        waveformPosition: WaveformPosition? = nil,
        keyMap: [String: String],
        chordMap: [String: String],
        dialMap: [String: String] = [:],
        dialChordMap: [String: String] = [:],
        rekordboxMode: RekordboxMappingMode? = nil
    ) {
        self.waveformPosition = waveformPosition
        groupMappings = [
            "1": OverCUEGroupMapping(
                keyMap: keyMap,
                chordMap: chordMap,
                dialMap: dialMap,
                dialChordMap: dialChordMap,
                rekordboxMode: rekordboxMode
            ),
        ]
    }

    public init(
        waveformPosition: WaveformPosition? = nil,
        groupMappings: [String: OverCUEGroupMapping]
    ) {
        self.waveformPosition = waveformPosition
        self.groupMappings = groupMappings
    }

    public func mapping(for group: Int) -> OverCUEGroupMapping {
        var result = storedMapping(for: group)
        guard group != 1, let global = groupMappings["1"] else { return result }
        for (input, action) in global.keyMap where Self.isGroupCycle(action) {
            result.keyMap[input] = action
        }
        for (input, action) in global.chordMap where Self.isGroupCycle(action) {
            result.chordMap[input] = action
        }
        for (input, action) in global.dialMap where Self.isGroupCycle(action) {
            result.dialMap[input] = action
        }
        for (input, action) in global.dialChordMap where Self.isGroupCycle(action) {
            result.dialChordMap[input] = action
        }
        return result
    }

    private static func isGroupCycle(_ rawAction: String) -> Bool {
        ActionID(rawValue: rawAction)?.isGroupCycle == true
    }

    public func storedMapping(for group: Int) -> OverCUEGroupMapping {
        groupMappings[String(group)] ?? OverCUEGroupMapping()
    }

    public mutating func setMapping(_ mapping: OverCUEGroupMapping, for group: Int) {
        groupMappings[String(group)] = mapping
    }

    public var keyMap: [String: String] {
        get { mapping(for: 1).keyMap }
        set {
            var mapping = mapping(for: 1)
            mapping.keyMap = newValue
            setMapping(mapping, for: 1)
        }
    }

    public var chordMap: [String: String] {
        get { mapping(for: 1).chordMap }
        set {
            var mapping = mapping(for: 1)
            mapping.chordMap = newValue
            setMapping(mapping, for: 1)
        }
    }

    public var dialMap: [String: String] {
        get { mapping(for: 1).dialMap }
        set {
            var mapping = mapping(for: 1)
            mapping.dialMap = newValue
            setMapping(mapping, for: 1)
        }
    }

    public var dialChordMap: [String: String] {
        get { mapping(for: 1).dialChordMap }
        set {
            var mapping = mapping(for: 1)
            mapping.dialChordMap = newValue
            setMapping(mapping, for: 1)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case waveformPosition
        case groupMappings
        case keyMap
        case chordMap
        case dialMap
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        waveformPosition = try container.decodeIfPresent(WaveformPosition.self, forKey: .waveformPosition)
        if let groups = try container.decodeIfPresent(
            [String: OverCUEGroupMapping].self,
            forKey: .groupMappings
        ) {
            groupMappings = groups
        } else {
            groupMappings = [
                "1": OverCUEGroupMapping(
                    keyMap: try container.decodeIfPresent([String: String].self, forKey: .keyMap) ?? [:],
                    chordMap: try container.decodeIfPresent([String: String].self, forKey: .chordMap) ?? [:],
                    dialMap: try container.decodeIfPresent([String: String].self, forKey: .dialMap) ?? [:]
                ),
            ]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(waveformPosition, forKey: .waveformPosition)
        try container.encode(groupMappings, forKey: .groupMappings)
    }

    public static let defaultValue: OverCUEProfile = {
        guard let url = Bundle.module.url(
            forResource: "DefaultKeyMapping",
            withExtension: "json"
        ) else {
            fatalError("DefaultKeyMapping.json is missing from OverCUECore resources.")
        }
        do {
            let resource = try JSONDecoder().decode(
                DefaultKeyMappingResource.self,
                from: Data(contentsOf: url)
            )
            return OverCUEProfile(groupMappings: resource.groupMappings)
        } catch {
            fatalError("DefaultKeyMapping.json is invalid: \(error)")
        }
    }()
}

private struct DefaultKeyMappingResource: Decodable {
    let groupMappings: [String: OverCUEGroupMapping]
}

public struct OverCUEConfiguration: Codable, Equatable, Sendable {
    public static let currentVersion = 6

    public var version: Int
    public var defaultProfile: String
    public var profiles: [String: OverCUEProfile]
    public var deviceProfiles: [String: String]

    public init(
        version: Int = currentVersion,
        defaultProfile: String = "default",
        profiles: [String: OverCUEProfile],
        deviceProfiles: [String: String] = [:]
    ) {
        self.version = version
        self.defaultProfile = defaultProfile
        self.profiles = profiles
        self.deviceProfiles = deviceProfiles
    }

    public static let defaultValue = OverCUEConfiguration(
        profiles: ["default": .defaultValue]
    )
}

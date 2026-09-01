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
    public var waveformPosition: WaveformPosition?
    public var keyMap: [String: String]
    public var chordMap: [String: String]
    public var dialMap: [String: String]
    public var dialChordMap: [String: String]
    public var rekordboxMode: RekordboxMappingMode?
    // Decode-only migration state for version 9 and earlier. Version 10+
    // configurations never encode a group-global Deck.
    public var legacyRekordboxDeck: RekordboxDeck?

    public init(
        waveformPosition: WaveformPosition? = nil,
        keyMap: [String: String] = [:],
        chordMap: [String: String] = [:],
        dialMap: [String: String] = [:],
        dialChordMap: [String: String] = [:],
        rekordboxMode: RekordboxMappingMode? = nil,
        legacyRekordboxDeck: RekordboxDeck? = nil
    ) {
        self.waveformPosition = waveformPosition
        self.keyMap = keyMap
        self.chordMap = chordMap
        self.dialMap = dialMap
        self.dialChordMap = dialChordMap
        self.rekordboxMode = rekordboxMode
        self.legacyRekordboxDeck = legacyRekordboxDeck
    }

    private enum CodingKeys: String, CodingKey {
        case waveformPosition, keyMap, chordMap, dialMap, dialChordMap, rekordboxMode, rekordboxDeck
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        waveformPosition = try container.decodeIfPresent(WaveformPosition.self, forKey: .waveformPosition)
        keyMap = try container.decodeIfPresent([String: String].self, forKey: .keyMap) ?? [:]
        chordMap = try container.decodeIfPresent([String: String].self, forKey: .chordMap) ?? [:]
        dialMap = try container.decodeIfPresent([String: String].self, forKey: .dialMap) ?? [:]
        dialChordMap = try container.decodeIfPresent([String: String].self, forKey: .dialChordMap) ?? [:]
        rekordboxMode = try container.decodeIfPresent(RekordboxMappingMode.self, forKey: .rekordboxMode)
        legacyRekordboxDeck = try container.decodeIfPresent(
            RekordboxDeck.self,
            forKey: .rekordboxDeck
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(waveformPosition, forKey: .waveformPosition)
        try container.encode(keyMap, forKey: .keyMap)
        try container.encode(chordMap, forKey: .chordMap)
        try container.encode(dialMap, forKey: .dialMap)
        try container.encode(dialChordMap, forKey: .dialChordMap)
        try container.encodeIfPresent(rekordboxMode, forKey: .rekordboxMode)
    }
}

// Historical source/API name retained for config/code compatibility. In the UI
// this object is simply called a Preset.
public struct OverCUEPresetGroup: Codable, Equatable, Identifiable, Sendable {
    public static let maximumCount = 24

    public var id: String
    public var name: String
    public var order: Int
    public var mapping: OverCUEGroupMapping

    public init(id: String, name: String, order: Int, mapping: OverCUEGroupMapping) {
        self.id = id
        self.name = name
        self.order = order
        self.mapping = mapping
    }

    public static func migratedID(forLegacyGroup group: Int) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "overcue-v9-group-\(group)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "pg-%016llx", hash)
    }
}

/// A Group Preset is the parent assignment for a multi-controller setup.
/// A Logical Device is included when its ID exists in `devicePresetAssignments`;
/// the value is the stable Preset ID that device starts from.
public struct OverCUEGroupPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var order: Int
    public var devicePresetAssignments: [String: String]

    public init(
        id: String,
        name: String,
        order: Int,
        devicePresetAssignments: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.devicePresetAssignments = devicePresetAssignments
    }
}

public enum OverCUEPresetGroupNavigator {
    public static func nextID(
        currentID: String?,
        step: Int,
        in profile: OverCUEProfile
    ) -> String? {
        let groups = profile.orderedPresetGroups
        guard !groups.isEmpty else { return nil }
        guard let currentIndex = currentID.flatMap({ id in groups.firstIndex { $0.id == id } })
        else {
            return step < 0 ? groups.last?.id : groups.first?.id
        }
        let offset = ((currentIndex + step) % groups.count + groups.count) % groups.count
        return groups[offset].id
    }
}

public struct OverCUEProfile: Codable, Equatable, Sendable {
    // Kept only so version 1–6 files can migrate their profile-wide position
    // into every Preset. Version 7+ configurations leave this value nil.
    public var waveformPosition: WaveformPosition?
    public var presetGroups: [OverCUEPresetGroup]

    public init(
        waveformPosition: WaveformPosition? = nil,
        keyMap: [String: String],
        chordMap: [String: String],
        dialMap: [String: String] = [:],
        dialChordMap: [String: String] = [:],
        rekordboxMode: RekordboxMappingMode? = nil
    ) {
        self.waveformPosition = waveformPosition
        presetGroups = [
            OverCUEPresetGroup(
                id: OverCUEPresetGroup.migratedID(forLegacyGroup: 1),
                name: "Group 1",
                order: 1,
                mapping: OverCUEGroupMapping(
                    keyMap: keyMap,
                    chordMap: chordMap,
                    dialMap: dialMap,
                    dialChordMap: dialChordMap,
                    rekordboxMode: rekordboxMode
                )
            ),
        ]
    }

    public init(
        waveformPosition: WaveformPosition? = nil,
        groupMappings: [String: OverCUEGroupMapping]
    ) {
        self.waveformPosition = waveformPosition
        presetGroups = Self.presets(from: groupMappings)
    }

    public init(
        waveformPosition: WaveformPosition? = nil,
        presetGroups: [OverCUEPresetGroup]
    ) {
        self.waveformPosition = waveformPosition
        self.presetGroups = presetGroups
    }

    public var orderedPresetGroups: [OverCUEPresetGroup] {
        presetGroups.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id < $1.id
        }
    }

    public var groupMappings: [String: OverCUEGroupMapping] {
        get {
            Dictionary(uniqueKeysWithValues: orderedPresetGroups.enumerated().map {
                (String($0.offset + 1), $0.element.mapping)
            })
        }
        set { presetGroups = Self.presets(from: newValue) }
    }

    public func presetGroup(id: String) -> OverCUEPresetGroup? {
        presetGroups.first { $0.id == id }
    }

    public func mapping(forPresetID id: String) -> OverCUEGroupMapping {
        guard let index = orderedPresetGroups.firstIndex(where: { $0.id == id }) else {
            return OverCUEGroupMapping()
        }
        return mapping(for: index + 1)
    }

    public mutating func setMapping(_ mapping: OverCUEGroupMapping, forPresetID id: String) {
        guard let index = presetGroups.firstIndex(where: { $0.id == id }) else { return }
        presetGroups[index].mapping = mapping
    }

    public func mapping(for group: Int) -> OverCUEGroupMapping {
        var result = storedMapping(for: group)
        guard group != 1, let global = orderedPresetGroups.first?.mapping else { return result }
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
        let groups = orderedPresetGroups
        guard groups.indices.contains(group - 1) else { return OverCUEGroupMapping() }
        return groups[group - 1].mapping
    }

    public mutating func setMapping(_ mapping: OverCUEGroupMapping, for group: Int) {
        let groups = orderedPresetGroups
        if groups.indices.contains(group - 1),
           let index = presetGroups.firstIndex(where: { $0.id == groups[group - 1].id }) {
            presetGroups[index].mapping = mapping
        } else if group > 0, group <= OverCUEPresetGroup.maximumCount {
            presetGroups.append(
                OverCUEPresetGroup(
                    id: OverCUEPresetGroup.migratedID(forLegacyGroup: group),
                    name: "Group \(group)",
                    order: group,
                    mapping: mapping
                )
            )
        }
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
        case presetGroups
        case groupMappings
        case keyMap
        case chordMap
        case dialMap
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        waveformPosition = try container.decodeIfPresent(WaveformPosition.self, forKey: .waveformPosition)
        if let presets = try container.decodeIfPresent(
            [OverCUEPresetGroup].self,
            forKey: .presetGroups
        ) {
            guard !presets.isEmpty,
                  presets.count <= OverCUEPresetGroup.maximumCount,
                  Set(presets.map(\.id)).count == presets.count,
                  Set(presets.map(\.order)).count == presets.count,
                  presets.allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .presetGroups,
                    in: container,
                    debugDescription: "Presets must have 1...24 unique stable IDs."
                )
            }
            presetGroups = presets
        } else if let groups = try container.decodeIfPresent(
            [String: OverCUEGroupMapping].self,
            forKey: .groupMappings
        ) {
            presetGroups = Self.presets(from: groups)
        } else {
            presetGroups = [
                OverCUEPresetGroup(
                    id: OverCUEPresetGroup.migratedID(forLegacyGroup: 1),
                    name: "Group 1",
                    order: 1,
                    mapping: OverCUEGroupMapping(
                        keyMap: try container.decodeIfPresent([String: String].self, forKey: .keyMap) ?? [:],
                        chordMap: try container.decodeIfPresent([String: String].self, forKey: .chordMap) ?? [:],
                        dialMap: try container.decodeIfPresent([String: String].self, forKey: .dialMap) ?? [:]
                    )
                ),
            ]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(waveformPosition, forKey: .waveformPosition)
        try container.encode(orderedPresetGroups, forKey: .presetGroups)
    }

    private static func presets(
        from mappings: [String: OverCUEGroupMapping]
    ) -> [OverCUEPresetGroup] {
        mappings.compactMap { key, mapping -> (Int, OverCUEGroupMapping)? in
            guard let order = Int(key), order > 0 else { return nil }
            return (order, mapping)
        }
        .sorted { $0.0 < $1.0 }
        .prefix(OverCUEPresetGroup.maximumCount)
        .map { order, mapping in
            OverCUEPresetGroup(
                id: OverCUEPresetGroup.migratedID(forLegacyGroup: order),
                name: "Group \(order)",
                order: order,
                mapping: mapping
            )
        }
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
            if let presetGroups = resource.presetGroups {
                return OverCUEProfile(presetGroups: presetGroups)
            }
            var profile = OverCUEProfile(groupMappings: resource.groupMappings ?? [:])
            for group in profile.presetGroups.indices.map({ $0 + 1 }) {
                var mapping = profile.storedMapping(for: group)
                let deck = mapping.legacyRekordboxDeck ?? .deck1
                mapping.keyMap = Self.scopedMappings(mapping.keyMap, deck: deck)
                mapping.chordMap = Self.scopedMappings(mapping.chordMap, deck: deck)
                mapping.dialMap = Self.scopedMappings(mapping.dialMap, deck: deck)
                mapping.dialChordMap = Self.scopedMappings(mapping.dialChordMap, deck: deck)
                mapping.legacyRekordboxDeck = nil
                profile.setMapping(mapping, for: group)
            }
            return profile
        } catch {
            fatalError("DefaultKeyMapping.json is invalid: \(error)")
        }
    }()

    private static func scopedMappings(
        _ mappings: [String: String],
        deck: RekordboxDeck
    ) -> [String: String] {
        mappings.mapValues { rawValue in
            guard let action = ActionID(rawValue: rawValue),
                  !action.behavior.isInternal
            else { return rawValue }
            return RekordboxActionAdapter.scopedTarget(for: action, deck: deck).configurationValue
        }
    }
}

private struct DefaultKeyMappingResource: Decodable {
    let presetGroups: [OverCUEPresetGroup]?
    let groupMappings: [String: OverCUEGroupMapping]?
}

public struct OverCUEConfiguration: Codable, Equatable, Sendable {
    public static let currentVersion = 10

    public var version: Int
    public var defaultProfile: String
    public var profiles: [String: OverCUEProfile]
    // Retained for decoding and migrating version 2-8 configurations. New
    // assignments use logicalDevices + physicalDeviceBindings.
    public var deviceProfiles: [String: String]
    public var logicalDevices: [String: OverCUELogicalDevice]
    public var physicalDeviceBindings: [OverCUEPhysicalDeviceBinding]
    public var groupPresets: [OverCUEGroupPreset]
    public var activeGroupPresetID: String?

    public init(
        version: Int = currentVersion,
        defaultProfile: String = "default",
        profiles: [String: OverCUEProfile],
        deviceProfiles: [String: String] = [:],
        logicalDevices: [String: OverCUELogicalDevice] = [:],
        physicalDeviceBindings: [OverCUEPhysicalDeviceBinding] = [],
        groupPresets: [OverCUEGroupPreset] = [],
        activeGroupPresetID: String? = nil
    ) {
        self.version = version
        self.defaultProfile = defaultProfile
        self.profiles = profiles
        self.deviceProfiles = deviceProfiles
        self.logicalDevices = logicalDevices
        self.physicalDeviceBindings = physicalDeviceBindings
        self.groupPresets = groupPresets
        self.activeGroupPresetID = activeGroupPresetID
    }

    private enum CodingKeys: String, CodingKey {
        case version, defaultProfile, profiles, deviceProfiles, logicalDevices, physicalDeviceBindings
        case groupPresets, activeGroupPresetID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        defaultProfile = try container.decodeIfPresent(String.self, forKey: .defaultProfile) ?? "default"
        profiles = try container.decode([String: OverCUEProfile].self, forKey: .profiles)
        deviceProfiles = try container.decodeIfPresent([String: String].self, forKey: .deviceProfiles) ?? [:]
        logicalDevices = try container.decodeIfPresent(
            [String: OverCUELogicalDevice].self,
            forKey: .logicalDevices
        ) ?? [:]
        physicalDeviceBindings = try container.decodeIfPresent(
            [OverCUEPhysicalDeviceBinding].self,
            forKey: .physicalDeviceBindings
        ) ?? []
        groupPresets = try container.decodeIfPresent(
            [OverCUEGroupPreset].self,
            forKey: .groupPresets
        ) ?? []
        activeGroupPresetID = try container.decodeIfPresent(String.self, forKey: .activeGroupPresetID)

        guard version >= 10 else { return }
        for profileName in profiles.keys {
            guard var profile = profiles[profileName] else { continue }
            for index in profile.presetGroups.indices {
                profile.presetGroups[index].name = Self.currentPresetDisplayName(
                    profile.presetGroups[index].name
                )
            }
            profiles[profileName] = profile
        }
        if groupPresets.isEmpty {
            let assignments = Dictionary(uniqueKeysWithValues:
                logicalDevices.compactMap { logicalDeviceID, logicalDevice in
                    guard let presetID = profiles[logicalDevice.profileName]?
                        .orderedPresetGroups.first?.id
                    else { return nil }
                    return (logicalDeviceID, presetID)
                }
            )
            groupPresets = [
                OverCUEGroupPreset(
                    id: "group-preset-default",
                    name: "Default",
                    order: 1,
                    devicePresetAssignments: assignments
                ),
            ]
            activeGroupPresetID = "group-preset-default"
        } else if activeGroupPresetID == nil
                    || !groupPresets.contains(where: { $0.id == activeGroupPresetID }) {
            activeGroupPresetID = orderedGroupPresets.first?.id
        }
    }

    public var orderedGroupPresets: [OverCUEGroupPreset] {
        groupPresets.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id < $1.id
        }
    }

    public var activeGroupPreset: OverCUEGroupPreset? {
        guard let activeGroupPresetID else { return nil }
        return groupPresets.first { $0.id == activeGroupPresetID }
    }

    public func assignedPresetID(for logicalDeviceID: String) -> String? {
        guard let presetID = activeGroupPreset?.devicePresetAssignments[logicalDeviceID],
              let logicalDevice = logicalDevices[logicalDeviceID],
              let profile = profiles[logicalDevice.profileName],
              profile.presetGroup(id: presetID) != nil
        else { return nil }
        return presetID
    }

    public func logicalDeviceID(for device: HIDPhysicalDeviceDescriptor) -> String? {
        guard case let .bound(logicalDeviceID) = bindingResolution(
            for: device,
            among: [device]
        ) else { return nil }
        return logicalDeviceID
    }

    public func bindingResolution(
        for device: HIDPhysicalDeviceDescriptor,
        among connectedDevices: [HIDPhysicalDeviceDescriptor]
    ) -> PhysicalDeviceBindingResolution {
        let matchingBindings = physicalDeviceBindings.filter { $0.matches(device) }
        let logicalDeviceIDs = Array(Set(matchingBindings.map(\.logicalDeviceID))).sorted()
        guard !logicalDeviceIDs.isEmpty else { return .unbound }

        if let persistentIdentifier = device.persistentIdentifier {
            let matchingSessions = Set(connectedDevices.compactMap { candidate -> String? in
                candidate.persistentIdentifier == persistentIdentifier
                    ? candidate.sessionIdentifier
                    : nil
            })
            if matchingSessions.count > 1 {
                return .ambiguous(logicalDeviceIDs: logicalDeviceIDs)
            }
        }
        guard logicalDeviceIDs.count == 1, let logicalDeviceID = logicalDeviceIDs.first else {
            return .ambiguous(logicalDeviceIDs: logicalDeviceIDs)
        }
        return .bound(logicalDeviceID: logicalDeviceID)
    }

    public func profileName(for device: HIDPhysicalDeviceDescriptor) -> String {
        guard let logicalDeviceID = logicalDeviceID(for: device),
              let logicalDevice = logicalDevices[logicalDeviceID],
              profiles[logicalDevice.profileName] != nil
        else { return defaultProfile }
        return logicalDevice.profileName
    }

    public func profileName(
        for device: HIDPhysicalDeviceDescriptor,
        among connectedDevices: [HIDPhysicalDeviceDescriptor]
    ) -> String {
        guard case let .bound(logicalDeviceID) = bindingResolution(
            for: device,
            among: connectedDevices
        ),
              let logicalDevice = logicalDevices[logicalDeviceID],
              profiles[logicalDevice.profileName] != nil
        else { return defaultProfile }
        return logicalDevice.profileName
    }

    private static func currentPresetDisplayName(_ name: String) -> String {
        guard name.hasPrefix("Group "),
              Int(name.dropFirst("Group ".count)) != nil
        else { return name }
        return "Preset \(name.dropFirst("Group ".count))"
    }

    public static let defaultValue = OverCUEConfiguration(
        profiles: ["default": .defaultValue],
        groupPresets: [
            OverCUEGroupPreset(
                id: "group-preset-default",
                name: "Default",
                order: 1
            ),
        ],
        activeGroupPresetID: "group-preset-default"
    )
}

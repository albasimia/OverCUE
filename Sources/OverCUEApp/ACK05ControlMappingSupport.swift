import Foundation
import OverCUECore

enum ACK05ControlInput: Hashable, Sendable {
    case key(String)
    case chord(String)
    case dial(String)
    case dialChord(String)

    var label: String {
        switch self {
        case let .key(value):
            return value.uppercased()
        case let .chord(value):
            return value.uppercased().replacingOccurrences(of: "+", with: " + ")
        case let .dial(value):
            return value.lowercased() == DialDirection.clockwise.rawValue ? "DIAL →" : "DIAL ←"
        case let .dialChord(value):
            return value.uppercased()
                .replacingOccurrences(of: "DIAL_RIGHT", with: "DIAL →")
                .replacingOccurrences(of: "DIAL_LEFT", with: "DIAL ←")
                .replacingOccurrences(of: "+", with: " + ")
        }
    }
}

struct ACK05ControlState: Sendable {
    let logicalDeviceID: String
    let deviceName: String
    let mapping: OverCUEControlMapping

    func inputs(for target: ActionTarget) -> Set<ACK05ControlInput> {
        Self.inputs(for: target, in: mapping)
    }

    func target(for key: ACK05Key) -> ActionTarget? {
        mapping.keyMap[key.rawValue.uppercased()].flatMap(ActionTarget.init(configurationValue:))
    }

    func target(for direction: DialDirection) -> ActionTarget? {
        mapping.dialMap[direction.rawValue].flatMap(ActionTarget.init(configurationValue:))
    }

    static func inputs(
        for target: ActionTarget,
        in mapping: OverCUEControlMapping
    ) -> Set<ACK05ControlInput> {
        let value = target.configurationValue
        var result: Set<ACK05ControlInput> = []
        for (input, assigned) in mapping.keyMap where assigned == value {
            result.insert(.key(input))
        }
        for (input, assigned) in mapping.chordMap where assigned == value {
            result.insert(.chord(input))
        }
        for (input, assigned) in mapping.dialMap where assigned == value {
            result.insert(.dial(input))
        }
        for (input, assigned) in mapping.dialChordMap where assigned == value {
            result.insert(.dialChord(input))
        }
        return result
    }
}

enum ACK05ControlMappingSupport {
    static func state(
        runtimeLogicalDeviceID: String?,
        at configurationURL: URL = OverCUEAppConfigurationLocation.url
    ) throws -> ACK05ControlState? {
        let configuration = try OverCUEConfigurationFileStore.readCurrent(at: configurationURL)
        guard let logicalDeviceID = resolveLogicalDeviceID(
            runtimeLogicalDeviceID: runtimeLogicalDeviceID,
            configuration: configuration
        ),
              let logicalDevice = configuration.logicalDevices[logicalDeviceID]
        else { return nil }
        return ACK05ControlState(
            logicalDeviceID: logicalDeviceID,
            deviceName: logicalDevice.name,
            mapping: logicalDevice.controlMapping
        )
    }

    static func presetInputs(
        target: ActionTarget,
        presetID: String?,
        at configurationURL: URL = OverCUEAppConfigurationLocation.url
    ) throws -> Set<ACK05ControlInput> {
        let configuration = try OverCUEConfigurationFileStore.readCurrent(at: configurationURL)
        guard let profile = configuration.profiles[configuration.defaultProfile] else { return [] }
        if target.behavior.isInternal {
            return Set(profile.orderedPresetGroups.flatMap { inputs(target: target, mapping: $0.mapping) })
        }
        guard let presetID,
              let preset = profile.presetGroup(id: presetID)
        else { return [] }
        return Set(inputs(target: target, mapping: preset.mapping))
    }

    static func finalizeLearn(
        logicalDeviceID: String,
        target: ActionTarget,
        presetID: String?,
        beforeInputs: Set<ACK05ControlInput>,
        at configurationURL: URL = OverCUEAppConfigurationLocation.url
    ) async throws -> Bool {
        let changed = try await OverCUEPersistenceWorker.run {
            var didChange = false
            _ = try OverCUEConfigurationFileStore.updateCurrent(
                at: configurationURL,
                fallback: .defaultValue
            ) { latest in
                guard var logicalDevice = latest.logicalDevices[logicalDeviceID],
                      var profile = latest.profiles[latest.defaultProfile]
                else { return }

                let afterInputs: Set<ACK05ControlInput>
                if target.behavior.isInternal {
                    afterInputs = Set(profile.orderedPresetGroups.flatMap {
                        inputs(target: target, mapping: $0.mapping)
                    })
                } else if let presetID,
                          let preset = profile.presetGroup(id: presetID) {
                    afterInputs = Set(inputs(target: target, mapping: preset.mapping))
                } else {
                    afterInputs = []
                }

                // Generic HID may win the unified Learn session. If ACK05 did
                // not alter its mapping, leave the device Control state alone.
                guard afterInputs != beforeInputs else { return }

                if target.behavior.isInternal {
                    var control = logicalDevice.controlMapping
                    removeTarget(target, from: &control)
                    for input in afterInputs {
                        remove(input, from: &control)
                        remove(input, fromAllPresetsIn: &profile)
                        assign(input, to: target, in: &control)
                    }
                    logicalDevice.controlMapping = control
                    latest.logicalDevices[logicalDeviceID] = logicalDevice
                    profile.removeInternalControlMappings()
                    latest.profiles[latest.defaultProfile] = profile
                    didChange = true
                } else {
                    var control = logicalDevice.controlMapping
                    for input in afterInputs {
                        remove(input, from: &control)
                    }
                    if control != logicalDevice.controlMapping {
                        logicalDevice.controlMapping = control
                        latest.logicalDevices[logicalDeviceID] = logicalDevice
                        didChange = true
                    }
                }
            }
            return didChange
        }
        if changed { OverCUEConfigurationChangedNotification.post() }
        return changed
    }

    static func removeControlTarget(
        logicalDeviceID: String,
        target: ActionTarget,
        at configurationURL: URL = OverCUEAppConfigurationLocation.url
    ) async throws {
        let changed = try await OverCUEPersistenceWorker.run {
            var changed = false
            _ = try OverCUEConfigurationFileStore.updateCurrent(
                at: configurationURL,
                fallback: .defaultValue
            ) { latest in
                guard var logicalDevice = latest.logicalDevices[logicalDeviceID] else { return }
                var control = logicalDevice.controlMapping
                removeTarget(target, from: &control)
                guard control != logicalDevice.controlMapping else { return }
                logicalDevice.controlMapping = control
                latest.logicalDevices[logicalDeviceID] = logicalDevice
                changed = true
            }
            return changed
        }
        if changed { OverCUEConfigurationChangedNotification.post() }
    }

    private static func resolveLogicalDeviceID(
        runtimeLogicalDeviceID: String?,
        configuration: OverCUEConfiguration
    ) -> String? {
        if let runtimeLogicalDeviceID,
           configuration.logicalDevices[runtimeLogicalDeviceID] != nil,
           configuration.physicalDeviceBindings.contains(where: {
               $0.logicalDeviceID == runtimeLogicalDeviceID && $0.kind == .ack05
           }) {
            return runtimeLogicalDeviceID
        }
        let candidates = Set(configuration.physicalDeviceBindings.compactMap { binding in
            binding.kind == .ack05 ? binding.logicalDeviceID : nil
        })
        return candidates.count == 1 ? candidates.first : nil
    }

    private static func inputs(
        target: ActionTarget,
        mapping: OverCUEGroupMapping
    ) -> [ACK05ControlInput] {
        let value = target.configurationValue
        var result: [ACK05ControlInput] = []
        result += mapping.keyMap.compactMap { $0.value == value ? .key($0.key) : nil }
        result += mapping.chordMap.compactMap { $0.value == value ? .chord($0.key) : nil }
        result += mapping.dialMap.compactMap { $0.value == value ? .dial($0.key) : nil }
        result += mapping.dialChordMap.compactMap { $0.value == value ? .dialChord($0.key) : nil }
        return result
    }

    private static func removeTarget(_ target: ActionTarget, from mapping: inout OverCUEControlMapping) {
        let value = target.configurationValue
        mapping.keyMap = mapping.keyMap.filter { $0.value != value }
        mapping.chordMap = mapping.chordMap.filter { $0.value != value }
        mapping.dialMap = mapping.dialMap.filter { $0.value != value }
        mapping.dialChordMap = mapping.dialChordMap.filter { $0.value != value }
    }

    private static func remove(_ input: ACK05ControlInput, from mapping: inout OverCUEControlMapping) {
        switch input {
        case let .key(value): mapping.keyMap.removeValue(forKey: value)
        case let .chord(value): mapping.chordMap.removeValue(forKey: value)
        case let .dial(value): mapping.dialMap.removeValue(forKey: value)
        case let .dialChord(value): mapping.dialChordMap.removeValue(forKey: value)
        }
    }

    private static func remove(_ input: ACK05ControlInput, from mapping: inout OverCUEGroupMapping) {
        switch input {
        case let .key(value): mapping.keyMap.removeValue(forKey: value)
        case let .chord(value): mapping.chordMap.removeValue(forKey: value)
        case let .dial(value): mapping.dialMap.removeValue(forKey: value)
        case let .dialChord(value): mapping.dialChordMap.removeValue(forKey: value)
        }
    }

    private static func remove(
        _ input: ACK05ControlInput,
        fromAllPresetsIn profile: inout OverCUEProfile
    ) {
        for index in profile.presetGroups.indices {
            remove(input, from: &profile.presetGroups[index].mapping)
        }
    }

    private static func assign(
        _ input: ACK05ControlInput,
        to target: ActionTarget,
        in mapping: inout OverCUEControlMapping
    ) {
        switch input {
        case let .key(value): mapping.keyMap[value] = target.configurationValue
        case let .chord(value): mapping.chordMap[value] = target.configurationValue
        case let .dial(value): mapping.dialMap[value] = target.configurationValue
        case let .dialChord(value): mapping.dialChordMap[value] = target.configurationValue
        }
    }
}

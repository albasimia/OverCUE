import ApplicationServices
import AppKit
import CoreFoundation
import CoreMIDI
import Darwin
import Foundation
import IOKit.hid
import OverCUECore

private enum ACK05Identity {
    static let vendorID = 0x28BD
    static let productID = 0x0202
}

private enum OutputMode: String {
    case midi
    case mouse
}

private enum RekordboxMode: String {
    case export
    case performance
}

private struct BridgeOptions {
    var outputMode = OutputMode.midi
    var rekordboxMode = RekordboxMode.export
    var deck = 1
    var touchOffMilliseconds = 150
    var sourceName = "OverCUE"
    var seizeDevice = true
    var dragPixels = 1.0
    var maximumDragPixels = 20.0
    var accelerationEnabled = true
    var invertDial = false
    var configPath: String?

    static func parse(_ arguments: [String]) throws -> BridgeOptions {
        var options = BridgeOptions()
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--output":
                let value = try stringValue(after: argument, arguments: arguments, index: &index)
                guard let outputMode = OutputMode(rawValue: value) else {
                    throw BridgeError.invalidValue("--output must be 'midi' or 'mouse'")
                }
                options.outputMode = outputMode
            case "--rekordbox-mode":
                let value = try stringValue(after: argument, arguments: arguments, index: &index)
                guard let mode = RekordboxMode(rawValue: value) else {
                    throw BridgeError.invalidValue("--rekordbox-mode must be 'export' or 'performance'")
                }
                options.rekordboxMode = mode
            case "--deck":
                options.deck = try integerValue(after: argument, arguments: arguments, index: &index)
            case "--touch-off-ms", "--idle-ms":
                options.touchOffMilliseconds = try integerValue(
                    after: argument,
                    arguments: arguments,
                    index: &index
                )
            case "--source-name":
                options.sourceName = try stringValue(after: argument, arguments: arguments, index: &index)
            case "--shared":
                options.seizeDevice = false
            case "--drag-pixels":
                options.dragPixels = try doubleValue(after: argument, arguments: arguments, index: &index)
            case "--max-drag-pixels":
                options.maximumDragPixels = try doubleValue(
                    after: argument,
                    arguments: arguments,
                    index: &index
                )
            case "--no-acceleration":
                options.accelerationEnabled = false
            case "--invert-dial":
                options.invertDial = true
            case "--config":
                options.configPath = try stringValue(after: argument, arguments: arguments, index: &index)
            case "--help", "-h":
                printUsage()
                exit(EXIT_SUCCESS)
            default:
                throw BridgeError.invalidArgument(argument)
            }
            index += 1
        }

        guard (1...4).contains(options.deck) else {
            throw BridgeError.invalidValue("--deck must be between 1 and 4")
        }
        guard (10...5_000).contains(options.touchOffMilliseconds) else {
            throw BridgeError.invalidValue("--touch-off-ms must be between 10 and 5000")
        }
        guard !options.sourceName.isEmpty else {
            throw BridgeError.invalidValue("--source-name cannot be empty")
        }
        guard (0.25...100).contains(options.dragPixels) else {
            throw BridgeError.invalidValue("--drag-pixels must be between 0.25 and 100")
        }
        guard (0.25...100).contains(options.maximumDragPixels) else {
            throw BridgeError.invalidValue("--max-drag-pixels must be between 0.25 and 100")
        }
        guard options.maximumDragPixels >= options.dragPixels else {
            throw BridgeError.invalidValue("--max-drag-pixels must be greater than or equal to --drag-pixels")
        }

        return options
    }

    static func printUsage() {
        print(
            """
            Usage: overcue [options]

            Convert XPPen ACK05 dial input into MIDI or waveform mouse dragging.

            Options:
              --output <midi|mouse>  Output mode. Default: midi.
              --rekordbox-mode <mode> Shortcut mode: export or performance. Default: export.
              --deck <1-4>           Target deck/MIDI channel. Default: 1.
              --touch-off-ms <ms>    JogTouch release delay. Default: 150.
              --idle-ms <ms>         Alias used as mouse drag release delay.
              --source-name <name>   CoreMIDI virtual source name. Default: OverCUE.
              --drag-pixels <px>     Slow mouse movement per detent. Default: 1.
              --max-drag-pixels <px> Fast mouse movement per detent. Default: 20.
              --no-acceleration      Disable rotation-speed acceleration.
              --invert-dial          Reverse the mouse drag direction.
              --config <path>        Settings JSON path. Default: ~/Library/Application Support/OverCUE/config.json.
              --shared               Do not suppress ACK05 factory keyboard input.
              -h, --help             Show this help.

            Exclusive ACK05 access is enabled by default. Press Control-C to stop.
            In mouse mode, use the configured Capture Waveform Position chord to save its position.
            """
        )
    }

    private static func integerValue(
        after option: String,
        arguments: [String],
        index: inout Int
    ) throws -> Int {
        let value = try stringValue(after: option, arguments: arguments, index: &index)
        guard let integer = Int(value) else {
            throw BridgeError.invalidValue("\(option) requires an integer")
        }
        return integer
    }

    private static func doubleValue(
        after option: String,
        arguments: [String],
        index: inout Int
    ) throws -> Double {
        let value = try stringValue(after: option, arguments: arguments, index: &index)
        guard let double = Double(value) else {
            throw BridgeError.invalidValue("\(option) requires a number")
        }
        return double
    }

    private static func stringValue(
        after option: String,
        arguments: [String],
        index: inout Int
    ) throws -> String {
        index += 1
        guard index < arguments.count else {
            throw BridgeError.missingValue(option)
        }
        return arguments[index]
    }
}

private enum BridgeError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case invalidValue(String)
    case missingValue(String)
    case hidOpenFailed(IOReturn)
    case midiOperationFailed(operation: String, status: OSStatus)
    case accessibilityPermissionMissing
    case shortcutConfiguration(String)
    case configuration(String)

    var description: String {
        switch self {
        case let .invalidArgument(argument):
            return "Unknown argument: \(argument)"
        case let .invalidValue(message):
            return message
        case let .missingValue(argument):
            return "Missing value after \(argument)"
        case let .hidOpenFailed(result):
            if result == kIOReturnNotPermitted {
                return "HID access was denied. Grant Input Monitoring permission to this app, then restart it."
            }
            return "Could not open ACK05 HID input (\(formatStatus(result)))."
        case let .midiOperationFailed(operation, status):
            return "CoreMIDI \(operation) failed (\(formatStatus(status)))."
        case .accessibilityPermissionMissing:
            return "Mouse control was denied. Grant Accessibility permission to the terminal "
                + "running OverCUE in System Settings > Privacy & Security, then restart it."
        case let .shortcutConfiguration(message):
            return message
        case let .configuration(message):
            return message
        }
    }
}

private final class ConfigurationStore {
    private struct VersionEnvelope: Decodable {
        let version: Int
    }

    private struct LegacyConfiguration: Decodable {
        let waveformPosition: WaveformPosition?
        let keyMap: [String: String]
        let chordMap: [String: String]
    }

    let url: URL
    private(set) var configuration: OverCUEConfiguration

    init(path: String?) throws {
        if let path {
            url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        } else {
            url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/OverCUE/config.json")
        }

        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let version = try decoder.decode(VersionEnvelope.self, from: data).version
                if version == 1 {
                    let legacy = try decoder.decode(LegacyConfiguration.self, from: data)
                    configuration = OverCUEConfiguration(
                        version: 1,
                        profiles: [
                            "default": OverCUEProfile(
                                waveformPosition: legacy.waveformPosition,
                                keyMap: legacy.keyMap,
                                chordMap: legacy.chordMap
                            )
                        ]
                    )
                    try migrateToVersion3(originalData: data, sourceVersion: version)
                } else if version == 2 {
                    configuration = try decoder.decode(OverCUEConfiguration.self, from: data)
                    try migrateToVersion3(originalData: data, sourceVersion: version)
                } else if version == 3 {
                    configuration = try decoder.decode(OverCUEConfiguration.self, from: data)
                } else {
                    throw BridgeError.configuration("Unsupported config version \(version) at \(url.path).")
                }
            } catch {
                throw BridgeError.configuration("Could not read config at \(url.path): \(error)")
            }
        } else {
            configuration = .defaultValue
            try save()
        }

        guard configuration.version == 3 else {
            throw BridgeError.configuration(
                "Unsupported config version \(configuration.version) at \(url.path)."
            )
        }
        guard configuration.profiles[configuration.defaultProfile] != nil else {
            throw BridgeError.configuration(
                "defaultProfile '\(configuration.defaultProfile)' does not exist in profiles."
            )
        }
        for (deviceID, profileName) in configuration.deviceProfiles
        where configuration.profiles[profileName] == nil {
            throw BridgeError.configuration(
                "Device '\(deviceID)' references unknown profile '\(profileName)'."
            )
        }
    }

    func profileName(for deviceID: String?) -> String {
        guard let deviceID else { return configuration.defaultProfile }
        return configuration.deviceProfiles[deviceID] ?? configuration.defaultProfile
    }

    @discardableResult
    func registerDeviceIfNeeded(_ deviceID: String) throws -> Bool {
        guard deviceID != "unknown", configuration.deviceProfiles[deviceID] == nil else {
            return false
        }
        configuration.deviceProfiles[deviceID] = configuration.defaultProfile
        try save()
        return true
    }

    func profile(named name: String) throws -> OverCUEProfile {
        guard let profile = configuration.profiles[name] else {
            throw BridgeError.configuration("Unknown profile '\(name)'.")
        }
        return profile
    }

    func saveWaveformPosition(_ position: CGPoint, profileName: String) throws {
        guard var profile = configuration.profiles[profileName] else {
            throw BridgeError.configuration("Unknown profile '\(profileName)'.")
        }
        profile.waveformPosition = WaveformPosition(x: position.x, y: position.y)
        configuration.profiles[profileName] = profile
        try save()
    }

    private func save() throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: url, options: .atomic)
        } catch {
            throw BridgeError.configuration("Could not save config at \(url.path): \(error)")
        }
    }

    private func migrateToVersion3(originalData: Data, sourceVersion: Int) throws {
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("config.v\(sourceVersion).backup.json")
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try originalData.write(to: backupURL, options: .atomic)
        }

        let result = ActionConfigurationMigrator.migrateToVersion3(configuration)
        configuration = result.configuration
        for warning in result.warnings {
            log(
                "WARNING Profile '\(warning.profileName)' \(warning.section) \(warning.input): "
                    + "unknown legacy action '\(warning.rawAction)'; disabled."
            )
        }
        try save()
        log("Migrated configuration from version \(sourceVersion) to version 3; backup: \(backupURL.path)")
    }
}

private final class CoreMIDIVirtualSource {
    let name: String

    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()

    init(name: String) throws {
        self.name = name

        var status = MIDIClientCreateWithBlock("OverCUE Client" as CFString, &client) { _ in }
        guard status == noErr else {
            throw BridgeError.midiOperationFailed(operation: "client creation", status: status)
        }

        status = MIDISourceCreate(client, name as CFString, &source)
        guard status == noErr else {
            MIDIClientDispose(client)
            throw BridgeError.midiOperationFailed(operation: "virtual source creation", status: status)
        }
    }

    deinit {
        if source != 0 {
            MIDIEndpointDispose(source)
        }
        if client != 0 {
            MIDIClientDispose(client)
        }
    }

    func send(_ message: MIDIMessage) throws {
        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)
        let bytes = message.bytes

        _ = bytes.withUnsafeBufferPointer { buffer in
            MIDIPacketListAdd(
                &packetList,
                MemoryLayout<MIDIPacketList>.size,
                packet,
                0,
                buffer.count,
                buffer.baseAddress!
            )
        }

        let status = MIDIReceived(source, &packetList)
        guard status == noErr else {
            throw BridgeError.midiOperationFailed(operation: "send", status: status)
        }
    }
}

private func defaultAction(for key: ACK05Key) -> ActionID {
    switch key {
    case .k1: .hotCue3
    case .k2: .deleteMemoryCue
    case .k3: .jumpForward
    case .k4: .hotCue2
    case .k5: .setMemoryCue
    case .k6: .jumpBackward
    case .k7: .quantize
    case .k8: .hotCue1
    case .k9: .cue
    case .k10: .playPause
    }
}

private extension ActionMapping {
    init(profile: OverCUEProfile) throws {
        let knownKeys = Dictionary(uniqueKeysWithValues: ACK05Key.allCases.map {
            ($0.rawValue.uppercased(), $0)
        })
        var resolvedKeys = Dictionary(uniqueKeysWithValues: ACK05Key.allCases.map {
            ($0, defaultAction(for: $0))
        })

        for (rawKey, rawAction) in profile.keyMap {
            guard let key = knownKeys[rawKey.uppercased()] else {
                throw BridgeError.configuration("Unknown key '\(rawKey)' in keyMap.")
            }
            guard let action = ActionID(rawValue: rawAction) else {
                throw BridgeError.configuration("Unknown action '\(rawAction)' for \(rawKey).")
            }
            resolvedKeys[key] = action
        }

        var resolvedChords: [KeyChord: ActionID] = [:]
        for (rawChord, rawAction) in profile.chordMap {
            let components = rawChord.uppercased()
                .replacingOccurrences(of: " ", with: "")
                .split(separator: "+", omittingEmptySubsequences: false)
                .map(String.init)
            guard components.count == 2,
                  let modifier = knownKeys[components[0]],
                  let trigger = knownKeys[components[1]],
                  modifier != trigger
            else {
                throw BridgeError.configuration(
                    "Chord '\(rawChord)' must contain two different keys, for example K5+K1."
                )
            }
            let chord = KeyChord(modifier: modifier, trigger: trigger)
            guard resolvedChords[chord] == nil else {
                throw BridgeError.configuration("Duplicate chord '\(chord.label)' in chordMap.")
            }
            guard let action = ActionID(rawValue: rawAction) else {
                throw BridgeError.configuration("Unknown action '\(rawAction)' for \(rawChord).")
            }
            resolvedChords[chord] = action
        }

        self.init(keys: resolvedKeys, chords: resolvedChords)
    }
}

private struct KeyboardShortcut {
    let rawValue: String
    let keyCode: CGKeyCode
    let flags: CGEventFlags

    init(rawValue: String) throws {
        self.rawValue = rawValue
        let components = rawValue.lowercased().components(separatedBy: " + ")
        guard let keyName = components.last,
              let keyCode = Self.keyCodes[keyName]
        else {
            throw BridgeError.shortcutConfiguration("Unsupported rekordbox shortcut: \(rawValue)")
        }
        self.keyCode = keyCode

        var flags: CGEventFlags = []
        for modifier in components.dropLast() {
            switch modifier {
            case "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "option": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default:
                throw BridgeError.shortcutConfiguration("Unsupported shortcut modifier: \(modifier)")
            }
        }
        self.flags = flags
    }

    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5,
        "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
        "k": 40, "n": 45, "m": 46,
        "spacebar": 49,
        "cursor left": 123,
        "cursor right": 124,
        "cursor down": 125,
        "cursor up": 126,
    ]
}

private struct ResolvedKeyboardCommand {
    let displayName: String
    let shortcut: KeyboardShortcut
}

private struct RekordboxAdapter {
    private let baseURL: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        baseURL = homeDirectory
            .appendingPathComponent("Library/Application Support/Pioneer/rekordbox6")
    }

    func load(mode: RekordboxMode) throws -> (name: String, actions: [ActionID: ResolvedKeyboardCommand]) {
        let mappingID: String
        switch mode {
        case .export:
            mappingID = "0000000000030"
        case .performance:
            let settingsData = try Data(contentsOf: baseURL.appendingPathComponent("rekordbox3.settings"))
            let settings = try RekordboxSettings.parse(data: settingsData)
            guard let selectedID = settings.performanceKeyMappingID else {
                throw BridgeError.shortcutConfiguration("Could not find the selected Performance key mapping.")
            }
            mappingID = selectedID
        }

        let mappingURL = baseURL
            .appendingPathComponent("KeyMappings")
            .appendingPathComponent("rekordbox_\(mappingID).mappings")
        let mapping = try RekordboxKeyMapping.parse(data: Data(contentsOf: mappingURL))
        var actions: [ActionID: ResolvedKeyboardCommand] = [:]

        for action in ActionID.allCases {
            guard let commandID = RekordboxActionAdapter.commandID(for: action),
                  let rawShortcut = mapping.shortcut(for: commandID)
            else {
                continue
            }
            actions[action] = ResolvedKeyboardCommand(
                displayName: action.displayName,
                shortcut: try KeyboardShortcut(rawValue: rawShortcut)
            )
        }
        return (mapping.name, actions)
    }

}

private final class RekordboxKeyboardOutput {
    private var heldKeys: [ACK05Key: ResolvedKeyboardCommand] = [:]

    deinit {
        for key in Array(heldKeys.keys) {
            release(key: key)
        }
    }

    func send(command: ResolvedKeyboardCommand, keyLabel: String) {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.pioneerdj.rekordboxdj" else {
            log("KEY \(keyLabel) ignored because rekordbox is not frontmost.")
            return
        }

        post(shortcut: command.shortcut, keyDown: true)
        post(shortcut: command.shortcut, keyDown: false)
        log(
            "KEY \(keyLabel) -> \(command.displayName) "
                + "[\(command.shortcut.rawValue)]."
        )
    }

    func pressAndHold(key: ACK05Key, command: ResolvedKeyboardCommand) {
        guard heldKeys[key] == nil else { return }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.pioneerdj.rekordboxdj" else {
            log("KEY \(key.rawValue.uppercased()) ignored because rekordbox is not frontmost.")
            return
        }

        post(shortcut: command.shortcut, keyDown: true)
        heldKeys[key] = command
        log(
            "KEY \(key.rawValue.uppercased()) HOLD -> \(command.displayName) "
                + "[\(command.shortcut.rawValue)] down."
        )
    }

    func release(key: ACK05Key) {
        guard let command = heldKeys.removeValue(forKey: key) else { return }

        post(shortcut: command.shortcut, keyDown: false)
        log(
            "KEY \(key.rawValue.uppercased()) HOLD -> \(command.displayName) "
                + "[\(command.shortcut.rawValue)] up."
        )
    }

    private func post(shortcut: KeyboardShortcut, keyDown: Bool) {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: shortcut.keyCode,
            keyDown: keyDown
        ) else {
            log("ERROR Could not create a keyboard event.")
            return
        }
        event.flags = shortcut.flags
        event.post(tap: .cghidEventTap)
    }
}

private final class InternalActionHandler {
    var captureWaveformPosition: (() -> Void)?

    func handle(_ event: ActionEvent) -> Bool {
        guard event.action == .captureWaveformPosition else { return false }
        if event.phase == .triggered {
            captureWaveformPosition?()
        }
        return true
    }
}

private protocol ACK05ReportHandling: AnyObject {
    func handle(deviceID: String, reportID: UInt32, bytes: [UInt8])
}

private final class MIDIBridgeController: NSObject, ACK05ReportHandling {
    private let decoder = ACK05ReportDecoder()
    private let midi: CoreMIDIVirtualSource
    private let profile: DDJSXMIDIProfile
    private let touchOffInterval: TimeInterval
    private var state = JogStateMachine()
    private var touchOffTimer: Timer?

    init(midi: CoreMIDIVirtualSource, profile: DDJSXMIDIProfile, touchOffMilliseconds: Int) {
        self.midi = midi
        self.profile = profile
        touchOffInterval = TimeInterval(touchOffMilliseconds) / 1_000
        super.init()
    }

    deinit {
        touchOffTimer?.invalidate()
    }

    func handle(deviceID: String, reportID: UInt32, bytes: [UInt8]) {
        guard let event = decoder.decode(reportID: reportID, bytes: bytes) else { return }

        switch event {
        case let .dial(direction):
            emit(state.rotate(direction))
            scheduleTouchOff()
        case let .keyDown(key):
            log("KEY \(key.rawValue.uppercased()) ignored (reserved for future mapping).")
        case .allReleased:
            break
        }
    }

    private func scheduleTouchOff() {
        touchOffTimer?.invalidate()
        let timer = Timer(
            timeInterval: touchOffInterval,
            target: self,
            selector: #selector(touchOffTimerDidFire),
            userInfo: nil,
            repeats: false
        )
        touchOffTimer = timer
        RunLoop.current.add(timer, forMode: .common)
    }

    @objc private func touchOffTimerDidFire(_ timer: Timer) {
        emit(state.touchDidTimeout())
    }

    private func emit(_ commands: [JogCommand]) {
        for command in commands {
            let message = profile.message(for: command)
            do {
                try midi.send(message)
                log("MIDI \(commandLabel(command)) -> \(hex(message.bytes))")
            } catch {
                log("ERROR \(error)")
            }
        }
    }
}

private final class MouseBridgeController: NSObject, ACK05ReportHandling {
    private let decoder = ACK05ReportDecoder()
    private let profile: WaveformDragProfile
    private let keyboardOutput: RekordboxKeyboardOutput
    private let keyboardCommands: [ActionID: ResolvedKeyboardCommand]
    private let internalActionHandler = InternalActionHandler()
    private var mappings: ActionMapping
    private let mappingsByProfile: [String: ActionMapping]
    private let configurationStore: ConfigurationStore
    private var activeProfileName: String
    private var activeDeviceID: String?
    private let releaseInterval: TimeInterval
    private var waveformAnchor: CGPoint?
    private var originalPointerPosition: CGPoint?
    private var currentDragPosition: CGPoint?
    private var isDragging = false
    private var lastRotationTimestamp: TimeInterval?
    private var lastDirection: DialDirection?
    private var smoothedRotationInterval: Double?
    private var releaseTimer: Timer?
    private var didWarnAboutMissingAnchor = false
    private var actionResolver = InputActionResolver()
    private let keyRepeatProfile = AcceleratingKeyRepeatProfile()
    private var repeatingKey: ACK05Key?
    private var keyRepeatStartedAt: TimeInterval?
    private var keyRepeatTimer: Timer?

    init(
        profile: WaveformDragProfile,
        keyboardOutput: RekordboxKeyboardOutput,
        keyboardCommands: [ActionID: ResolvedKeyboardCommand],
        mappingsByProfile: [String: ActionMapping],
        configurationStore: ConfigurationStore,
        releaseMilliseconds: Int
    ) throws {
        self.profile = profile
        self.keyboardOutput = keyboardOutput
        self.keyboardCommands = keyboardCommands
        self.mappingsByProfile = mappingsByProfile
        self.configurationStore = configurationStore
        activeProfileName = configurationStore.configuration.defaultProfile
        guard let defaultMappings = mappingsByProfile[activeProfileName] else {
            throw BridgeError.configuration("Default profile mappings are unavailable.")
        }
        mappings = defaultMappings
        releaseInterval = TimeInterval(releaseMilliseconds) / 1_000
        if let position = try configurationStore.profile(named: activeProfileName).waveformPosition {
            waveformAnchor = CGPoint(x: position.x, y: position.y)
        }
        super.init()

        internalActionHandler.captureWaveformPosition = { [weak self] in
            self?.captureWaveformAnchor()
        }

        guard AXIsProcessTrusted() else {
            throw BridgeError.accessibilityPermissionMissing
        }
    }

    deinit {
        releaseTimer?.invalidate()
        keyRepeatTimer?.invalidate()
        finishDrag(restorePointer: true)
    }

    func handle(deviceID: String, reportID: UInt32, bytes: [UInt8]) {
        activateProfile(for: deviceID)
        if let pressedKeys = decoder.pressedKeys(
            reportID: reportID,
            bytes: bytes,
            previousKeys: actionResolver.pressedKeys
        ) {
            handlePressedKeys(pressedKeys)
            return
        }

        guard let event = decoder.decode(reportID: reportID, bytes: bytes) else { return }

        switch event {
        case let .dial(direction):
            drag(direction)
        case .keyDown, .allReleased:
            break
        }
    }

    private func activateProfile(for deviceID: String) {
        do {
            if try configurationStore.registerDeviceIfNeeded(deviceID) {
                log("Registered device \(deviceID) with default profile '\(configurationStore.configuration.defaultProfile)'.")
            }
        } catch {
            log("ERROR \(error)")
        }
        let profileName = configurationStore.profileName(for: deviceID)
        guard activeDeviceID != deviceID || activeProfileName != profileName else { return }
        guard let nextMappings = mappingsByProfile[profileName] else {
            log("ERROR Device \(deviceID) references unavailable profile '\(profileName)'.")
            return
        }

        for event in actionResolver.reset(mapping: mappings) {
            route(event)
        }
        stopKeyRepeat()
        finishDrag(restorePointer: true)
        mappings = nextMappings
        activeProfileName = profileName
        activeDeviceID = deviceID

        do {
            let savedPosition = try configurationStore.profile(named: profileName).waveformPosition
            waveformAnchor = savedPosition.map { CGPoint(x: $0.x, y: $0.y) }
            log("DEVICE \(deviceID) -> profile '\(profileName)'.")
        } catch {
            log("ERROR \(error)")
        }
    }

    private func handlePressedKeys(_ pressedKeys: Set<ACK05Key>) {
        let released = actionResolver.pressedKeys.subtracting(pressedKeys)
        let events = actionResolver.handle(pressedKeys: pressedKeys, mapping: mappings)
        for event in events {
            route(event)
            if event.phase == .pressed,
               event.action.behavior == .acceleratingRepeat,
               let key = event.sourceKey {
                startKeyRepeat(for: key)
            }
        }
        if let repeatingKey, released.contains(repeatingKey) {
            stopKeyRepeat()
        }
    }

    private func route(_ event: ActionEvent) {
        if internalActionHandler.handle(event) {
            log("ACTION \(event.action.rawValue) from \(event.sourceLabel).")
            return
        }

        switch event.phase {
        case .triggered, .repeated:
            guard let command = resolveKeyboardCommand(for: event) else { return }
            keyboardOutput.send(command: command, keyLabel: event.sourceLabel)
        case .pressed:
            guard let key = event.sourceKey else { return }
            guard let command = resolveKeyboardCommand(for: event) else { return }
            if event.action.behavior == .hold {
                keyboardOutput.pressAndHold(key: key, command: command)
            } else {
                keyboardOutput.send(command: command, keyLabel: event.sourceLabel)
            }
        case .released:
            guard let key = event.sourceKey else { return }
            keyboardOutput.release(key: key)
        }
    }

    private func resolveKeyboardCommand(for event: ActionEvent) -> ResolvedKeyboardCommand? {
        guard let command = keyboardCommands[event.action] else {
            log("KEY \(event.sourceLabel) \(event.action.displayName) is unassigned in rekordbox.")
            return nil
        }
        return command
    }

    private func startKeyRepeat(for key: ACK05Key) {
        stopKeyRepeat()
        repeatingKey = key
        keyRepeatStartedAt = ProcessInfo.processInfo.systemUptime
        scheduleKeyRepeat(afterMilliseconds: keyRepeatProfile.initialDelayMilliseconds)
    }

    private func scheduleKeyRepeat(afterMilliseconds delay: Double) {
        keyRepeatTimer?.invalidate()
        let timer = Timer(
            timeInterval: delay / 1_000,
            target: self,
            selector: #selector(keyRepeatTimerDidFire),
            userInfo: nil,
            repeats: false
        )
        keyRepeatTimer = timer
        RunLoop.current.add(timer, forMode: .common)
    }

    @objc private func keyRepeatTimerDidFire(_ timer: Timer) {
        guard let key = repeatingKey,
              let event = actionResolver.repeatedEvent(for: key, mapping: mappings),
              let startedAt = keyRepeatStartedAt
        else {
            stopKeyRepeat()
            return
        }

        route(event)
        let heldMilliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        let nextInterval = keyRepeatProfile.repeatInterval(heldMilliseconds: heldMilliseconds)
        log(
            String(
                format: "KEY %@ REPEAT held=%.0fms next=%.0fms.",
                key.rawValue.uppercased(),
                heldMilliseconds,
                nextInterval
            )
        )
        scheduleKeyRepeat(afterMilliseconds: nextInterval)
    }

    private func stopKeyRepeat() {
        keyRepeatTimer?.invalidate()
        keyRepeatTimer = nil
        repeatingKey = nil
        keyRepeatStartedAt = nil
    }

    private func captureWaveformAnchor() {
        finishDrag(restorePointer: true)
        guard let location = CGEvent(source: nil)?.location else {
            log("ERROR Could not read the current pointer position.")
            return
        }

        waveformAnchor = location
        didWarnAboutMissingAnchor = false
        do {
            try configurationStore.saveWaveformPosition(location, profileName: activeProfileName)
            log(
                String(
                    format: "MOUSE waveform position captured and saved at x=%.1f y=%.1f.",
                    location.x,
                    location.y
                )
            )
        } catch {
            log("ERROR \(error)")
        }
    }

    private func drag(_ direction: DialDirection) {
        guard let waveformAnchor else {
            if !didWarnAboutMissingAnchor {
                log("MOUSE not calibrated. Hover over the enlarged waveform and press K8+K1.")
                didWarnAboutMissingAnchor = true
            }
            return
        }

        if !isDragging {
            originalPointerPosition = CGEvent(source: nil)?.location
            currentDragPosition = waveformAnchor
            postMouseEvent(type: .mouseMoved, at: waveformAnchor)
            postMouseEvent(type: .leftMouseDown, at: waveformAnchor)
            isDragging = true
        }

        guard var nextPosition = currentDragPosition else { return }
        let timestamp = ProcessInfo.processInfo.systemUptime
        let rawIntervalMilliseconds = lastRotationTimestamp.map { (timestamp - $0) * 1_000 }
        let effectiveIntervalMilliseconds: Double?

        if lastDirection == direction, let rawIntervalMilliseconds {
            let smoothed = profile.smoothedInterval(
                previousMilliseconds: smoothedRotationInterval,
                currentMilliseconds: rawIntervalMilliseconds
            )
            smoothedRotationInterval = smoothed
            effectiveIntervalMilliseconds = smoothed
        } else {
            smoothedRotationInterval = nil
            effectiveIntervalMilliseconds = nil
        }

        lastRotationTimestamp = timestamp
        lastDirection = direction
        let delta = profile.horizontalDelta(
            for: direction,
            intervalMilliseconds: effectiveIntervalMilliseconds
        )
        nextPosition.x += delta
        currentDragPosition = nextPosition
        postMouseEvent(type: .leftMouseDragged, at: nextPosition)
        let rawIntervalLabel = rawIntervalMilliseconds.map { String(format: "%.1fms", $0) } ?? "start"
        let speedIntervalLabel = effectiveIntervalMilliseconds.map { String(format: "%.1fms", $0) } ?? "reset"
        log(
            String(
                format: "MOUSE waveform drag %@ delta=%+.2f interval=%@ smoothed=%@ x=%.2f.",
                direction == .clockwise ? "CW" : "CCW",
                delta,
                rawIntervalLabel,
                speedIntervalLabel,
                nextPosition.x
            )
        )
        scheduleRelease()
    }

    private func scheduleRelease() {
        releaseTimer?.invalidate()
        let timer = Timer(
            timeInterval: releaseInterval,
            target: self,
            selector: #selector(releaseTimerDidFire),
            userInfo: nil,
            repeats: false
        )
        releaseTimer = timer
        RunLoop.current.add(timer, forMode: .common)
    }

    @objc private func releaseTimerDidFire(_ timer: Timer) {
        finishDrag(restorePointer: true)
    }

    private func finishDrag(restorePointer: Bool) {
        releaseTimer?.invalidate()
        releaseTimer = nil

        if isDragging, let currentDragPosition {
            postMouseEvent(type: .leftMouseUp, at: currentDragPosition)
            log("MOUSE waveform drag released.")
        }

        isDragging = false
        currentDragPosition = nil
        lastRotationTimestamp = nil
        lastDirection = nil
        smoothedRotationInterval = nil

        if restorePointer, let originalPointerPosition {
            postMouseEvent(type: .mouseMoved, at: originalPointerPosition)
        }
        originalPointerPosition = nil
    }

    private func postMouseEvent(type: CGEventType, at location: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: .left
        ) else {
            log("ERROR Could not create a mouse event.")
            return
        }
        event.post(tap: .cghidEventTap)
    }
}

private final class ACK05HIDInput {
    private let controller: any ACK05ReportHandling
    private let manager: IOHIDManager
    private let seizeDevice: Bool

    init(controller: any ACK05ReportHandling, seizeDevice: Bool) {
        self.controller = controller
        self.seizeDevice = seizeDevice
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: ACK05Identity.vendorID,
            kIOHIDProductIDKey as String: ACK05Identity.productID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, bridgeDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, bridgeDeviceRemoved, context)
        IOHIDManagerRegisterInputReportCallback(manager, bridgeInputReportReceived, context)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetCurrent(),
            CFRunLoopMode.defaultMode.rawValue
        )
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetCurrent(),
            CFRunLoopMode.defaultMode.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func start() throws {
        let options = seizeDevice
            ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
            : IOOptionBits(kIOHIDOptionsTypeNone)
        let result = IOHIDManagerOpen(manager, options)
        guard result == kIOReturnSuccess else {
            throw BridgeError.hidOpenFailed(result)
        }
    }

    func didMatch(device: IOHIDDevice, result: IOReturn) {
        guard result == kIOReturnSuccess else {
            log("ERROR ACK05 connection callback failed (\(formatStatus(result))).")
            return
        }
        log("ACK05 connected: \(deviceIdentity(device)).")
    }

    func didRemove(device: IOHIDDevice, result: IOReturn) {
        guard result == kIOReturnSuccess else {
            log("ERROR ACK05 removal callback failed (\(formatStatus(result))).")
            return
        }
        log("ACK05 disconnected: \(deviceIdentity(device)).")
    }

    func didReceiveReport(
        result: IOReturn,
        device: IOHIDDevice?,
        reportID: UInt32,
        report: UnsafeMutablePointer<UInt8>,
        reportLength: CFIndex
    ) {
        guard result == kIOReturnSuccess else {
            log("ERROR HID report failed (\(formatStatus(result))).")
            return
        }

        let bytes = Array(
            UnsafeBufferPointer(start: report, count: max(0, Int(reportLength)))
        )
        controller.handle(
            deviceID: device.map(deviceIdentifier) ?? "unknown",
            reportID: reportID,
            bytes: bytes
        )
    }
}

private func bridgeDeviceMatched(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<ACK05HIDInput>.fromOpaque(context).takeUnretainedValue()
        .didMatch(device: device, result: result)
}

private func bridgeDeviceRemoved(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<ACK05HIDInput>.fromOpaque(context).takeUnretainedValue()
        .didRemove(device: device, result: result)
}

private func bridgeInputReportReceived(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    reportType: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context else { return }
    let device = sender.map { Unmanaged<IOHIDDevice>.fromOpaque($0).takeUnretainedValue() }
    Unmanaged<ACK05HIDInput>.fromOpaque(context).takeUnretainedValue().didReceiveReport(
        result: result,
        device: device,
        reportID: reportID,
        report: report,
        reportLength: reportLength
    )
}

private func deviceIdentity(_ device: IOHIDDevice) -> String {
    let manufacturer = IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String
    let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
    return "\(manufacturer ?? "unknown") / \(product ?? "unknown")"
}

private func deviceIdentifier(_ device: IOHIDDevice) -> String {
    for key in ["PhysicalDeviceUniqueID", "DeviceAddress"] {
        if let value = IOHIDDeviceGetProperty(device, key as CFString) as? String,
           !value.isEmpty {
            return value
        }
    }
    if let location = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? NSNumber {
        return String(format: "location:%08X", location.uint32Value)
    }
    return "unknown"
}

private func commandLabel(_ command: JogCommand) -> String {
    switch command {
    case .touchOn:
        return "JogTouch ON"
    case .touchOff:
        return "JogTouch OFF"
    case .scratch(.clockwise):
        return "JogScratch CW"
    case .scratch(.counterclockwise):
        return "JogScratch CCW"
    }
}

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

private func formatStatus<T: FixedWidthInteger>(_ status: T) -> String {
    String(format: "0x%08X", UInt32(truncatingIfNeeded: status))
}

private func log(_ message: String) {
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    FileHandle.standardOutput.write(Data(line.utf8))
}

do {
    let options = try BridgeOptions.parse(CommandLine.arguments)
    let controller: any ACK05ReportHandling

    switch options.outputMode {
    case .midi:
        let profile = try DDJSXMIDIProfile(deck: options.deck)
        let midi = try CoreMIDIVirtualSource(name: options.sourceName)
        controller = MIDIBridgeController(
            midi: midi,
            profile: profile,
            touchOffMilliseconds: options.touchOffMilliseconds
        )
        log("CoreMIDI source '\(options.sourceName)' is ready for Deck \(options.deck).")
        log("JogTouch timeout: \(options.touchOffMilliseconds) ms.")
    case .mouse:
        let configurationStore = try ConfigurationStore(path: options.configPath)
        var mappingsByProfile: [String: ActionMapping] = [:]
        for (name, profileConfiguration) in configurationStore.configuration.profiles {
            mappingsByProfile[name] = try ActionMapping(profile: profileConfiguration)
        }
        let defaultProfileName = configurationStore.configuration.defaultProfile
        guard let mappings = mappingsByProfile[defaultProfileName] else {
            throw BridgeError.configuration("Default profile mappings are unavailable.")
        }
        let defaultProfile = try configurationStore.profile(named: defaultProfileName)
        let maximumPixels = options.accelerationEnabled
            ? options.maximumDragPixels
            : options.dragPixels
        let profile = WaveformDragProfile(
            pixelsPerDetent: options.dragPixels,
            maximumPixelsPerDetent: maximumPixels,
            isInverted: options.invertDial
        )
        let loadedShortcuts = try RekordboxAdapter().load(mode: options.rekordboxMode)
        let keyboardOutput = RekordboxKeyboardOutput()
        controller = try MouseBridgeController(
            profile: profile,
            keyboardOutput: keyboardOutput,
            keyboardCommands: loadedShortcuts.actions,
            mappingsByProfile: mappingsByProfile,
            configurationStore: configurationStore,
            releaseMilliseconds: options.touchOffMilliseconds
        )
        log("Free-plan mouse output is ready.")
        log(
            "Rekordbox shortcut mode: \(options.rekordboxMode.rawValue) "
                + "[\(loadedShortcuts.name)]."
        )
        log("Configuration: \(configurationStore.url.path)")
        log("Default profile: \(defaultProfileName)")
        if let position = defaultProfile.waveformPosition {
            log(String(format: "Saved waveform position: x=%.1f y=%.1f.", position.x, position.y))
        } else {
            log("Waveform position is not saved yet.")
        }
        log(String(format: "Waveform drag: %.2f to %.2f px/detent.", options.dragPixels, maximumPixels))
        log(options.accelerationEnabled ? "Rotation-speed acceleration is ON." : "Rotation-speed acceleration is OFF.")
        log(options.invertDial ? "Dial direction is inverted." : "Dial direction is normal.")
        for key in ACK05Key.allCases {
            let action = mappings.keys[key] ?? defaultAction(for: key)
            if let resolved = loadedShortcuts.actions[action] {
                log("  \(key.rawValue.uppercased()): \(action.displayName) [\(resolved.shortcut.rawValue)]")
            } else {
                log("  \(key.rawValue.uppercased()): \(action.displayName) [unassigned]")
            }
        }
        for chord in defaultProfile.chordMap.keys.sorted() {
            let normalizedChord = chord.uppercased().replacingOccurrences(of: " ", with: "")
            guard let configuredChord = mappings.chords.keys.first(where: { $0.label == normalizedChord }),
                  let chordAction = mappings.chords[configuredChord]
            else {
                continue
            }
            if chordAction == .captureWaveformPosition {
                log("  \(chord): \(chordAction.displayName)")
            } else {
                let action = chordAction
                let shortcut = loadedShortcuts.actions[action]?.shortcut.rawValue ?? "unassigned"
                log("  \(chord): \(action.displayName) [\(shortcut)]")
            }
        }
        for (deviceID, profileName) in configurationStore.configuration.deviceProfiles.sorted(by: { $0.key < $1.key }) {
            log("  DEVICE \(deviceID) -> profile '\(profileName)'")
        }
        log("Hover over the enlarged waveform and use the capture chord to save its position.")
    }

    let hid = ACK05HIDInput(controller: controller, seizeDevice: options.seizeDevice)
    try hid.start()

    log(options.seizeDevice ? "ACK05 exclusive input is ON." : "ACK05 shared input is ON.")
    log("Rotate the ACK05 dial. Press Control-C to stop.")

    CFRunLoopRun()
} catch {
    fputs("overcue: \(error)\n", stderr)
    BridgeOptions.printUsage()
    exit(EXIT_FAILURE)
}

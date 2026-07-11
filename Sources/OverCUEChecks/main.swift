import Darwin
import Foundation
import OverCUECore

private var checkCount = 0
private var failureCount = 0

@MainActor
private func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    checkCount += 1
    if !condition() {
        failureCount += 1
        fputs("FAIL: \(label)\n", stderr)
    }
}

let decoder = ACK05ReportDecoder()

check(Set(ActionID.allCases.map(\.rawValue)).count == ActionID.allCases.count, "Action IDs are unique")
check(ActionID.allCases.allSatisfy { !$0.displayName.isEmpty }, "every Action ID has a display name")
for action in ActionID.allCases {
    do {
        let encoded = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(ActionID.self, from: encoded)
        check(decoded == action, "Action ID Codable round-trip \(action.rawValue)")
        check(ActionID(legacyDisplayName: action.displayName) == action, "legacy display mapping \(action.rawValue)")
    } catch {
        failureCount += 1
        fputs("FAIL: Action ID Codable error for \(action.rawValue): \(error)\n", stderr)
    }
}
check(ActionID.cue.behavior == .hold, "Cue uses hold behavior")
check(ActionID.jumpForward.behavior == .acceleratingRepeat, "Jump uses repeat behavior")
check(ActionID.captureWaveformPosition.behavior == .internalCommand, "capture uses internal behavior")
check(RekordboxActionAdapter.commandID(for: .hotCue1) == "301e", "rekordbox Hot Cue 1 command")
check(RekordboxActionAdapter.commandID(for: .callNextMemoryCue) == "3039", "rekordbox next Memory Cue command")
check(RekordboxActionAdapter.commandID(for: .callPreviousMemoryCue) == "303a", "rekordbox previous Memory Cue command")
check(RekordboxActionAdapter.commandID(for: .captureWaveformPosition) == nil, "internal action has no rekordbox command")
check(ActionTarget(configurationValue: "hot_cue_1") == .action(.hotCue1), "built-in Action target parses")
check(ActionTarget(configurationValue: "rekordbox:42ff") == .rekordboxCommand("42ff"), "generic rekordbox target parses")
check(ActionTarget(configurationValue: "rekordbox:") == nil, "empty generic rekordbox target is rejected")
check(RekordboxActionAdapter.commandID(for: .rekordboxCommand("42ff")) == "42ff", "generic target keeps command ID")
check(RekordboxActionAdapter.target(for: "301e") == .action(.hotCue1), "known command ID maps to built-in Action")
check(RekordboxActionAdapter.target(for: "42ff") == .rekordboxCommand("42ff"), "unknown command ID maps to generic target")

let genericMapping = ActionMapping(
    keys: [.k2: .rekordboxCommand("42ff")],
    chords: [:]
)
var genericResolver = InputActionResolver()
check(
    genericResolver.handle(pressedKeys: [.k2], mapping: genericMapping).first?.target == .rekordboxCommand("42ff"),
    "generic rekordbox target resolves from a physical key"
)

let actionMapping = ActionMapping(
    keys: [
        .k1: .hotCue3,
        .k3: .jumpForward,
        .k7: .quantize,
        .k8: .hotCue1,
        .k9: .cue,
    ],
    chords: [
        KeyChord(modifier: .k7, trigger: .k1): .deleteHotCue3,
        KeyChord(modifier: .k8, trigger: .k1): .captureWaveformPosition,
    ]
)
var triggerResolver = InputActionResolver()
check(triggerResolver.handle(pressedKeys: [.k1], mapping: actionMapping) == [
    ActionEvent(action: .hotCue3, phase: .triggered, sourceKey: .k1, sourceLabel: "K1")
], "normal key resolves to Action")
check(triggerResolver.handle(pressedKeys: [], mapping: actionMapping).isEmpty, "trigger key release emits nothing")

var cueResolver = InputActionResolver()
check(cueResolver.handle(pressedKeys: [.k9], mapping: actionMapping).first?.phase == .pressed, "Cue emits pressed")
check(cueResolver.handle(pressedKeys: [], mapping: actionMapping).first?.phase == .released, "Cue emits released")

var repeatResolver = InputActionResolver()
check(repeatResolver.handle(pressedKeys: [.k3], mapping: actionMapping).first?.action == .jumpForward, "Jump emits Action")
check(repeatResolver.repeatedEvent(for: .k3, mapping: actionMapping)?.phase == .repeated, "Jump repeat reissues Action")
_ = repeatResolver.handle(pressedKeys: [], mapping: actionMapping)
check(repeatResolver.repeatedEvent(for: .k3, mapping: actionMapping) == nil, "Jump repeat stops on release")

var chordResolver = InputActionResolver()
check(chordResolver.handle(pressedKeys: [.k7], mapping: actionMapping).isEmpty, "modifier press is deferred")
check(chordResolver.handle(pressedKeys: [.k7, .k1], mapping: actionMapping) == [
    ActionEvent(action: .deleteHotCue3, phase: .triggered, sourceKey: .k1, sourceLabel: "K7+K1")
], "chord emits Action and suppresses trigger")
check(chordResolver.handle(pressedKeys: [.k7], mapping: actionMapping).isEmpty, "chord trigger release emits nothing")
check(chordResolver.handle(pressedKeys: [], mapping: actionMapping).isEmpty, "used modifier action is suppressed")

var unusedModifierResolver = InputActionResolver()
_ = unusedModifierResolver.handle(pressedKeys: [.k7], mapping: actionMapping)
check(unusedModifierResolver.handle(pressedKeys: [], mapping: actionMapping) == [
    ActionEvent(action: .quantize, phase: .triggered, sourceKey: .k7, sourceLabel: "K7")
], "unused modifier emits standalone Action on release")

let legacyConfiguration = OverCUEConfiguration(
    version: 2,
    defaultProfile: "legacy",
    profiles: [
        "legacy": OverCUEProfile(
            waveformPosition: WaveformPosition(x: 12.5, y: 34.5),
            keyMap: [
                "K1": "Hot Cue C",
                "K2": "Unknown Legacy Action",
                "K9": "Cue",
            ],
            chordMap: [
                "K8+K1": "Capture Waveform Position",
                "K7+K8": "Delete Hot Cue A",
                "K7+K4": "Delete Hot Cue B",
                "K7+K1": "Delete Hot Cue C",
            ]
        )
    ],
    deviceProfiles: ["device-1": "legacy"]
)
let migration = ActionConfigurationMigrator.migrateToVersion3(legacyConfiguration)
check(migration.configuration.version == 3, "migration updates configuration version")
check(migration.configuration.profiles["legacy"]?.keyMap["K1"] == "hot_cue_3", "migration converts known key Action")
check(migration.configuration.profiles["legacy"]?.keyMap["K9"] == "cue", "migration converts Cue Action")
check(migration.configuration.profiles["legacy"]?.keyMap["K2"] == nil, "migration disables unknown Action")
check(migration.warnings == [
    ActionMigrationWarning(
        profileName: "legacy",
        section: "keyMap",
        input: "K2",
        rawAction: "Unknown Legacy Action"
    )
], "migration reports unknown Action")
check(
    migration.configuration.profiles["legacy"]?.waveformPosition == WaveformPosition(x: 12.5, y: 34.5),
    "migration preserves waveform position"
)
check(migration.configuration.deviceProfiles["device-1"] == "legacy", "migration preserves device profile")
check(
    migration.configuration.profiles["legacy"]?.chordMap["K7+K3"] == "call_next_memory_cue",
    "migration upgrades prior default chords"
)

check(
    decoder.decode(reportID: 6, bytes: [6, 1, 0x57, 0, 0, 0, 0, 0]) == .dial(.clockwise),
    "decode clockwise dial"
)
check(
    decoder.decode(reportID: 6, bytes: [6, 1, 0x56, 0, 0, 0, 0, 0]) == .dial(.counterclockwise),
    "decode counterclockwise dial"
)

let keyReports: [(ACK05Key, [UInt8])] = [
    (.k1, [6, 1, 0x12, 0, 0, 0, 0, 0]),
    (.k2, [6, 1, 0x11, 0, 0, 0, 0, 0]),
    (.k3, [6, 0, 0x3E, 0, 0, 0, 0, 0]),
    (.k4, [6, 2, 0x00, 0, 0, 0, 0, 0]),
    (.k5, [6, 1, 0x00, 0, 0, 0, 0, 0]),
    (.k6, [6, 4, 0x00, 0, 0, 0, 0, 0]),
    (.k7, [6, 1, 0x16, 0, 0, 0, 0, 0]),
    (.k8, [6, 1, 0x1D, 0, 0, 0, 0, 0]),
    (.k9, [6, 0, 0x2C, 0, 0, 0, 0, 0]),
    (.k10, [6, 3, 0x1D, 0, 0, 0, 0, 0]),
]
for (key, report) in keyReports {
    check(decoder.decode(reportID: 6, bytes: report) == .keyDown(key), "decode \(key.rawValue)")
}

check(
    decoder.decode(reportID: 6, bytes: [6, 0, 0, 0, 0, 0, 0, 0]) == .allReleased,
    "decode release"
)
check(
    decoder.pressedKeys(reportID: 6, bytes: [6, 1, 0x1D, 0, 0, 0, 0, 0]) == [.k8],
    "decode K8 pressed state"
)
check(
    decoder.pressedKeys(reportID: 6, bytes: [6, 1, 0x1D, 0x12, 0, 0, 0, 0]) == [.k8, .k1],
    "decode K8+K1 chord"
)
check(
    decoder.pressedKeys(reportID: 6, bytes: [6, 1, 0x16, 0x1D, 0, 0, 0, 0]) == [.k7, .k8],
    "decode K7+K8 chord"
)
check(
    decoder.pressedKeys(reportID: 6, bytes: [6, 3, 0x16, 0, 0, 0, 0, 0]) == [.k7, .k4],
    "decode K7+K4 chord"
)
check(
    decoder.pressedKeys(reportID: 6, bytes: [6, 1, 0x16, 0x12, 0, 0, 0, 0]) == [.k7, .k1],
    "decode K7+K1 chord"
)
check(
    decoder.pressedKeys(
        reportID: 6,
        bytes: [6, 1, 0x12, 0, 0, 0, 0, 0],
        previousKeys: [.k5]
    ) == [.k5, .k1],
    "retain modifier-only K5 in K5+K1 chord"
)
check(
    decoder.pressedKeys(
        reportID: 6,
        bytes: [6, 3, 0x1D, 0, 0, 0, 0, 0],
        previousKeys: [.k8]
    ) == [.k8, .k4],
    "disambiguate K8+K4 from K10 using previous state"
)
check(
    decoder.pressedKeys(
        reportID: 6,
        bytes: [6, 5, 0x2C, 0, 0, 0, 0, 0],
        previousKeys: [.k6]
    ) == [.k6, .k9, .k5],
    "reconstruct combined modifier-only keys"
)
check(
    decoder.pressedKeys(reportID: 6, bytes: [6, 0, 0, 0, 0, 0, 0, 0]) == [],
    "decode empty pressed state"
)
check(
    decoder.pressedKeys(reportID: 6, bytes: [6, 1, 0x57, 0, 0, 0, 0, 0]) == nil,
    "dial report is not a key state"
)
check(decoder.decode(reportID: 5, bytes: [6, 1, 0x57, 0, 0, 0, 0, 0]) == nil, "reject report ID")
check(decoder.decode(reportID: 6, bytes: [6, 1, 0x57]) == nil, "reject report length")
check(
    decoder.decode(reportID: 6, bytes: [6, 1, 0x57, 1, 0, 0, 0, 0]) == nil,
    "reject unexpected trailing data"
)

var state = JogStateMachine()
check(state.rotate(.clockwise) == [.touchOn, .scratch(.clockwise)], "touch on before first rotation")
check(state.rotate(.counterclockwise) == [.scratch(.counterclockwise)], "keep touch during rotation")
check(state.touchDidTimeout() == [.touchOff], "touch off on timeout")
check(state.touchDidTimeout() == [], "do not duplicate touch off")

let normalDrag = WaveformDragProfile(pixelsPerDetent: 1, maximumPixelsPerDetent: 20)
check(normalDrag.horizontalDelta(for: .clockwise) == -1, "first clockwise detent uses fine movement")
check(normalDrag.horizontalDelta(for: .counterclockwise) == 1, "first counterclockwise detent uses fine movement")
check(
    normalDrag.horizontalDelta(for: .clockwise, intervalMilliseconds: 250) == -1,
    "slow rotation stays fine"
)
check(
    normalDrag.horizontalDelta(for: .clockwise, intervalMilliseconds: 20) == -20,
    "fast rotation reaches maximum acceleration"
)
let mediumMagnitude = normalDrag.dragMagnitude(intervalMilliseconds: 100)
check(mediumMagnitude > 1 && mediumMagnitude < 20, "medium rotation interpolates acceleration")
check(
    normalDrag.dragMagnitude(intervalMilliseconds: 150) < 1.25,
    "fourth-power curve preserves fine slow rotation"
)
check(mediumMagnitude > 3.5 && mediumMagnitude < 3.7, "fourth-power curve medium value")
check(
    normalDrag.dragMagnitude(intervalMilliseconds: 50) > 13
        && normalDrag.dragMagnitude(intervalMilliseconds: 50) < 15,
    "fourth-power curve fast value"
)
let firstSmoothedInterval = normalDrag.smoothedInterval(
    previousMilliseconds: nil,
    currentMilliseconds: 50
)
check(firstSmoothedInterval == 147.5, "first fast interval is smoothed from slow baseline")
let secondSmoothedInterval = normalDrag.smoothedInterval(
    previousMilliseconds: firstSmoothedInterval,
    currentMilliseconds: 50
)
check(secondSmoothedInterval > 113 && secondSmoothedInterval < 114, "speed ramps over multiple detents")

let keyRepeat = AcceleratingKeyRepeatProfile()
check(keyRepeat.repeatInterval(heldMilliseconds: 0) == 180, "key repeat stays slow before initial delay")
check(keyRepeat.repeatInterval(heldMilliseconds: 400) == 180, "key repeat starts at slow interval")
check(keyRepeat.repeatInterval(heldMilliseconds: 1_400) == 107.5, "key repeat accelerates smoothly")
check(keyRepeat.repeatInterval(heldMilliseconds: 2_400) == 35, "key repeat reaches fast interval")
check(keyRepeat.repeatInterval(heldMilliseconds: 4_000) == 35, "key repeat clamps at fast interval")

let invertedDrag = WaveformDragProfile(
    pixelsPerDetent: 0.5,
    maximumPixelsPerDetent: 0.5,
    isInverted: true
)
check(invertedDrag.horizontalDelta(for: .clockwise) == 0.5, "invert clockwise drag")
check(invertedDrag.horizontalDelta(for: .counterclockwise) == -0.5, "invert counterclockwise drag")

do {
    let mappingXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <PROPERTIES>
      <VALUE name="keyMappingName" val="Test Mapping"/>
      <VALUE name="keyMappingXml">
        <KEYMAPPINGS>
          <MAPPING commandId="3006" description="Play/Pause" key="spacebar"/>
          <MAPPING commandId="3007" description="Cue" key="shift + C"/>
        </KEYMAPPINGS>
      </VALUE>
    </PROPERTIES>
    """
    let mapping = try RekordboxKeyMapping.parse(data: Data(mappingXML.utf8))
    check(mapping.name == "Test Mapping", "parse rekordbox mapping name")
    check(mapping.entries.count == 2, "preserve ordered rekordbox shortcut entries")
    check(mapping.entries[0].commandID == "3006", "preserve rekordbox command ID")
    check(mapping.entries[0].description == "Play/Pause", "preserve rekordbox description")
    check(mapping.entries[1].shortcut == "shift + C", "preserve rekordbox shortcut text")
    check(mapping.shortcut(for: "3006") == "spacebar", "parse rekordbox Play/Pause shortcut")
    check(mapping.shortcut(for: "3007") == "shift + C", "parse rekordbox Cue shortcut")

    check(
        RekordboxShortcutCategory.category(for: "b129") == .browse,
        "categorize Browse shortcut"
    )
    check(
        RekordboxShortcutCategory.category(for: "3006") == .deck1,
        "categorize Deck 1 shortcut"
    )
    check(
        RekordboxShortcutCategory.category(for: "3106") == .deck2,
        "categorize Deck 2 shortcut"
    )
    check(
        RekordboxShortcutCategory.category(for: "3000") == .allDecks,
        "categorize All Decks shortcut"
    )
    check(
        RekordboxShortcutCategory.category(for: "f001") == .sampler,
        "categorize Sampler shortcut"
    )

    let settingsXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <PROPERTIES><VALUE name="performaceKeyMapping" val="1234567890123"/></PROPERTIES>
    """
    let settings = try RekordboxSettings.parse(data: Data(settingsXML.utf8))
    check(settings.performanceKeyMappingID == "1234567890123", "parse selected Performance mapping")
} catch {
    failureCount += 1
    fputs("FAIL: unexpected rekordbox XML parsing error: \(error)\n", stderr)
}

do {
    let temporaryHome = FileManager.default.temporaryDirectory
        .appendingPathComponent("overcue-loader-\(UUID().uuidString)")
    let baseURL = temporaryHome
        .appendingPathComponent("Library/Application Support/Pioneer/rekordbox6")
    let mappingsURL = baseURL.appendingPathComponent("KeyMappings")
    try FileManager.default.createDirectory(at: mappingsURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryHome) }

    let settingsXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <PROPERTIES><VALUE name="performaceKeyMapping" val="1234567890123"/></PROPERTIES>
    """
    let mappingXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <PROPERTIES>
      <VALUE name="keyMappingName" val="Loader Test"/>
      <VALUE name="keyMappingXml">
        <KEYMAPPINGS><MAPPING commandId="3006" description="Play/Pause" key="spacebar"/></KEYMAPPINGS>
      </VALUE>
    </PROPERTIES>
    """
    let exportMappingXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <PROPERTIES>
      <VALUE name="keyMappingName" val="Export Loader Test"/>
      <VALUE name="keyMappingXml">
        <KEYMAPPINGS>
          <MAPPING commandId="3006" description="Play/Pause" key="spacebar"/>
          <MAPPING commandId="3007" description="Cue" key="C"/>
        </KEYMAPPINGS>
      </VALUE>
    </PROPERTIES>
    """
    try Data(settingsXML.utf8).write(to: baseURL.appendingPathComponent("rekordbox3.settings"))
    try Data(mappingXML.utf8).write(
        to: mappingsURL.appendingPathComponent("rekordbox_1234567890123.mappings")
    )
    try Data(exportMappingXML.utf8).write(
        to: mappingsURL.appendingPathComponent("rekordbox_0000000000030.mappings")
    )

    let loader = RekordboxKeyMappingLoader(homeDirectory: temporaryHome)
    let performance = try loader.load(mode: .performance)
    check(performance.mappingID == "1234567890123", "load selected Performance mapping ID")
    check(performance.mapping.name == "Loader Test", "load selected Performance mapping XML")
    check(performance.mapping.entries.count == 1, "load Performance shortcut entries")
    let export = try loader.load(mode: .export)
    check(export.mappingID == "0000000000030", "load fixed Export mapping ID")
    check(export.mapping.name == "Export Loader Test", "switch loader to Export mapping XML")
    check(export.mapping.entries.count == 2, "load distinct Export shortcut entries")
} catch {
    failureCount += 1
    fputs("FAIL: unexpected rekordbox mapping loader error: \(error)\n", stderr)
}

do {
    var configuration = OverCUEConfiguration.defaultValue
    configuration.profiles["default"]?.waveformPosition = WaveformPosition(x: 640.5, y: 212.25)
    configuration.profiles["default"]?.keyMap["K1"] = "hot_cue_1"
    configuration.profiles["alternate"] = OverCUEProfile.defaultValue
    configuration.deviceProfiles["device-uuid"] = "alternate"
    let data = try JSONEncoder().encode(configuration)
    let decoded = try JSONDecoder().decode(OverCUEConfiguration.self, from: data)
    check(decoded == configuration, "round-trip external configuration")
    check(decoded.version == 3, "persist profile configuration version")
    check(
        decoded.profiles["default"]?.waveformPosition == WaveformPosition(x: 640.5, y: 212.25),
        "persist profile waveform position"
    )
    check(decoded.profiles["default"]?.keyMap["K1"] == "hot_cue_1", "persist profile Action ID")
    check(
        decoded.profiles["default"]?.chordMap["K7+K8"] == "delete_hot_cue_1",
        "persist profile chord mapping"
    )
    check(
        decoded.profiles["default"]?.chordMap["K7+K3"] == "call_next_memory_cue",
        "persist next Memory Cue chord"
    )
    check(
        decoded.profiles["default"]?.chordMap["K7+K6"] == "call_previous_memory_cue",
        "persist previous Memory Cue chord"
    )
    check(decoded.deviceProfiles["device-uuid"] == "alternate", "persist device profile assignment")
} catch {
    failureCount += 1
    fputs("FAIL: unexpected configuration error: \(error)\n", stderr)
}

do {
    let deck1 = try DDJSXMIDIProfile(deck: 1)
    check(deck1.message(for: .touchOn).bytes == [0x90, 0x36, 0x7F], "Deck 1 touch on MIDI")
    check(deck1.message(for: .touchOff).bytes == [0x90, 0x36, 0x00], "Deck 1 touch off MIDI")
    check(deck1.message(for: .scratch(.clockwise)).bytes == [0xB0, 0x22, 0x41], "Deck 1 clockwise MIDI")
    check(
        deck1.message(for: .scratch(.counterclockwise)).bytes == [0xB0, 0x22, 0x3F],
        "Deck 1 counterclockwise MIDI"
    )

    let deck4 = try DDJSXMIDIProfile(deck: 4)
    check(deck4.message(for: .touchOn).status == 0x93, "Deck 4 note channel")
    check(deck4.message(for: .scratch(.clockwise)).status == 0xB3, "Deck 4 CC channel")
} catch {
    failureCount += 1
    fputs("FAIL: unexpected MIDI profile error: \(error)\n", stderr)
}

do {
    _ = try DDJSXMIDIProfile(deck: 0)
    check(false, "reject Deck 0")
} catch {
    check(error as? DDJSXMIDIProfileError == .invalidDeck(0), "reject Deck 0")
}

do {
    _ = try DDJSXMIDIProfile(deck: 5)
    check(false, "reject Deck 5")
} catch {
    check(error as? DDJSXMIDIProfileError == .invalidDeck(5), "reject Deck 5")
}

guard failureCount == 0 else {
    fputs("\(failureCount) of \(checkCount) checks failed.\n", stderr)
    exit(EXIT_FAILURE)
}

print("All \(checkCount) OverCUE core checks passed.")

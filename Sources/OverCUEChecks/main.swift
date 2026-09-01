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
check(ActionID.jogSearchLeft.behavior == .internalCommand, "Jog Search Left uses internal behavior")
check(ActionID.cycleGroup.behavior == .internalCommand, "group cycle uses internal behavior")
check(
    ActionID.cycleGroupBackward.behavior == .internalCommand,
    "descending group cycle uses internal behavior"
)
check(ActionID.toggleRekordboxMode.behavior == .internalCommand, "mode toggle uses internal behavior")
check(RekordboxActionAdapter.commandID(for: .hotCue1) == "301e", "rekordbox Hot Cue 1 command")
check(RekordboxActionAdapter.commandID(for: .playPause, deck: .deck1) == "3006", "Play/Pause resolves for Deck 1")
check(RekordboxActionAdapter.commandID(for: .playPause, deck: .deck2) == "3106", "Play/Pause resolves for Deck 2")
check(RekordboxActionAdapter.commandID(for: .playPause, deck: .deck3) == "3206", "Play/Pause resolves for Deck 3")
check(RekordboxActionAdapter.commandID(for: .playPause, deck: .deck4) == "3306", "Play/Pause resolves for Deck 4")
check(RekordboxActionAdapter.commandID(for: .pitchBendIncrease, deck: .deck4) == "334f", "Pitch Bend uses the shared Deck rule")
check(RekordboxActionAdapter.commandID(for: .callNextMemoryCue) == "3039", "rekordbox next Memory Cue command")
check(RekordboxActionAdapter.commandID(for: .callPreviousMemoryCue) == "303a", "rekordbox previous Memory Cue command")
check(RekordboxActionAdapter.commandID(for: .captureWaveformPosition) == nil, "internal action has no rekordbox command")
check(ActionTarget(configurationValue: "hot_cue_1") == .action(.hotCue1), "built-in Action target parses")
check(ActionTarget(configurationValue: "rekordbox:42ff") == .rekordboxCommand("42ff"), "generic rekordbox target parses")
check(ActionTarget(configurationValue: "rekordbox:") == nil, "empty generic rekordbox target is rejected")
check(RekordboxActionAdapter.commandID(for: .rekordboxCommand("42ff")) == "42ff", "generic target keeps command ID")
check(RekordboxActionAdapter.commandID(for: .rekordboxCommand("42ff"), deck: .deck4) == "42ff", "generic target is not Deck-transformed")
check(RekordboxActionAdapter.target(for: "301e") == .action(.hotCue1), "known command ID maps to built-in Action")
check(RekordboxActionAdapter.target(for: "42ff") == .rekordboxCommand("42ff"), "unknown command ID maps to generic target")
check(RekordboxActionAdapter.target(for: "331e") == .action(.hotCue1), "Deck 4 command maps to shared Action")

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

let threeKeyChord = KeyChord(keys: [.k7, .k8, .k1])!
let overlappingChordMapping = ActionMapping(
    keys: [:],
    chords: [
        KeyChord(modifier: .k8, trigger: .k1): .captureWaveformPosition,
        threeKeyChord: .cycleGroup,
    ]
)
var threeChordResolver = InputActionResolver()
check(
    threeChordResolver.handle(pressedKeys: [.k7, .k8], mapping: overlappingChordMapping).isEmpty,
    "three-key chord modifiers are deferred"
)
check(threeChordResolver.handle(pressedKeys: [.k7, .k8, .k1], mapping: overlappingChordMapping) == [
    ActionEvent(action: .cycleGroup, phase: .triggered, sourceKey: .k1, sourceLabel: "K7+K8+K1")
], "three-key chord wins over overlapping two-key chord")

let fiveKeyChord = KeyChord(keys: [.k7, .k8, .k5, .k4, .k1])!
let fiveKeyMapping = ActionMapping(keys: [:], chords: [fiveKeyChord: .toggleRekordboxMode])
var fiveKeyResolver = InputActionResolver()
check(
    fiveKeyResolver.handle(pressedKeys: [.k7, .k8, .k5, .k4], mapping: fiveKeyMapping).isEmpty,
    "arbitrary chord modifiers are deferred"
)
check(
    fiveKeyResolver.handle(
        pressedKeys: [.k7, .k8, .k5, .k4, .k1],
        mapping: fiveKeyMapping
    ).first?.action == .toggleRekordboxMode,
    "five-key chord resolves an Action"
)
check(KeyChord(keys: ACK05Key.allCases) != nil, "all ACK05 buttons can form one chord")
check(KeyChord(keys: [.k1]) == nil, "single key is not represented as a chord")

let occupiedConflict = ActionMappingConflictDetector.conflict(
    for: .key(.k1),
    target: .action(.hotCue2),
    profile: .defaultValue,
    selectedGroup: 1
)
check(
    occupiedConflict?.kind == .occupied(existing: .action(.hotCue3)),
    "detect an existing physical shortcut collision"
)
let longModifierChord = KeyChord(keys: [.k9, .k1])!
let modifierConflict = ActionMappingConflictDetector.conflict(
    for: .chord(longModifierChord),
    target: .action(.deleteHotCue1),
    profile: .defaultValue,
    selectedGroup: 1
)
check(
    modifierConflict?.kind == .chordUsesLongPressModifier(key: .k9, existing: .action(.cue)),
    "detect a chord modifier assigned to a hold Action"
)
var longTargetProfile = OverCUEProfile.defaultValue
longTargetProfile.keyMap["K7"] = "unassigned"
let longTargetConflict = ActionMappingConflictDetector.conflict(
    for: .key(.k7),
    target: .action(.cue),
    profile: longTargetProfile,
    selectedGroup: 1
)
check(
    longTargetConflict?.kind == .longPressTargetUsesChord(
        chord: KeyChord(modifier: .k7, trigger: .k1),
        chordTarget: .action(.deleteHotCue3)
    ),
    "detect a hold Action assigned to an existing chord modifier"
)
var dialChordConflictProfile = OverCUEProfile.defaultValue
dialChordConflictProfile.dialChordMap["K7+DIAL_RIGHT"] = ActionID.toggleRekordboxMode.rawValue
let occupiedDialChord = DialChord(keys: [.k7], direction: .clockwise)!
check(
    ActionMappingConflictDetector.conflict(
        for: .dialChord(occupiedDialChord),
        target: .action(.cycleGroup),
        profile: dialChordConflictProfile,
        selectedGroup: 1
    )?.kind == .occupied(existing: .action(.toggleRekordboxMode)),
    "detect an existing key hold plus dial collision"
)
let longDialChord = DialChord(keys: [.k9], direction: .counterclockwise)!
check(
    ActionMappingConflictDetector.conflict(
        for: .dialChord(longDialChord),
        target: .action(.cycleGroup),
        profile: .defaultValue,
        selectedGroup: 1
    )?.kind == .dialChordUsesLongPressModifier(key: .k9, existing: .action(.cue)),
    "detect a held dial modifier assigned to a hold Action"
)

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
let version4Migration = ActionConfigurationMigrator.migrateToVersion4(legacyConfiguration)
check(version4Migration.configuration.version == 4, "migration updates configuration to version 4")
check(
    version4Migration.configuration.profiles["legacy"]?.dialMap["clockwise"] == "jog_search_right",
    "version 4 migration adds default clockwise Jog Search mapping"
)
check(
    OverCUEProfile.defaultValue.storedMapping(for: 1).rekordboxMode == .performance,
    "default group 1 uses Performance mode"
)
check(
    OverCUEProfile.defaultValue.storedMapping(for: 2).rekordboxMode == .performance,
    "default group 2 uses Performance mode"
)
check(
    OverCUEProfile.defaultValue.storedMapping(for: 1).rekordboxDeck == .deck1,
    "default group 1 targets Deck 1"
)
check(
    OverCUEProfile.defaultValue.storedMapping(for: 2).rekordboxDeck == .deck2,
    "default group 2 targets Deck 2"
)
check(
    OverCUEProfile.defaultValue.storedMapping(for: 2).keyMap["K10"] == "play_pause",
    "default group 2 uses the shared Play/Pause Action"
)
check(
    OverCUEProfile.defaultValue.storedMapping(for: 3).rekordboxMode == .export,
    "default group 3 uses Export mode"
)
check(
    OverCUEProfile.defaultValue.storedMapping(for: 1).dialChordMap["K7+DIAL_LEFT"]
        == ActionID.pitchBendDecrease.rawValue,
    "default group 1 uses the shared Pitch Bend minus Action"
)
check(
    OverCUEProfile.defaultValue.storedMapping(for: 2).dialChordMap["K7+DIAL_RIGHT"]
        == ActionID.pitchBendIncrease.rawValue,
    "default group 2 uses the shared Pitch Bend plus Action"
)
check(
    OverCUEProfile.defaultValue.storedMapping(for: 1).chordMap["K7+K2"]
        == ActionID.cycleGroup.rawValue,
    "default mapping cycles groups in ascending order with K7+K2"
)
check(
    OverCUEProfile.defaultValue.storedMapping(for: 1).chordMap["K7+K5"]
        == ActionID.cycleGroupBackward.rawValue,
    "default mapping cycles groups in descending order with K7+K5"
)

var previousDefaultProfile = OverCUEProfile.defaultValue
var previousGroup1 = previousDefaultProfile.storedMapping(for: 1)
previousGroup1.dialChordMap = [:]
previousGroup1.rekordboxMode = .export
previousGroup1.chordMap["K7+K2"] = ActionID.cycleGroup.rawValue
previousDefaultProfile.setMapping(previousGroup1, for: 1)
previousDefaultProfile.setMapping(OverCUEGroupMapping(rekordboxMode: .export), for: 2)
previousDefaultProfile.setMapping(OverCUEGroupMapping(rekordboxMode: .export), for: 3)
let version5Migration = ActionConfigurationMigrator.migrateToVersion5(
    OverCUEConfiguration(version: 4, profiles: ["default": previousDefaultProfile])
)
check(version5Migration.configuration.version == 5, "migration updates configuration to version 5")
check(
    version5Migration.configuration.profiles["default"]?.storedMapping(for: 1).rekordboxMode
        == .performance,
    "version 5 migration updates previous default group 1 mode"
)
check(
    version5Migration.configuration.profiles["default"]?.storedMapping(for: 1)
        .dialChordMap["K7+DIAL_RIGHT"] == ActionID.pitchBendIncrease.rawValue,
    "version 5 migration adds Deck 1 Pitch Bend mapping"
)
check(
    version5Migration.configuration.profiles["default"]?.storedMapping(for: 1)
        .chordMap["K7+K2"] == ActionID.cycleGroup.rawValue,
    "version 5 migration preserves custom group 1 mappings"
)
check(
    version5Migration.configuration.profiles["default"]?.storedMapping(for: 2)
        .keyMap["K10"] == "play_pause",
    "version 5 migration seeds Deck 2 defaults"
)
var previousVersion5Profile = version5Migration.configuration.profiles["default"]!
var previousVersion5Group1 = previousVersion5Profile.storedMapping(for: 1)
previousVersion5Group1.chordMap.removeValue(forKey: "K7+K5")
previousVersion5Profile.setMapping(previousVersion5Group1, for: 1)
let version6Migration = ActionConfigurationMigrator.migrateToVersion6(
    OverCUEConfiguration(version: 5, profiles: ["default": previousVersion5Profile])
)
check(version6Migration.configuration.version == 6, "migration updates configuration to version 6")
check(
    version6Migration.configuration.profiles["default"]?.storedMapping(for: 1)
        .chordMap["K7+K5"] == ActionID.cycleGroupBackward.rawValue,
    "version 6 migration adds descending group cycle"
)
var previousVersion6Profile = version6Migration.configuration.profiles["default"]!
previousVersion6Profile.waveformPosition = WaveformPosition(x: 12.5, y: 34.5)
var previousVersion6Group2 = previousVersion6Profile.storedMapping(for: 2)
previousVersion6Group2.waveformPosition = WaveformPosition(x: 56.5, y: 78.5)
previousVersion6Profile.setMapping(previousVersion6Group2, for: 2)
let version7Migration = ActionConfigurationMigrator.migrateToVersion7(
    OverCUEConfiguration(version: 6, profiles: ["default": previousVersion6Profile])
)
check(version7Migration.configuration.version == 7, "migration updates configuration to version 7")
check(
    version7Migration.configuration.profiles["default"]?.waveformPosition == nil,
    "version 7 migration removes the profile-wide waveform position"
)
check(
    version7Migration.configuration.profiles["default"]?.storedMapping(for: 1).waveformPosition
        == WaveformPosition(x: 12.5, y: 34.5),
    "version 7 migration copies the shared waveform position to group 1"
)
check(
    version7Migration.configuration.profiles["default"]?.storedMapping(for: 2).waveformPosition
        == WaveformPosition(x: 56.5, y: 78.5),
    "version 7 migration preserves an existing group waveform position"
)
check(
    version7Migration.configuration.profiles["default"]?.storedMapping(for: 4).waveformPosition
        == WaveformPosition(x: 12.5, y: 34.5),
    "version 7 migration copies the shared waveform position to every group"
)
let makeLegacyDeckMappings: ([String: String], RekordboxDeck) -> [String: String] = {
    mappings, deck in
    mappings.mapValues { value in
        guard let target = ActionTarget(configurationValue: value),
              let commandID = RekordboxActionAdapter.commandID(for: target, deck: deck)
        else { return value }
        return "rekordbox:\(commandID)"
    }
}
var legacyVersion7Profile = OverCUEProfile.defaultValue
for group in 1...4 {
    var mapping = legacyVersion7Profile.storedMapping(for: group)
    mapping.rekordboxDeck = nil
    legacyVersion7Profile.setMapping(mapping, for: group)
}
var legacyDeck2 = legacyVersion7Profile.storedMapping(for: 2)
legacyDeck2.keyMap = makeLegacyDeckMappings(legacyDeck2.keyMap, .deck2)
legacyDeck2.chordMap = makeLegacyDeckMappings(legacyDeck2.chordMap, .deck2)
legacyDeck2.dialChordMap = makeLegacyDeckMappings(legacyDeck2.dialChordMap, .deck2)
legacyVersion7Profile.setMapping(legacyDeck2, for: 2)
var explicitGenericProfile = OverCUEProfile(
    keyMap: ["K1": "rekordbox:42ff"],
    chordMap: [:],
    rekordboxMode: .performance
)
explicitGenericProfile.waveformPosition = nil
let version8Migration = ActionConfigurationMigrator.migrateToVersion8(
    OverCUEConfiguration(
        version: 7,
        profiles: ["default": legacyVersion7Profile, "generic": explicitGenericProfile]
    )
)
check(version8Migration.configuration.version == 8, "migration updates configuration to version 8")
check(
    version8Migration.configuration.profiles["default"]?.storedMapping(for: 2).rekordboxDeck
        == .deck2,
    "version 8 migration identifies the legacy default Deck 2 group"
)
check(
    version8Migration.configuration.profiles["default"]?.storedMapping(for: 2).keyMap["K10"]
        == ActionID.playPause.rawValue,
    "version 8 migration replaces legacy Deck 2 IDs with standard Actions"
)
check(
    version8Migration.configuration.profiles["default"]?.storedMapping(for: 3).rekordboxMode
        == .export,
    "version 8 migration preserves the existing EXPORT group"
)
check(
    version8Migration.configuration.profiles["default"]?.storedMapping(for: 2).waveformPosition
        == legacyDeck2.waveformPosition,
    "version 8 migration preserves group waveform coordinates"
)
check(
    version8Migration.configuration.profiles["generic"]?.storedMapping(for: 1).keyMap["K1"]
        == "rekordbox:42ff",
    "version 8 migration preserves explicit Generic command IDs"
)
var legacyDeviceConfiguration = version8Migration.configuration
legacyDeviceConfiguration.deviceProfiles = ["location:0012ABCD": "generic"]
let version9Migration = ActionConfigurationMigrator.migrateToCurrentVersion(
    legacyDeviceConfiguration
)
check(version9Migration.configuration.version == 9, "migration updates configuration to version 9")
check(
    version9Migration.configuration.logicalDevices["legacy:location:0012ABCD"]?.profileName
        == "generic",
    "version 9 migration creates a Logical Device for a legacy profile assignment"
)
check(
    version9Migration.configuration.physicalDeviceBindings.first
        == OverCUEPhysicalDeviceBinding(
            logicalDeviceID: "legacy:location:0012ABCD",
            kind: .ack05,
            vendorID: 0x28BD,
            productID: 0x0202,
            lastKnownLocationID: 0x0012ABCD,
            legacyDeviceIdentifier: "location:0012ABCD"
        ),
    "version 9 migration preserves a legacy ACK05 binding"
)
check(
    version9Migration.configuration.deviceProfiles.isEmpty,
    "version 9 migration removes the duplicated legacy device profile map"
)

let serialDevice = HIDPhysicalDeviceDescriptor(
    kind: .ack05,
    vendorID: 0x28BD,
    productID: 0x0202,
    serialNumber: "ACK05-A",
    locationID: 0x1000,
    transportIdentifier: "session-a"
)
let movedSerialDevice = HIDPhysicalDeviceDescriptor(
    kind: .ack05,
    vendorID: 0x28BD,
    productID: 0x0202,
    serialNumber: "ACK05-A",
    locationID: 0x2000,
    transportIdentifier: "session-b"
)
let serialBinding = OverCUEPhysicalDeviceBinding(
    logicalDeviceID: "deck-a",
    kind: .ack05,
    vendorID: 0x28BD,
    productID: 0x0202,
    serialNumber: "ACK05-A",
    lastKnownLocationID: 0x1000
)
check(serialBinding.matches(serialDevice), "match a Physical Device by VID PID and Serial")
check(serialBinding.matches(movedSerialDevice), "preserve binding when a serial device changes USB port")
let locationOnlyBinding = OverCUEPhysicalDeviceBinding(
    logicalDeviceID: "deck-b",
    kind: .ack05,
    vendorID: 0x28BD,
    productID: 0x0202,
    lastKnownLocationID: 0x1000
)
check(!locationOnlyBinding.matches(serialDevice), "do not treat USB location as persistent identity")
check(locationOnlyBinding.isLocationHint(for: serialDevice), "use USB location only as a rebind hint")
var logicalConfiguration = OverCUEConfiguration.defaultValue
logicalConfiguration.profiles["alternate"] = .defaultValue
logicalConfiguration.logicalDevices["deck-a"] = OverCUELogicalDevice(
    name: "Deck A Main",
    profileName: "alternate"
)
logicalConfiguration.physicalDeviceBindings = [serialBinding]
check(
    logicalConfiguration.profileName(for: movedSerialDevice) == "alternate",
    "resolve Physical Device through Logical Device to Profile"
)
let unregisteredDevice = HIDPhysicalDeviceDescriptor(
    kind: .ack05,
    vendorID: 0x28BD,
    productID: 0x0202,
    locationID: 0x3000,
    transportIdentifier: "session-c"
)
check(
    logicalConfiguration.profileName(for: unregisteredDevice) == logicalConfiguration.defaultProfile,
    "use the default Profile without registering an unknown Physical Device"
)

var inputStates = DeviceScopedStateStore<InputActionResolver>()
let isolatedMapping = ActionMapping(keys: [.k1: .cue], chords: [:])
inputStates.withState(for: "ack05-a", create: InputActionResolver.init) { resolver in
    _ = resolver.handle(pressedKeys: [.k1], mapping: isolatedMapping)
}
let secondDeviceKeys = inputStates.withState(
    for: "ack05-b",
    create: InputActionResolver.init
) { $0.pressedKeys }
let firstDeviceKeys = inputStates.withState(
    for: "ack05-a",
    create: InputActionResolver.init
) { $0.pressedKeys }
check(secondDeviceKeys.isEmpty, "keep the second ACK05 key state independent")
check(firstDeviceKeys == [.k1], "retain the first ACK05 key state independently")
check(inputStates.count == 2, "store one input state per Physical Device")
inputStates.removeState(for: "ack05-a")
check(inputStates.count == 1, "remove only the disconnected Physical Device state")
var globalGroupProfile = OverCUEProfile.defaultValue
globalGroupProfile.chordMap["K7+K8+K1"] = ActionID.cycleGroup.rawValue
check(
    globalGroupProfile.mapping(for: 3).chordMap["K7+K8+K1"] == ActionID.cycleGroup.rawValue,
    "group cycle mapping is inherited by every group"
)
check(
    globalGroupProfile.storedMapping(for: 3).chordMap["K7+K8+K1"] == nil,
    "inherited group cycle mapping is not duplicated in stored group maps"
)
let stableVersion3 = OverCUEConfiguration(
    version: 3,
    profiles: [
        "default": OverCUEProfile(keyMap: ["K1": "rekordbox:42ff"], chordMap: [:]),
    ]
)
check(
    ActionConfigurationMigrator.migrateToVersion4(stableVersion3)
        .configuration.profiles["default"]?.keyMap["K1"] == "rekordbox:42ff",
    "version 4 migration preserves generic rekordbox targets"
)

let heldDialChord = DialChord(keys: [.k7], direction: .clockwise)!
let heldDialMapping = ActionMapping(
    keys: [.k7: .quantize],
    chords: [:],
    dialChords: [heldDialChord: .toggleRekordboxMode]
)
var heldDialResolver = InputActionResolver()
check(
    heldDialResolver.handle(pressedKeys: [.k7], mapping: heldDialMapping).isEmpty,
    "key used by a dial chord is deferred while held"
)
check(
    heldDialResolver.dialEvent(for: .clockwise, mapping: heldDialMapping)?.action
        == .toggleRekordboxMode,
    "held key plus dial resolves an Action"
)
check(
    heldDialResolver.handle(pressedKeys: [], mapping: heldDialMapping).isEmpty,
    "dial chord suppresses the held key standalone Action"
)

do {
    let legacyGroupJSON = Data("""
    {"keyMap":{"K1":"hot_cue_1"},"chordMap":{},"dialMap":{}}
    """.utf8)
    let group = try JSONDecoder().decode(OverCUEGroupMapping.self, from: legacyGroupJSON)
    check(group.dialChordMap.isEmpty, "decode group mapping without dialChordMap")
    check(group.rekordboxMode == nil, "decode group mapping without rekordboxMode")
    check(group.rekordboxDeck == nil, "decode group mapping without rekordboxDeck")

    let invalidDeckJSON = Data("""
    {"keyMap":{},"chordMap":{},"dialMap":{},"rekordboxDeck":5}
    """.utf8)
    do {
        _ = try JSONDecoder().decode(OverCUEGroupMapping.self, from: invalidDeckJSON)
        check(false, "reject target Deck outside 1 through 4")
    } catch {
        check(true, "reject target Deck outside 1 through 4")
    }
} catch {
    failureCount += 1
    fputs("FAIL: unexpected legacy group mapping error: \(error)\n", stderr)
}

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
let k7Report: [UInt8] = [6, 1, 0x16, 0, 0, 0, 0, 0]
check(
    decoder.pressedKeys(reportID: 6, bytes: k7Report, previousKeys: []) == [.k7],
    "decode initial K7 press"
)
check(
    decoder.pressedKeys(reportID: 6, bytes: k7Report, previousKeys: [.k7]) == [.k7, .k5],
    "infer K5 added after K7 from a duplicate HID report"
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
    decoder.pressedKeys(
        reportID: 6,
        bytes: [6, 1, 0x16, 0x1D, 0x12, 0, 0, 0],
        previousKeys: [.k7, .k8]
    ) == [.k7, .k8, .k1],
    "decode three simultaneously pressed keys"
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
        RekordboxShortcutCategory.category(for: "3206") == .deck3,
        "categorize Deck 3 shortcut"
    )
    check(
        RekordboxShortcutCategory.category(for: "3306") == .deck4,
        "categorize Deck 4 shortcut"
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
    <PROPERTIES>
      <VALUE name="performanceKeyMapping" val="1234567890123"/>
      <VALUE name="exportKeyMapping" val="9876543210123"/>
    </PROPERTIES>
    """
    let settings = try RekordboxSettings.parse(data: Data(settingsXML.utf8))
    check(settings.performanceKeyMappingID == "1234567890123", "parse selected Performance mapping")
    check(settings.exportKeyMappingID == "9876543210123", "parse selected Export mapping when available")

    let functionShortcut = try RekordboxKeyboardShortcut(rawValue: "command+F10")
    check(functionShortcut.keyCode == 109, "parse F10 key code without spacing around separators")
    check(functionShortcut.modifiers == [.command], "parse command modifier for F10")
    let symbolShortcut = try RekordboxKeyboardShortcut(rawValue: "shift + >")
    check(symbolShortcut.keyCode == 47, "parse symbol shortcut from rekordbox preset")
    check(symbolShortcut.modifiers == [.shift], "parse symbol shortcut modifier")
} catch {
    failureCount += 1
    fputs("FAIL: unexpected rekordbox XML parsing error: \(error)\n", stderr)
}

do {
    let temporaryHome = FileManager.default.temporaryDirectory
        .appendingPathComponent("overcue-loader-\(UUID().uuidString)")
    let baseURL = temporaryHome
        .appendingPathComponent("Library/Application Support/Pioneer/rekordbox7")
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
        to: mappingsURL.appendingPathComponent("rekordbox_4567890123456.mappings")
    )

    let loader = RekordboxKeyMappingLoader(homeDirectory: temporaryHome)
    check(loader.baseURL.lastPathComponent == "rekordbox7", "discover versioned rekordbox settings directory")
    let performance = try loader.load(mode: .performance)
    check(performance.mappingID == "1234567890123", "load selected Performance mapping ID")
    check(performance.mapping.name == "Loader Test", "load selected Performance mapping XML")
    check(performance.mapping.entries.count == 1, "load Performance shortcut entries")
    let export = try loader.load(mode: .export)
    check(export.mappingID == "4567890123456", "discover Export mapping ID from mapping contents")
    check(export.mapping.name == "Export Loader Test", "load discovered Export mapping XML")
    check(export.mapping.entries.count == 2, "load distinct Export shortcut entries")
} catch {
    failureCount += 1
    fputs("FAIL: unexpected rekordbox mapping loader error: \(error)\n", stderr)
}

do {
    var configuration = OverCUEConfiguration.defaultValue
    configuration.profiles["default"]?.keyMap["K1"] = "hot_cue_1"
    configuration.profiles["alternate"] = OverCUEProfile.defaultValue
    var group2 = configuration.profiles["default"]!.storedMapping(for: 2)
    group2.rekordboxMode = .performance
    group2.rekordboxDeck = .deck3
    group2.waveformPosition = WaveformPosition(x: 840.5, y: 312.25)
    configuration.profiles["default"]!.setMapping(group2, for: 2)
    var group1 = configuration.profiles["default"]!.storedMapping(for: 1)
    group1.waveformPosition = WaveformPosition(x: 640.5, y: 212.25)
    configuration.profiles["default"]!.setMapping(group1, for: 1)
    configuration.logicalDevices["deck-a"] = OverCUELogicalDevice(
        name: "Deck A Main",
        profileName: "alternate"
    )
    configuration.physicalDeviceBindings = [serialBinding]
    let data = try JSONEncoder().encode(configuration)
    let decoded = try JSONDecoder().decode(OverCUEConfiguration.self, from: data)
    check(decoded == configuration, "round-trip external configuration")
    check(decoded.version == 9, "persist profile configuration version")
    check(
        decoded.profiles["default"]?.storedMapping(for: 1).waveformPosition
            == WaveformPosition(x: 640.5, y: 212.25),
        "persist group 1 waveform position"
    )
    check(
        decoded.profiles["default"]?.storedMapping(for: 2).waveformPosition
            == WaveformPosition(x: 840.5, y: 312.25),
        "persist group 2 waveform position independently"
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
    check(
        decoded.profiles["default"]?.dialMap["clockwise"] == "jog_search_right",
        "persist clockwise dial mapping"
    )
    check(
        decoded.logicalDevices["deck-a"]?.profileName == "alternate",
        "persist Logical Device profile assignment"
    )
    check(
        decoded.physicalDeviceBindings == [serialBinding],
        "persist Physical Device binding independently"
    )
    check(
        decoded.profiles["default"]?.mapping(for: 2).rekordboxMode == .performance,
        "persist rekordbox mode independently for group 2"
    )
    check(
        decoded.profiles["default"]?.mapping(for: 2).rekordboxDeck == .deck3,
        "persist target Deck independently for group 2"
    )
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

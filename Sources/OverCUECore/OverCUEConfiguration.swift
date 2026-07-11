import Foundation

public struct WaveformPosition: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct OverCUEProfile: Codable, Equatable, Sendable {
    public var waveformPosition: WaveformPosition?
    public var keyMap: [String: String]
    public var chordMap: [String: String]

    public init(
        waveformPosition: WaveformPosition? = nil,
        keyMap: [String: String],
        chordMap: [String: String]
    ) {
        self.waveformPosition = waveformPosition
        self.keyMap = keyMap
        self.chordMap = chordMap
    }

    public static let defaultValue = OverCUEProfile(
        keyMap: [
            "K1": "hot_cue_3",
            "K2": "delete_memory_cue",
            "K3": "jump_forward",
            "K4": "hot_cue_2",
            "K5": "set_memory_cue",
            "K6": "jump_backward",
            "K7": "quantize",
            "K8": "hot_cue_1",
            "K9": "cue",
            "K10": "play_pause",
        ],
        chordMap: [
            "K8+K1": "capture_waveform_position",
            "K7+K8": "delete_hot_cue_1",
            "K7+K4": "delete_hot_cue_2",
            "K7+K1": "delete_hot_cue_3",
            "K7+K3": "call_next_memory_cue",
            "K7+K6": "call_previous_memory_cue",
        ]
    )
}

public struct OverCUEConfiguration: Codable, Equatable, Sendable {
    public var version: Int
    public var defaultProfile: String
    public var profiles: [String: OverCUEProfile]
    public var deviceProfiles: [String: String]

    public init(
        version: Int = 3,
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

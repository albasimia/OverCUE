using System.Text.Json;
using System.Text.Json.Serialization;

namespace OverCUE.Core;

public sealed record WaveformPosition(double X, double Y);

public sealed class OverCUEGroupMapping
{
    [JsonPropertyName("waveformPosition")] public WaveformPosition? WaveformPosition { get; set; }
    [JsonPropertyName("keyMap")] public Dictionary<string, string> KeyMap { get; set; } = [];
    [JsonPropertyName("chordMap")] public Dictionary<string, string> ChordMap { get; set; } = [];
    [JsonPropertyName("dialMap")] public Dictionary<string, string> DialMap { get; set; } = [];
    [JsonPropertyName("dialChordMap")] public Dictionary<string, string> DialChordMap { get; set; } = [];
    [JsonPropertyName("rekordboxMode")] public string RekordboxMode { get; set; } = "performance";

    public ActionMapping ToActionMapping()
    {
        var result = new ActionMapping();
        foreach (var (rawKey, rawTarget) in KeyMap)
            if (Enum.TryParse<ACK05Key>(rawKey, true, out var key) && ActionTarget.Parse(rawTarget) is { } target)
                result.Keys[key] = target;
        foreach (var (rawChord, rawTarget) in ChordMap)
            if (ParseKeys(rawChord) is { Length: >= 2 } keys && ActionTarget.Parse(rawTarget) is { } target)
                result.Chords[new KeyChord(keys)] = target;
        foreach (var (rawDirection, rawTarget) in DialMap)
            if (Enum.TryParse<DialDirection>(rawDirection, true, out var direction) && ActionTarget.Parse(rawTarget) is { } target)
                result.Dial[direction] = target;
        foreach (var (rawChord, rawTarget) in DialChordMap)
        {
            var parts = rawChord.Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
            var dialPart = parts.LastOrDefault();
            var direction = dialPart?.Equals("DIAL_RIGHT", StringComparison.OrdinalIgnoreCase) == true
                ? DialDirection.Clockwise : dialPart?.Equals("DIAL_LEFT", StringComparison.OrdinalIgnoreCase) == true
                    ? DialDirection.Counterclockwise : (DialDirection?)null;
            var keys = ParseKeys(string.Join('+', parts.SkipLast(1)));
            if (direction is { } value && keys is { Length: > 0 } && ActionTarget.Parse(rawTarget) is { } target)
                result.DialChords[new DialChord(keys, value)] = target;
        }
        return result;
    }

    private static ACK05Key[]? ParseKeys(string value)
    {
        var keys = new List<ACK05Key>();
        foreach (var part in value.Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
        {
            if (!Enum.TryParse<ACK05Key>(part, true, out var key)) return null;
            keys.Add(key);
        }
        return keys.Distinct().Count() == keys.Count ? keys.ToArray() : null;
    }
}

public sealed class OverCUEProfile
{
    [JsonPropertyName("groupMappings")] public Dictionary<string, OverCUEGroupMapping> GroupMappings { get; set; } = [];
    public OverCUEGroupMapping Mapping(int group)
    {
        var result = GroupMappings.GetValueOrDefault(group.ToString()) ?? new();
        if (group == 1 || !GroupMappings.TryGetValue("1", out var global)) return result;
        CopyGroupCycleActions(global.KeyMap, result.KeyMap);
        CopyGroupCycleActions(global.ChordMap, result.ChordMap);
        CopyGroupCycleActions(global.DialMap, result.DialMap);
        CopyGroupCycleActions(global.DialChordMap, result.DialChordMap);
        return result;
    }

    private static void CopyGroupCycleActions(Dictionary<string, string> source, Dictionary<string, string> destination)
    {
        foreach (var (input, action) in source)
            if (action is "cycle_group" or "cycle_group_backward") destination[input] = action;
    }
}

public sealed class OverCUEConfiguration
{
    public const int CurrentVersion = 7;
    [JsonPropertyName("version")] public int Version { get; set; } = CurrentVersion;
    [JsonPropertyName("defaultProfile")] public string DefaultProfile { get; set; } = "default";
    [JsonPropertyName("profiles")] public Dictionary<string, OverCUEProfile> Profiles { get; set; } = [];
    [JsonPropertyName("deviceProfiles")] public Dictionary<string, string> DeviceProfiles { get; set; } = [];

    public static OverCUEConfiguration CreateDefault() => new()
    {
        Profiles = new() { ["default"] = new() { GroupMappings = DefaultGroups() } },
    };

    public static OverCUEConfiguration Load(string path)
    {
        if (!File.Exists(path)) { var created = CreateDefault(); created.Save(path); return created; }
        var value = JsonSerializer.Deserialize<OverCUEConfiguration>(File.ReadAllText(path), JsonOptions)
            ?? throw new InvalidDataException("OverCUE configuration is empty.");
        if (value.Version != CurrentVersion) throw new InvalidDataException($"Unsupported configuration version {value.Version}.");
        MigrateGeneratedWindowsDefaults(value);
        return value;
    }

    public void Save(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path) ?? ".");
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(this, JsonOptions));
        File.Move(temporary, path, true);
    }

    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    private static void MigrateGeneratedWindowsDefaults(OverCUEConfiguration configuration)
    {
        if (!configuration.Profiles.TryGetValue(configuration.DefaultProfile, out var profile)) return;
        if (profile.GroupMappings.TryGetValue("1", out var first)
            && first.KeyMap.Count == 10 && first.ChordMap.Count == 6
            && first.KeyMap.GetValueOrDefault("K1") == "hot_cue_3"
            && first.KeyMap.GetValueOrDefault("K10") == "play_pause")
        {
            first.ChordMap["K7+K2"] = "cycle_group";
            first.ChordMap["K7+K5"] = "cycle_group_backward";
        }
        if (profile.GroupMappings.TryGetValue("2", out var second)
            && second.KeyMap.Count == 10 && second.ChordMap.Count == 6
            && second.KeyMap.GetValueOrDefault("K1") == "hot_cue_3"
            && second.KeyMap.GetValueOrDefault("K10") == "play_pause")
            profile.GroupMappings["2"] = DeckTwoGroup();
    }

    private static Dictionary<string, OverCUEGroupMapping> DefaultGroups() => new()
    {
        ["1"] = DefaultGroup("performance"),
        ["2"] = DeckTwoGroup(),
        ["3"] = DefaultGroup("export"),
        ["4"] = new() { RekordboxMode = "export" },
    };

    private static OverCUEGroupMapping DefaultGroup(string mode)
    {
        var group = new OverCUEGroupMapping
        {
            RekordboxMode = mode,
            KeyMap = new() { ["K1"]="hot_cue_3", ["K2"]="delete_memory_cue", ["K3"]="jump_forward",
                ["K4"]="hot_cue_2", ["K5"]="set_memory_cue", ["K6"]="jump_backward", ["K7"]="quantize",
                ["K8"]="hot_cue_1", ["K9"]="cue", ["K10"]="play_pause" },
            ChordMap = new() { ["K8+K1"]="capture_waveform_position", ["K7+K8"]="delete_hot_cue_1",
                ["K7+K4"]="delete_hot_cue_2", ["K7+K1"]="delete_hot_cue_3", ["K7+K3"]="call_next_memory_cue",
                ["K7+K6"]="call_previous_memory_cue", ["K7+K2"]="cycle_group",
                ["K7+K5"]="cycle_group_backward" },
            DialMap = new() { ["counterclockwise"]="jog_search_left", ["clockwise"]="jog_search_right" },
            DialChordMap = new() { ["K7+DIAL_LEFT"]="rekordbox:3050", ["K7+DIAL_RIGHT"]="rekordbox:304f" },
        };
        return group;
    }

    private static OverCUEGroupMapping DeckTwoGroup() => new()
    {
        RekordboxMode = "performance",
        KeyMap = new() { ["K1"]="rekordbox:3120", ["K2"]="rekordbox:313b", ["K3"]="rekordbox:3108",
            ["K4"]="rekordbox:311f", ["K5"]="rekordbox:3124", ["K6"]="rekordbox:3109",
            ["K7"]="rekordbox:311c", ["K8"]="rekordbox:311e", ["K9"]="rekordbox:3107",
            ["K10"]="rekordbox:3106" },
        ChordMap = new() { ["K8+K1"]="capture_waveform_position", ["K7+K8"]="rekordbox:3121",
            ["K7+K4"]="rekordbox:3122", ["K7+K1"]="rekordbox:3123", ["K7+K3"]="rekordbox:3139",
            ["K7+K6"]="rekordbox:313a" },
        DialMap = new() { ["counterclockwise"]="jog_search_left", ["clockwise"]="jog_search_right" },
        DialChordMap = new() { ["K7+DIAL_LEFT"]="rekordbox:3150", ["K7+DIAL_RIGHT"]="rekordbox:314f" },
    };
}

public static class RekordboxActionAdapter
{
    public static string? CommandID(ActionTarget target) => target.RekordboxCommandID ?? target.Action switch
    {
        ActionID.HotCue1 => "301e", ActionID.HotCue2 => "301f", ActionID.HotCue3 => "3020",
        ActionID.DeleteHotCue1 => "3021", ActionID.DeleteHotCue2 => "3022", ActionID.DeleteHotCue3 => "3023",
        ActionID.SetMemoryCue => "3024", ActionID.DeleteMemoryCue => "303b", ActionID.CallNextMemoryCue => "3039",
        ActionID.CallPreviousMemoryCue => "303a", ActionID.JumpForward => "3008", ActionID.JumpBackward => "3009",
        ActionID.Quantize => "301c", ActionID.Cue => "3007", ActionID.PlayPause => "3006", _ => null,
    };
}

namespace OverCUE.Core;

public enum ActionID
{
    HotCue1, HotCue2, HotCue3, DeleteHotCue1, DeleteHotCue2, DeleteHotCue3,
    SetMemoryCue, DeleteMemoryCue, CallNextMemoryCue, CallPreviousMemoryCue,
    JumpForward, JumpBackward, Quantize, Cue, PlayPause, CaptureWaveformPosition,
    JogSearchLeft, JogSearchRight, CycleGroup, CycleGroupBackward, ToggleRekordboxMode,
}

public enum ActionBehavior { Trigger, Hold, AcceleratingRepeat, InternalCommand }
public enum ActionPhase { Triggered, Pressed, Released, Repeated }

public static class ActionMetadata
{
    public static ActionBehavior Behavior(this ActionID action) => action switch
    {
        ActionID.Cue => ActionBehavior.Hold,
        ActionID.JumpForward or ActionID.JumpBackward => ActionBehavior.AcceleratingRepeat,
        ActionID.CaptureWaveformPosition or ActionID.JogSearchLeft or ActionID.JogSearchRight
            or ActionID.CycleGroup or ActionID.CycleGroupBackward or ActionID.ToggleRekordboxMode
            => ActionBehavior.InternalCommand,
        _ => ActionBehavior.Trigger,
    };

    public static string ConfigurationValue(this ActionID action) => action switch
    {
        ActionID.HotCue1 => "hot_cue_1", ActionID.HotCue2 => "hot_cue_2", ActionID.HotCue3 => "hot_cue_3",
        ActionID.DeleteHotCue1 => "delete_hot_cue_1", ActionID.DeleteHotCue2 => "delete_hot_cue_2",
        ActionID.DeleteHotCue3 => "delete_hot_cue_3", ActionID.SetMemoryCue => "set_memory_cue",
        ActionID.DeleteMemoryCue => "delete_memory_cue", ActionID.CallNextMemoryCue => "call_next_memory_cue",
        ActionID.CallPreviousMemoryCue => "call_previous_memory_cue", ActionID.JumpForward => "jump_forward",
        ActionID.JumpBackward => "jump_backward", ActionID.Quantize => "quantize", ActionID.Cue => "cue",
        ActionID.PlayPause => "play_pause", ActionID.CaptureWaveformPosition => "capture_waveform_position",
        ActionID.JogSearchLeft => "jog_search_left", ActionID.JogSearchRight => "jog_search_right",
        ActionID.CycleGroup => "cycle_group", ActionID.CycleGroupBackward => "cycle_group_backward",
        ActionID.ToggleRekordboxMode => "toggle_rekordbox_mode", _ => throw new ArgumentOutOfRangeException(nameof(action)),
    };

    public static ActionID? ParseAction(string value) => Enum.GetValues<ActionID>()
        .Cast<ActionID?>().FirstOrDefault(action => action!.Value.ConfigurationValue() == value);
}

public sealed record ActionTarget(ActionID? Action, string? RekordboxCommandID)
{
    public static ActionTarget ForAction(ActionID action) => new(action, null);
    public static ActionTarget? Parse(string value) => ActionMetadata.ParseAction(value) is { } action
        ? ForAction(action)
        : value.StartsWith("rekordbox:", StringComparison.Ordinal) && value.Length > 10
            ? new(null, value[10..]) : null;
    public ActionBehavior Behavior => Action?.Behavior() ?? RekordboxCommandID switch
    {
        "3007" or "3107" => ActionBehavior.Hold,
        "3008" or "3009" or "3108" or "3109" => ActionBehavior.AcceleratingRepeat,
        _ => ActionBehavior.Trigger,
    };
}

public sealed record ActionEvent(ActionTarget Target, ActionPhase Phase, ACK05Key? SourceKey, string SourceLabel);

public sealed class KeyChord : IEquatable<KeyChord>
{
    public IReadOnlyList<ACK05Key> Keys { get; }
    public ACK05Key Trigger => Keys[^1];
    public IEnumerable<ACK05Key> Modifiers => Keys.Take(Keys.Count - 1);
    public string Label => string.Join("+", Keys.Select(key => key.ToString().ToUpperInvariant()));
    public KeyChord(IEnumerable<ACK05Key> keys)
    {
        Keys = keys.ToArray();
        if (Keys.Count < 2 || Keys.Distinct().Count() != Keys.Count) throw new ArgumentException("Invalid chord.");
    }
    public bool Equals(KeyChord? other) => other is not null && Keys.SequenceEqual(other.Keys);
    public override bool Equals(object? obj) => Equals(obj as KeyChord);
    public override int GetHashCode() => Keys.Aggregate(17, (hash, key) => HashCode.Combine(hash, key));
}

public sealed record DialChord(IReadOnlyList<ACK05Key> Keys, DialDirection Direction)
{
    public string Label => string.Join("+", Keys.Select(key => key.ToString().ToUpperInvariant())
        .Append(Direction == DialDirection.Clockwise ? "DIAL_RIGHT" : "DIAL_LEFT"));
}

public sealed class ActionMapping
{
    public Dictionary<ACK05Key, ActionTarget> Keys { get; } = [];
    public Dictionary<KeyChord, ActionTarget> Chords { get; } = [];
    public Dictionary<DialDirection, ActionTarget> Dial { get; } = [];
    public Dictionary<DialChord, ActionTarget> DialChords { get; } = [];
    public HashSet<ACK05Key> ModifierKeys => Chords.Keys.SelectMany(chord => chord.Modifiers)
        .Concat(DialChords.Keys.SelectMany(chord => chord.Keys)).ToHashSet();

    public bool HasCommand(IEnumerable<ACK05Key> keys, string commandID) => keys.Any(key =>
        Keys.TryGetValue(key, out var target)
        && RekordboxActionAdapter.CommandID(target)?.Equals(commandID, StringComparison.OrdinalIgnoreCase) == true);
}

public sealed class InputActionResolver
{
    public HashSet<ACK05Key> PressedKeys { get; } = [];
    private readonly HashSet<ACK05Key> usedChordModifiers = [];
    private readonly HashSet<ACK05Key> suppressedChordTriggers = [];
    private readonly HashSet<ACK05Key> activeHoldKeys = [];

    public IReadOnlyList<ActionEvent> Handle(IEnumerable<ACK05Key> nextKeys, ActionMapping mapping)
    {
        var next = nextKeys.ToHashSet();
        var newlyPressed = next.Except(PressedKeys).ToHashSet();
        var released = PressedKeys.Except(next).ToHashSet();
        var events = new List<ActionEvent>();
        var consumedTriggers = new HashSet<ACK05Key>();

        foreach (var chord in mapping.Chords.Keys.OrderByDescending(value => value.Keys.Count).ThenBy(value => value.Label))
        {
            if (!newlyPressed.Contains(chord.Trigger) || !chord.Keys.All(next.Contains)
                || !consumedTriggers.Add(chord.Trigger)) continue;
            events.Add(new(mapping.Chords[chord], ActionPhase.Triggered, chord.Trigger, chord.Label));
            usedChordModifiers.UnionWith(chord.Modifiers);
            suppressedChordTriggers.Add(chord.Trigger);
        }

        foreach (var key in Enum.GetValues<ACK05Key>().Where(newlyPressed.Contains))
        {
            if (mapping.ModifierKeys.Contains(key) || suppressedChordTriggers.Contains(key)
                || !mapping.Keys.TryGetValue(key, out var target)) continue;
            var phase = target.Behavior is ActionBehavior.Hold or ActionBehavior.AcceleratingRepeat
                ? ActionPhase.Pressed : ActionPhase.Triggered;
            events.Add(Event(target, phase, key));
            if (target.Behavior == ActionBehavior.Hold) activeHoldKeys.Add(key);
        }

        foreach (var key in released.Where(activeHoldKeys.Remove))
            if (mapping.Keys.TryGetValue(key, out var target)) events.Add(Event(target, ActionPhase.Released, key));

        foreach (var key in released.Where(mapping.ModifierKeys.Contains))
            if (!usedChordModifiers.Contains(key) && !suppressedChordTriggers.Contains(key)
                && mapping.Keys.TryGetValue(key, out var target)) events.Add(Event(target, ActionPhase.Triggered, key));

        usedChordModifiers.ExceptWith(released);
        suppressedChordTriggers.ExceptWith(released);
        PressedKeys.Clear(); PressedKeys.UnionWith(next);
        return events;
    }

    public ActionEvent? RepeatedEvent(ACK05Key key, ActionMapping mapping) =>
        PressedKeys.Contains(key) && mapping.Keys.TryGetValue(key, out var target)
            && target.Behavior == ActionBehavior.AcceleratingRepeat ? Event(target, ActionPhase.Repeated, key) : null;

    public ActionEvent? DialEvent(DialDirection direction, ActionMapping mapping)
    {
        var chord = mapping.DialChords.Keys.Where(value => value.Direction == direction && value.Keys.All(PressedKeys.Contains))
            .OrderByDescending(value => value.Keys.Count).ThenBy(value => value.Label).FirstOrDefault();
        if (chord is not null) { usedChordModifiers.UnionWith(chord.Keys); return new(mapping.DialChords[chord], ActionPhase.Triggered, null, chord.Label); }
        return mapping.Dial.TryGetValue(direction, out var target)
            ? new(target, ActionPhase.Triggered, null, direction.ToString()) : null;
    }

    public IReadOnlyList<ActionEvent> Reset(ActionMapping mapping)
    {
        var releases = activeHoldKeys.Where(mapping.Keys.ContainsKey)
            .Select(key => Event(mapping.Keys[key], ActionPhase.Released, key)).ToArray();
        PressedKeys.Clear(); usedChordModifiers.Clear(); suppressedChordTriggers.Clear(); activeHoldKeys.Clear();
        return releases;
    }

    private static ActionEvent Event(ActionTarget target, ActionPhase phase, ACK05Key key) =>
        new(target, phase, key, key.ToString().ToUpperInvariant());
}

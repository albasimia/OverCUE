namespace OverCUE.Core;

public readonly record struct RawKeyboardEvent(
    DateTimeOffset Timestamp,
    ushort VirtualKey,
    ushort MakeCode,
    bool IsKeyDown);

public sealed class ACK05KeyboardDecoder
{
    private const ushort Shift = 0x10;
    private const ushort Control = 0x11;
    private const ushort Alt = 0x12;
    private readonly TimeSpan chordGrace;
    private readonly Dictionary<ushort, ModifierState> modifiers = new();
    private readonly HashSet<ushort> pressedKeys = new();

    public ACK05KeyboardDecoder(TimeSpan? chordGrace = null)
    {
        this.chordGrace = chordGrace ?? TimeSpan.FromMilliseconds(30);
    }

    public IReadOnlyList<ACK05Event> Process(RawKeyboardEvent input)
    {
        var results = Flush(input.Timestamp).ToList();
        if (IsModifier(input.VirtualKey))
        {
            ProcessModifier(input);
            return results;
        }

        if (input.IsKeyDown)
        {
            if (!pressedKeys.Add(input.VirtualKey))
            {
                return results;
            }
        }
        else
        {
            pressedKeys.Remove(input.VirtualKey);
        }

        var decoded = Decode(input.VirtualKey, input.IsKeyDown, input.Timestamp);
        if (decoded is not null)
        {
            MarkActiveModifiersUsed(input.Timestamp);
            results.Add(decoded);
        }

        return results;
    }

    public IReadOnlyList<ACK05Event> Flush(DateTimeOffset timestamp)
    {
        var results = new List<ACK05Event>();
        foreach (var (virtualKey, state) in modifiers.ToArray())
        {
            if (state.ReleasedAt is not { } releasedAt || timestamp - releasedAt < chordGrace)
            {
                continue;
            }

            if (!state.Used && ModifierAction(virtualKey) is { } action)
            {
                results.Add(new ACK05Event.KeyDown(action));
            }

            modifiers.Remove(virtualKey);
        }

        return results;
    }

    public void Reset()
    {
        modifiers.Clear();
        pressedKeys.Clear();
    }

    private void ProcessModifier(RawKeyboardEvent input)
    {
        if (input.IsKeyDown)
        {
            modifiers[input.VirtualKey] = new ModifierState(true, false, null);
            return;
        }

        if (modifiers.TryGetValue(input.VirtualKey, out var state))
        {
            modifiers[input.VirtualKey] = state with { Down = false, ReleasedAt = input.Timestamp };
        }
    }

    private ACK05Event? Decode(ushort virtualKey, bool isKeyDown, DateTimeOffset timestamp)
    {
        var control = HasModifier(Control, timestamp);
        var shift = HasModifier(Shift, timestamp);
        var alt = HasModifier(Alt, timestamp);

        if (virtualKey == 0x4E && !isKeyDown && control && !shift && !alt)
        {
            return new ACK05Event.KeyDown(ACK05Key.K2);
        }

        if (!isKeyDown)
        {
            return null;
        }

        return (virtualKey, control, shift, alt) switch
        {
            (0x7C, false, false, false) => new ACK05Event.KeyDown(ACK05Key.K1),
            (0x7D, false, false, false) => new ACK05Event.KeyDown(ACK05Key.K2),
            (0x7E, false, false, false) => new ACK05Event.KeyDown(ACK05Key.K3),
            (0x7F, false, false, false) => new ACK05Event.KeyDown(ACK05Key.K4),
            (0x80, false, false, false) => new ACK05Event.KeyDown(ACK05Key.K5),
            (0x81, false, false, false) => new ACK05Event.KeyDown(ACK05Key.K6),
            (0x82, false, false, false) => new ACK05Event.KeyDown(ACK05Key.K7),
            (0x83, false, false, false) => new ACK05Event.KeyDown(ACK05Key.K8),
            (0x84, false, false, false) => new ACK05Event.KeyDown(ACK05Key.K9),
            (0x85, false, false, false) => new ACK05Event.KeyDown(ACK05Key.K10),
            (0x86, false, false, false) => new ACK05Event.Dial(DialDirection.Counterclockwise),
            (0x87, false, false, false) => new ACK05Event.Dial(DialDirection.Clockwise),
            (0x4F, true, false, false) => new ACK05Event.KeyDown(ACK05Key.K1),
            (0x4E, true, false, false) => new ACK05Event.KeyDown(ACK05Key.K2),
            (0x74, false, false, false) => new ACK05Event.KeyDown(ACK05Key.K3),
            (0x53, true, false, false) => new ACK05Event.KeyDown(ACK05Key.K7),
            (0x5A, true, false, false) => new ACK05Event.KeyDown(ACK05Key.K8),
            (0x20, false, false, false) => new ACK05Event.KeyDown(ACK05Key.K9),
            (0x5A, true, true, false) => new ACK05Event.KeyDown(ACK05Key.K10),
            (0x6D, true, false, false) => new ACK05Event.Dial(DialDirection.Counterclockwise),
            (0x6B, true, false, false) => new ACK05Event.Dial(DialDirection.Clockwise),
            _ => null,
        };
    }

    private bool HasModifier(ushort virtualKey, DateTimeOffset timestamp) =>
        modifiers.TryGetValue(virtualKey, out var state)
        && (state.Down || state.ReleasedAt is { } releasedAt && timestamp - releasedAt <= chordGrace);

    private void MarkActiveModifiersUsed(DateTimeOffset timestamp)
    {
        foreach (var (virtualKey, state) in modifiers.ToArray())
        {
            if (state.Down || state.ReleasedAt is { } releasedAt && timestamp - releasedAt <= chordGrace)
            {
                modifiers[virtualKey] = state with { Used = true };
            }
        }
    }

    private static bool IsModifier(ushort virtualKey) => virtualKey is Shift or Control or Alt;

    private static ACK05Key? ModifierAction(ushort virtualKey) => virtualKey switch
    {
        Shift => ACK05Key.K4,
        Control => ACK05Key.K5,
        Alt => ACK05Key.K6,
        _ => null,
    };

    private sealed record ModifierState(bool Down, bool Used, DateTimeOffset? ReleasedAt);
}

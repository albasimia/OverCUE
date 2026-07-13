using System.Text.Json;
using OverCUE.Core;

var path = Path.Combine(AppContext.BaseDirectory, "TestVectors", "ack05-hid-reports.json");
var vectors = JsonSerializer.Deserialize<TestVectors>(
    File.ReadAllText(path),
    new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
    ?? throw new InvalidOperationException("Could not decode ACK05 test vectors.");

var failures = new List<string>();
var decoder = new ACK05ReportDecoder();

foreach (var testCase in vectors.EventCases)
{
    var actual = Format(decoder.Decode(vectors.ReportID, ToBytes(testCase.Bytes)));
    Check(actual == testCase.Expected, testCase.Name, testCase.Expected, actual);
}

foreach (var testCase in vectors.StateCases)
{
    var previous = testCase.Previous.Select(ParseKey).ToHashSet();
    var actual = decoder.PressedKeys(vectors.ReportID, ToBytes(testCase.Bytes), previous);
    var actualNames = actual?.Select(key => key.ToString()).Order().ToArray();
    var expectedNames = testCase.Expected?.Order().ToArray();
    Check(
        actualNames is null ? expectedNames is null : expectedNames is not null && actualNames.SequenceEqual(expectedNames),
        testCase.Name,
        expectedNames is null ? null : string.Join(",", expectedNames),
        actualNames is null ? null : string.Join(",", actualNames));
}

RunKeyboardDecoderChecks();
RunActionLayerChecks();
RunMotionProfileChecks();

if (failures.Count > 0)
{
    foreach (var failure in failures)
    {
        Console.Error.WriteLine(failure);
    }

    return 1;
}

Console.WriteLine($"OverCUE.Core checks passed: {vectors.EventCases.Length + vectors.StateCases.Length + 38}");
return 0;

void Check(bool condition, string name, string? expected, string? actual)
{
    if (!condition)
    {
        failures.Add($"FAIL {name}: expected={expected ?? "null"}, actual={actual ?? "null"}");
    }
}

static ACK05Key ParseKey(string value) => Enum.Parse<ACK05Key>(value, ignoreCase: false);

static byte[] ToBytes(int[] values) => values.Select(value => checked((byte)value)).ToArray();

static string? Format(ACK05Event? value) => value switch
{
    ACK05Event.Dial { Direction: DialDirection.Clockwise } => "dial:clockwise",
    ACK05Event.Dial { Direction: DialDirection.Counterclockwise } => "dial:counterclockwise",
    ACK05Event.KeyDown keyDown => $"keyDown:{keyDown.Key}",
    ACK05Event.AllReleased => "allReleased",
    null => null,
    _ => throw new ArgumentOutOfRangeException(nameof(value)),
};

void RunKeyboardDecoderChecks()
{
    var origin = DateTimeOffset.UnixEpoch;
    var cases = new[]
    {
        ("k1", Events((0, 0x11, true), (2, 0x4F, true)), "keyDown:K1"),
        ("k2-key-up-recovery", Events((0, 0x11, true), (100, 0x11, false), (102, 0x4E, false)), "keyDown:K2"),
        ("k3", Events((0, 0x74, true)), "keyDown:K3"),
        ("k4-modifier-only", Events((0, 0x10, true), (50, 0x10, false), (100, 0, false)), "keyDown:K4"),
        ("k5-modifier-only", Events((0, 0x11, true), (50, 0x11, false), (100, 0, false)), "keyDown:K5"),
        ("k6-modifier-only", Events((0, 0x12, true), (50, 0x12, false), (100, 0, false)), "keyDown:K6"),
        ("k7", Events((0, 0x11, true), (2, 0x53, true)), "keyDown:K7"),
        ("k8", Events((0, 0x11, true), (2, 0x5A, true)), "keyDown:K8"),
        ("k9", Events((0, 0x20, true)), "keyDown:K9"),
        ("k10", Events((0, 0x11, true), (1, 0x10, true), (2, 0x5A, true)), "keyDown:K10"),
        ("dial-left", Events((0, 0x11, true), (2, 0x6D, true)), "dial:counterclockwise"),
        ("dial-right", Events((0, 0x11, true), (2, 0x6B, true)), "dial:clockwise"),
        ("driver-k1-f13", Events((0, 0x7C, true)), "keyDown:K1"),
        ("driver-k2-f14", Events((0, 0x7D, true)), "keyDown:K2"),
        ("driver-k3-f15", Events((0, 0x7E, true)), "keyDown:K3"),
        ("driver-k4-f16", Events((0, 0x7F, true)), "keyDown:K4"),
        ("driver-k5-f17", Events((0, 0x80, true)), "keyDown:K5"),
        ("driver-k6-f18", Events((0, 0x81, true)), "keyDown:K6"),
        ("driver-k7-f19", Events((0, 0x82, true)), "keyDown:K7"),
        ("driver-k8-f20", Events((0, 0x83, true)), "keyDown:K8"),
        ("driver-k9-f21", Events((0, 0x84, true)), "keyDown:K9"),
        ("driver-k10-f22", Events((0, 0x85, true)), "keyDown:K10"),
        ("driver-dial-left-f23", Events((0, 0x86, true)), "dial:counterclockwise"),
        ("driver-dial-right-f24", Events((0, 0x87, true)), "dial:clockwise"),
    };

    foreach (var (name, inputs, expected) in cases)
    {
        var decoder = new ACK05KeyboardDecoder();
        var actual = new List<ACK05Event>();
        foreach (var (milliseconds, virtualKey, isDown) in inputs)
        {
            actual.AddRange(decoder.Process(new RawKeyboardEvent(
                origin.AddMilliseconds(milliseconds), virtualKey, 0, isDown)));
        }

        actual.AddRange(decoder.Flush(origin.AddSeconds(1)));
        Check(actual.Count == 1 && Format(actual[0]) == expected, name, expected, string.Join(",", actual.Select(Format)));
    }

    static (int Milliseconds, ushort VirtualKey, bool IsDown)[] Events(
        params (int Milliseconds, ushort VirtualKey, bool IsDown)[] values) => values;
}

void RunActionLayerChecks()
{
    var mapping = new ActionMapping();
    mapping.Keys[ACK05Key.K7] = ActionTarget.ForAction(ActionID.Quantize);
    mapping.Keys[ACK05Key.K8] = ActionTarget.ForAction(ActionID.HotCue1);
    mapping.Keys[ACK05Key.K9] = ActionTarget.ForAction(ActionID.Cue);
    mapping.Chords[new KeyChord([ACK05Key.K7, ACK05Key.K8])] = ActionTarget.ForAction(ActionID.DeleteHotCue1);
    mapping.Dial[DialDirection.Clockwise] = ActionTarget.ForAction(ActionID.JogSearchRight);
    mapping.DialChords[new DialChord([ACK05Key.K7], DialDirection.Clockwise)] = new(null, "304f");

    var resolver = new InputActionResolver();
    Check(resolver.Handle([ACK05Key.K7], mapping).Count == 0, "action-modifier-deferred", "0", "event");
    var chord = resolver.Handle([ACK05Key.K7, ACK05Key.K8], mapping);
    Check(chord.Count == 1 && chord[0].Target.Action == ActionID.DeleteHotCue1,
        "action-chord-priority", "DeleteHotCue1", string.Join(",", chord.Select(value => value.Target.Action)));
    Check(resolver.Handle([], mapping).Count == 0, "action-used-modifier-suppressed", "0", "event");

    resolver.Handle([ACK05Key.K9], mapping);
    var cueRelease = resolver.Handle([], mapping);
    Check(cueRelease.Count == 1 && cueRelease[0].Phase == ActionPhase.Released,
        "action-hold-release", "Released", string.Join(",", cueRelease.Select(value => value.Phase)));

    resolver.Handle([ACK05Key.K7], mapping);
    var dial = resolver.DialEvent(DialDirection.Clockwise, mapping);
    Check(dial?.Target.RekordboxCommandID == "304f", "action-dial-chord", "304f", dial?.Target.RekordboxCommandID);

    Check(ActionTarget.Parse("rekordbox:3107")?.Behavior == ActionBehavior.Hold,
        "action-deck2-cue-hold", "Hold", ActionTarget.Parse("rekordbox:3107")?.Behavior.ToString());
    Check(ActionTarget.Parse("rekordbox:3108")?.Behavior == ActionBehavior.AcceleratingRepeat,
        "action-deck2-jump-forward-repeat", "AcceleratingRepeat",
        ActionTarget.Parse("rekordbox:3108")?.Behavior.ToString());
    Check(ActionTarget.Parse("rekordbox:3109")?.Behavior == ActionBehavior.AcceleratingRepeat,
        "action-deck2-jump-backward-repeat", "AcceleratingRepeat",
        ActionTarget.Parse("rekordbox:3109")?.Behavior.ToString());

    var cuePlayResolver = new InputActionResolver();
    var cuePlayMapping = new ActionMapping();
    cuePlayMapping.Keys[ACK05Key.K2] = ActionTarget.ForAction(ActionID.Cue);
    cuePlayMapping.Keys[ACK05Key.K5] = ActionTarget.ForAction(ActionID.PlayPause);
    var cuePress = cuePlayResolver.Handle([ACK05Key.K2], cuePlayMapping);
    var playWhileCueHeld = cuePlayResolver.Handle([ACK05Key.K2, ACK05Key.K5], cuePlayMapping);
    Check(cuePress.Count == 1 && cuePress[0].Target.Action == ActionID.Cue
        && cuePress[0].Phase == ActionPhase.Pressed
        && playWhileCueHeld.Count == 1 && playWhileCueHeld[0].Target.Action == ActionID.PlayPause
        && playWhileCueHeld[0].Phase == ActionPhase.Triggered
        && cuePlayMapping.HasCommand([ACK05Key.K2], "3007")
        && cuePlayMapping.HasCommand([ACK05Key.K5], "3006")
        && !cuePlayMapping.HasCommand([ACK05Key.K9, ACK05Key.K10], "3007"),
        "action-remapped-play-while-cue-held", "Cue:Pressed,PlayPause:Triggered",
        $"{string.Join(',', cuePress.Select(value => $"{value.Target.Action}:{value.Phase}"))},"
            + string.Join(',', playWhileCueHeld.Select(value => $"{value.Target.Action}:{value.Phase}")));
}

void RunMotionProfileChecks()
{
    var repeat = new AcceleratingKeyRepeatProfile();
    Check(Math.Abs(repeat.RepeatInterval(400) - 180) < 0.001,
        "repeat-start-interval", "180", repeat.RepeatInterval(400).ToString("0.###"));
    Check(Math.Abs(repeat.RepeatInterval(2400) - 35) < 0.001,
        "repeat-fast-interval", "35", repeat.RepeatInterval(2400).ToString("0.###"));

    var drag = new WaveformDragProfile();
    Check(Math.Abs(drag.DragMagnitude(null) - 1) < 0.001,
        "drag-default-step", "1", drag.DragMagnitude(null).ToString("0.###"));
    Check(Math.Abs(drag.DragMagnitude(35) - 20) < 0.001,
        "drag-fast-step", "20", drag.DragMagnitude(35).ToString("0.###"));
    Check(drag.HorizontalDelta(DialDirection.Clockwise) == 1
        && drag.HorizontalDelta(DialDirection.Counterclockwise) == -1,
        "drag-direction", "clockwise=1,counterclockwise=-1",
        $"clockwise={drag.HorizontalDelta(DialDirection.Clockwise)},counterclockwise={drag.HorizontalDelta(DialDirection.Counterclockwise)}");
}

internal sealed record TestVectors(uint ReportID, int ReportLength, EventCase[] EventCases, StateCase[] StateCases);

internal sealed record EventCase(string Name, int[] Bytes, string? Expected);

internal sealed record StateCase(string Name, int[] Bytes, string[] Previous, string[]? Expected);

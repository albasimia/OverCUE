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

if (failures.Count > 0)
{
    foreach (var failure in failures)
    {
        Console.Error.WriteLine(failure);
    }

    return 1;
}

Console.WriteLine($"OverCUE.Core checks passed: {vectors.EventCases.Length + vectors.StateCases.Length}");
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

internal sealed record TestVectors(uint ReportID, int ReportLength, EventCase[] EventCases, StateCase[] StateCases);

internal sealed record EventCase(string Name, int[] Bytes, string? Expected);

internal sealed record StateCase(string Name, int[] Bytes, string[] Previous, string[]? Expected);

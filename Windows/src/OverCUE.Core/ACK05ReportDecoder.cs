namespace OverCUE.Core;

public enum DialDirection
{
    Clockwise,
    Counterclockwise,
}

public enum ACK05Key
{
    K1,
    K2,
    K3,
    K4,
    K5,
    K6,
    K7,
    K8,
    K9,
    K10,
}

public abstract record ACK05Event
{
    private ACK05Event()
    {
    }

    public sealed record Dial(DialDirection Direction) : ACK05Event;

    public sealed record KeyDown(ACK05Key Key) : ACK05Event;

    public sealed record AllReleased : ACK05Event;
}

public sealed class ACK05ReportDecoder
{
    public const uint ReportID = 0x06;
    public const int ReportLength = 8;

    private static readonly ACK05Key[] Keys = Enum.GetValues<ACK05Key>();

    public ACK05Event? Decode(uint reportID, ReadOnlySpan<byte> bytes)
    {
        if (!IsReport(reportID, bytes) || bytes[3..].ContainsAnyExcept((byte)0))
        {
            return null;
        }

        return (bytes[1], bytes[2]) switch
        {
            (0x01, 0x57) => new ACK05Event.Dial(DialDirection.Clockwise),
            (0x01, 0x56) => new ACK05Event.Dial(DialDirection.Counterclockwise),
            (0x01, 0x12) => new ACK05Event.KeyDown(ACK05Key.K1),
            (0x01, 0x11) => new ACK05Event.KeyDown(ACK05Key.K2),
            (0x00, 0x3E) => new ACK05Event.KeyDown(ACK05Key.K3),
            (0x02, 0x00) => new ACK05Event.KeyDown(ACK05Key.K4),
            (0x01, 0x00) => new ACK05Event.KeyDown(ACK05Key.K5),
            (0x04, 0x00) => new ACK05Event.KeyDown(ACK05Key.K6),
            (0x01, 0x16) => new ACK05Event.KeyDown(ACK05Key.K7),
            (0x01, 0x1D) => new ACK05Event.KeyDown(ACK05Key.K8),
            (0x00, 0x2C) => new ACK05Event.KeyDown(ACK05Key.K9),
            (0x03, 0x1D) => new ACK05Event.KeyDown(ACK05Key.K10),
            (0x00, 0x00) => new ACK05Event.AllReleased(),
            _ => null,
        };
    }

    public HashSet<ACK05Key>? PressedKeys(uint reportID, ReadOnlySpan<byte> bytes)
    {
        if (!IsReport(reportID, bytes))
        {
            return null;
        }

        var modifier = bytes[1];
        var usages = bytes[2..].ToArray().Where(value => value != 0).ToHashSet();
        if (usages.Contains(0x56) || usages.Contains(0x57))
        {
            return null;
        }

        var keys = new HashSet<ACK05Key>();
        if (usages.Contains(0x12) && (modifier & 0x01) != 0) keys.Add(ACK05Key.K1);
        if (usages.Contains(0x11) && (modifier & 0x01) != 0) keys.Add(ACK05Key.K2);
        if (usages.Contains(0x3E)) keys.Add(ACK05Key.K3);
        if ((modifier & 0x02) != 0 && !usages.Contains(0x1D)) keys.Add(ACK05Key.K4);
        if (modifier == 0x01 && usages.Count == 0) keys.Add(ACK05Key.K5);
        if (modifier == 0x04 && usages.Count == 0) keys.Add(ACK05Key.K6);
        if (usages.Contains(0x16) && (modifier & 0x01) != 0) keys.Add(ACK05Key.K7);
        if (usages.Contains(0x1D))
        {
            keys.Add((modifier & 0x03) == 0x03 ? ACK05Key.K10 : ACK05Key.K8);
        }

        if (usages.Contains(0x2C)) keys.Add(ACK05Key.K9);
        return keys;
    }

    public HashSet<ACK05Key>? PressedKeys(
        uint reportID,
        ReadOnlySpan<byte> bytes,
        IReadOnlySet<ACK05Key> previousKeys)
    {
        if (!IsReport(reportID, bytes))
        {
            return null;
        }

        var modifier = bytes[1];
        var usages = bytes[2..].ToArray().Where(value => value != 0).ToHashSet();
        if (usages.Contains(0x56) || usages.Contains(0x57))
        {
            return null;
        }

        Candidate? best = null;
        var matches = new List<Candidate>();
        for (var mask = 0; mask < 1 << Keys.Length; mask++)
        {
            var candidateKeys = new HashSet<ACK05Key>();
            byte candidateModifier = 0;
            var candidateUsages = new HashSet<byte>();

            for (var index = 0; index < Keys.Length; index++)
            {
                if ((mask & (1 << index)) == 0)
                {
                    continue;
                }

                var key = Keys[index];
                candidateKeys.Add(key);
                var signature = Signature(key);
                candidateModifier |= signature.Modifier;
                if (signature.Usage is { } usage)
                {
                    candidateUsages.Add(usage);
                }
            }

            if (candidateModifier != modifier || !candidateUsages.SetEquals(usages))
            {
                continue;
            }

            var retained = candidateKeys.Count(previousKeys.Contains);
            var changes = candidateKeys.Except(previousKeys).Count() + previousKeys.Except(candidateKeys).Count();
            var candidate = new Candidate(candidateKeys, retained, changes, mask);
            matches.Add(candidate);
            if (best is null || IsBetter(candidate, best))
            {
                best = candidate;
            }
        }

        if (best is not null && best.Keys.SetEquals(previousKeys))
        {
            var expanded = matches
                .Where(candidate => previousKeys.All(candidate.Keys.Contains))
                .Where(candidate => candidate.Keys.Count == previousKeys.Count + 1)
                .Where(candidate => candidate.Keys.Except(previousKeys).All(key => Signature(key).Usage is null))
                .OrderBy(candidate => candidate.Mask)
                .FirstOrDefault();
            if (expanded is not null)
            {
                return expanded.Keys;
            }
        }

        return best?.Keys;
    }

    private static bool IsReport(uint reportID, ReadOnlySpan<byte> bytes) =>
        reportID == ReportID && bytes.Length == ReportLength && bytes[0] == ReportID;

    private static bool IsBetter(Candidate candidate, Candidate current) =>
        candidate.Retained > current.Retained
        || (candidate.Retained == current.Retained && candidate.Changes < current.Changes)
        || (candidate.Retained == current.Retained && candidate.Changes == current.Changes
            && candidate.Keys.Count < current.Keys.Count)
        || (candidate.Retained == current.Retained && candidate.Changes == current.Changes
            && candidate.Keys.Count == current.Keys.Count && candidate.Mask < current.Mask);

    private static (byte Modifier, byte? Usage) Signature(ACK05Key key) => key switch
    {
        ACK05Key.K1 => (0x01, 0x12),
        ACK05Key.K2 => (0x01, 0x11),
        ACK05Key.K3 => (0x00, 0x3E),
        ACK05Key.K4 => (0x02, null),
        ACK05Key.K5 => (0x01, null),
        ACK05Key.K6 => (0x04, null),
        ACK05Key.K7 => (0x01, 0x16),
        ACK05Key.K8 => (0x01, 0x1D),
        ACK05Key.K9 => (0x00, 0x2C),
        ACK05Key.K10 => (0x03, 0x1D),
        _ => throw new ArgumentOutOfRangeException(nameof(key), key, null),
    };

    private sealed record Candidate(HashSet<ACK05Key> Keys, int Retained, int Changes, int Mask);
}

internal static class SpanExtensions
{
    public static bool ContainsAnyExcept(this ReadOnlySpan<byte> span, byte expected)
    {
        foreach (var value in span)
        {
            if (value != expected)
            {
                return true;
            }
        }

        return false;
    }
}

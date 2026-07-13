namespace OverCUE.Core;

public sealed record AcceleratingKeyRepeatProfile(
    double InitialDelayMilliseconds = 400,
    double SlowIntervalMilliseconds = 180,
    double FastIntervalMilliseconds = 35,
    double AccelerationDurationMilliseconds = 2000)
{
    public double RepeatInterval(double heldMilliseconds)
    {
        var elapsed = Math.Max(0, heldMilliseconds - InitialDelayMilliseconds);
        var normalized = Math.Min(1, elapsed / AccelerationDurationMilliseconds);
        var smoothStep = normalized * normalized * (3 - 2 * normalized);
        return SlowIntervalMilliseconds - (SlowIntervalMilliseconds - FastIntervalMilliseconds) * smoothStep;
    }
}

public sealed record WaveformDragProfile(
    double PixelsPerDetent = 1,
    double MaximumPixelsPerDetent = 20,
    bool IsInverted = false,
    double FastIntervalMilliseconds = 35,
    double SlowIntervalMilliseconds = 200,
    double CurrentIntervalWeight = 0.35)
{
    public double HorizontalDelta(DialDirection direction, double? intervalMilliseconds = null)
    {
        var magnitude = DragMagnitude(intervalMilliseconds);
        var forward = IsInverted ? -magnitude : magnitude;
        return direction == DialDirection.Clockwise ? forward : -forward;
    }

    public double DragMagnitude(double? interval)
    {
        if (MaximumPixelsPerDetent <= PixelsPerDetent || interval is null) return PixelsPerDetent;
        if (interval <= FastIntervalMilliseconds) return MaximumPixelsPerDetent;
        if (interval >= SlowIntervalMilliseconds) return PixelsPerDetent;
        var speed = (SlowIntervalMilliseconds - interval.Value) / (SlowIntervalMilliseconds - FastIntervalMilliseconds);
        var eased = speed * speed; eased *= eased;
        return PixelsPerDetent + (MaximumPixelsPerDetent - PixelsPerDetent) * eased;
    }

    public double SmoothedInterval(double? previous, double current) =>
        (previous ?? SlowIntervalMilliseconds) * (1 - CurrentIntervalWeight) + current * CurrentIntervalWeight;
}

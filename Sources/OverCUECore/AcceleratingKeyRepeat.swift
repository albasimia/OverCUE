public struct AcceleratingKeyRepeatProfile: Equatable, Sendable {
    public let initialDelayMilliseconds: Double
    public let slowIntervalMilliseconds: Double
    public let fastIntervalMilliseconds: Double
    public let accelerationDurationMilliseconds: Double

    public init(
        initialDelayMilliseconds: Double = 400,
        slowIntervalMilliseconds: Double = 180,
        fastIntervalMilliseconds: Double = 35,
        accelerationDurationMilliseconds: Double = 2_000
    ) {
        self.initialDelayMilliseconds = initialDelayMilliseconds
        self.slowIntervalMilliseconds = slowIntervalMilliseconds
        self.fastIntervalMilliseconds = fastIntervalMilliseconds
        self.accelerationDurationMilliseconds = accelerationDurationMilliseconds
    }

    public func repeatInterval(heldMilliseconds: Double) -> Double {
        let accelerationElapsed = max(0, heldMilliseconds - initialDelayMilliseconds)
        let normalized = min(1, accelerationElapsed / accelerationDurationMilliseconds)
        let smoothStep = normalized * normalized * (3 - (2 * normalized))
        return slowIntervalMilliseconds
            - ((slowIntervalMilliseconds - fastIntervalMilliseconds) * smoothStep)
    }
}

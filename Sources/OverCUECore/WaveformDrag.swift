public struct WaveformDragProfile: Equatable, Sendable {
    public let pixelsPerDetent: Double
    public let maximumPixelsPerDetent: Double
    public let isInverted: Bool
    public let fastIntervalMilliseconds: Double
    public let slowIntervalMilliseconds: Double
    public let currentIntervalWeight: Double

    public init(
        pixelsPerDetent: Double = 1,
        maximumPixelsPerDetent: Double = 20,
        isInverted: Bool = false,
        fastIntervalMilliseconds: Double = 35,
        slowIntervalMilliseconds: Double = 200,
        currentIntervalWeight: Double = 0.35
    ) {
        self.pixelsPerDetent = pixelsPerDetent
        self.maximumPixelsPerDetent = maximumPixelsPerDetent
        self.isInverted = isInverted
        self.fastIntervalMilliseconds = fastIntervalMilliseconds
        self.slowIntervalMilliseconds = slowIntervalMilliseconds
        self.currentIntervalWeight = currentIntervalWeight
    }

    public func horizontalDelta(
        for direction: DialDirection,
        intervalMilliseconds: Double? = nil
    ) -> Double {
        let magnitude = dragMagnitude(intervalMilliseconds: intervalMilliseconds)
        let forwardDelta = isInverted ? magnitude : -magnitude
        return direction == .clockwise ? forwardDelta : -forwardDelta
    }

    public func dragMagnitude(intervalMilliseconds: Double?) -> Double {
        guard maximumPixelsPerDetent > pixelsPerDetent,
            let intervalMilliseconds
        else {
            return pixelsPerDetent
        }

        if intervalMilliseconds <= fastIntervalMilliseconds {
            return maximumPixelsPerDetent
        }
        if intervalMilliseconds >= slowIntervalMilliseconds {
            return pixelsPerDetent
        }

        let range = slowIntervalMilliseconds - fastIntervalMilliseconds
        let normalizedSpeed = (slowIntervalMilliseconds - intervalMilliseconds) / range
        let squaredSpeed = normalizedSpeed * normalizedSpeed
        let easedSpeed = squaredSpeed * squaredSpeed
        return pixelsPerDetent
            + ((maximumPixelsPerDetent - pixelsPerDetent) * easedSpeed)
    }

    public func smoothedInterval(
        previousMilliseconds: Double?,
        currentMilliseconds: Double
    ) -> Double {
        let previous = previousMilliseconds ?? slowIntervalMilliseconds
        return (previous * (1 - currentIntervalWeight))
            + (currentMilliseconds * currentIntervalWeight)
    }
}

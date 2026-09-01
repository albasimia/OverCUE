import Foundation

public struct HIDUsage: Codable, Equatable, Hashable, Sendable {
    public let page: UInt32
    public let usage: UInt32

    public init(page: UInt32, usage: UInt32) {
        self.page = page
        self.usage = usage
    }
}

public enum GenericHIDInputKind: String, Codable, Equatable, Sendable {
    case keyboard
    case consumerControl
    case button
    case relativeValue
    case absoluteValue
}

public struct GenericHIDInputDescriptor: Codable, Equatable, Hashable, Sendable {
    public let usage: HIDUsage
    public let reportID: UInt32?
    public let collectionPath: [HIDUsage]

    public init(
        usagePage: UInt32,
        usage: UInt32,
        reportID: UInt32? = nil,
        collectionPath: [HIDUsage] = []
    ) {
        self.usage = HIDUsage(page: usagePage, usage: usage)
        self.reportID = reportID
        self.collectionPath = collectionPath
    }

    public var kind: GenericHIDInputKind {
        switch usage.page {
        case 0x07: .keyboard
        case 0x0C: .consumerControl
        case 0x09: .button
        default: .absoluteValue
        }
    }

    public var label: String {
        let report = reportID.map { " report \($0)" } ?? ""
        return String(
            format: "usage 0x%04X:0x%04X%@",
            usage.page,
            usage.usage,
            report
        )
    }
}

public enum GenericHIDActivation: String, Codable, Equatable, Hashable, Sendable {
    case press
    case relativePositive
    case relativeNegative
}

public struct GenericHIDInputBindingKey: Codable, Equatable, Hashable, Sendable {
    public let input: GenericHIDInputDescriptor
    public let activation: GenericHIDActivation

    public init(input: GenericHIDInputDescriptor, activation: GenericHIDActivation) {
        self.input = input
        self.activation = activation
    }

    public var label: String {
        let suffix: String
        switch activation {
        case .press: suffix = "press"
        case .relativePositive: suffix = "relative +"
        case .relativeNegative: suffix = "relative -"
        }
        return "\(input.label) \(suffix)"
    }

    fileprivate var runtimeIdentifier: String {
        let report = input.reportID.map(String.init) ?? "none"
        let collection = input.collectionPath.map {
            String(format: "%04X:%04X", $0.page, $0.usage)
        }.joined(separator: "/")
        return "\(input.usage.page):\(input.usage.usage):\(report):\(collection):\(activation.rawValue)"
    }
}

public struct GenericHIDRuntimeElementDescriptor: Equatable, Sendable {
    public let input: GenericHIDInputDescriptor
    public let cookie: UInt64?
    public let isRelative: Bool
    public let matchingElementCount: Int?

    public init(
        input: GenericHIDInputDescriptor,
        cookie: UInt64? = nil,
        isRelative: Bool,
        matchingElementCount: Int? = nil
    ) {
        self.input = input
        self.cookie = cookie
        self.isRelative = isRelative
        self.matchingElementCount = matchingElementCount
    }

    public var persistentInput: GenericHIDInputDescriptor? {
        guard matchingElementCount == 1 else { return nil }
        return input
    }

    public var kind: GenericHIDInputKind {
        isRelative ? .relativeValue : input.kind
    }
}

public struct GenericHIDRawValue: Equatable, Sendable {
    public let sessionDeviceID: String
    public let element: GenericHIDRuntimeElementDescriptor
    public let value: Int

    public init(
        sessionDeviceID: String,
        element: GenericHIDRuntimeElementDescriptor,
        value: Int
    ) {
        self.sessionDeviceID = sessionDeviceID
        self.element = element
        self.value = value
    }
}

public enum GenericHIDEventPhase: Equatable, Sendable {
    case pressed
    case released
    case relative(delta: Int)
    case absolute(value: Int)
}

public struct GenericHIDEvent: Equatable, Sendable {
    public let sessionDeviceID: String
    public let element: GenericHIDRuntimeElementDescriptor
    public let phase: GenericHIDEventPhase

    public init(
        sessionDeviceID: String,
        element: GenericHIDRuntimeElementDescriptor,
        phase: GenericHIDEventPhase
    ) {
        self.sessionDeviceID = sessionDeviceID
        self.element = element
        self.phase = phase
    }
}

public enum GenericHIDEventNormalizer {
    public static func normalize(_ rawValue: GenericHIDRawValue) -> GenericHIDEvent? {
        if rawValue.element.isRelative {
            guard rawValue.value != 0 else { return nil }
            return GenericHIDEvent(
                sessionDeviceID: rawValue.sessionDeviceID,
                element: rawValue.element,
                phase: .relative(delta: rawValue.value)
            )
        }

        switch rawValue.element.input.kind {
        case .keyboard, .consumerControl, .button:
            return GenericHIDEvent(
                sessionDeviceID: rawValue.sessionDeviceID,
                element: rawValue.element,
                phase: rawValue.value == 0 ? .released : .pressed
            )
        case .relativeValue:
            return nil
        case .absoluteValue:
            return GenericHIDEvent(
                sessionDeviceID: rawValue.sessionDeviceID,
                element: rawValue.element,
                phase: .absolute(value: rawValue.value)
            )
        }
    }
}

public struct GenericHIDLearnCandidate: Equatable, Sendable {
    public let sessionDeviceID: String
    public let runtimeElement: GenericHIDRuntimeElementDescriptor
    public let initialPhase: GenericHIDEventPhase

    public init(event: GenericHIDEvent) {
        sessionDeviceID = event.sessionDeviceID
        runtimeElement = event.element
        initialPhase = event.phase
    }

    public var persistentInput: GenericHIDInputDescriptor? {
        runtimeElement.persistentInput
    }

    public var activation: GenericHIDActivation? {
        Self.learnActivation(for: initialPhase)
    }

    public var persistentBindingKey: GenericHIDInputBindingKey? {
        guard let input = persistentInput, let activation else { return nil }
        return GenericHIDInputBindingKey(input: input, activation: activation)
    }

    private static func learnActivation(for phase: GenericHIDEventPhase) -> GenericHIDActivation? {
        switch phase {
        case .pressed:
            .press
        case let .relative(delta) where delta > 0:
            .relativePositive
        case let .relative(delta) where delta < 0:
            .relativeNegative
        case .relative, .released, .absolute:
            nil
        }
    }
}

public enum GenericHIDLearnCancellationReason: Equatable, Sendable {
    case cancelled
    case sourceDisconnected
}

public enum GenericHIDLearnState: Equatable, Sendable {
    case idle
    case listening(sourceSessionID: String?)
    case captured(GenericHIDLearnCandidate)
    case cancelled(GenericHIDLearnCancellationReason)
}

public enum GenericHIDLearnObservation: Equatable, Sendable {
    case ignored
    case captured(GenericHIDLearnCandidate)
}

public enum GenericHIDLearnError: Error, Equatable, LocalizedError, Sendable {
    case noCandidate
    case ambiguousPersistentInput

    public var errorDescription: String? {
        switch self {
        case .noCandidate:
            return "Generic HID Learn has no captured input."
        case .ambiguousPersistentInput:
            return "The HID input cannot be persisted until duplicate element identity is resolved."
        }
    }
}

public struct GenericHIDLogicalInputBinding: Equatable, Sendable {
    public let key: GenericHIDInputBindingKey
    public let target: ActionTarget

    public init(key: GenericHIDInputBindingKey, target: ActionTarget) {
        self.key = key
        self.target = target
    }

    @available(*, deprecated, message: "Use key so relative direction remains part of the binding.")
    public init(input: GenericHIDInputDescriptor, target: ActionTarget) {
        self.init(
            key: GenericHIDInputBindingKey(input: input, activation: .press),
            target: target
        )
    }

    public var input: GenericHIDInputDescriptor { key.input }
    public var activation: GenericHIDActivation { key.activation }
}

public struct GenericHIDLearnSession: Equatable, Sendable {
    public private(set) var state: GenericHIDLearnState = .idle

    public init() {}

    public mutating func begin() {
        state = .listening(sourceSessionID: nil)
    }

    public mutating func observe(_ event: GenericHIDEvent) -> GenericHIDLearnObservation {
        guard case let .listening(sourceSessionID) = state else { return .ignored }
        if let sourceSessionID, sourceSessionID != event.sessionDeviceID {
            return .ignored
        }
        guard Self.isLearnActivation(event.phase) else { return .ignored }
        if sourceSessionID == nil {
            state = .listening(sourceSessionID: event.sessionDeviceID)
        }
        let candidate = GenericHIDLearnCandidate(event: event)
        state = .captured(candidate)
        return .captured(candidate)
    }

    public mutating func deviceDisconnected(_ sessionIdentifier: String) {
        switch state {
        case let .listening(sourceSessionID) where sourceSessionID == sessionIdentifier:
            state = .cancelled(.sourceDisconnected)
        case let .captured(candidate) where candidate.sessionDeviceID == sessionIdentifier:
            state = .cancelled(.sourceDisconnected)
        default:
            break
        }
    }

    public mutating func cancel() {
        state = .cancelled(.cancelled)
    }

    public func binding(target: ActionTarget) throws -> GenericHIDLogicalInputBinding {
        guard case let .captured(candidate) = state else {
            throw GenericHIDLearnError.noCandidate
        }
        guard let key = candidate.persistentBindingKey else {
            throw GenericHIDLearnError.ambiguousPersistentInput
        }
        return GenericHIDLogicalInputBinding(key: key, target: target)
    }

    private static func isLearnActivation(_ phase: GenericHIDEventPhase) -> Bool {
        switch phase {
        case .pressed:
            true
        case let .relative(delta):
            delta != 0
        case .released, .absolute:
            false
        }
    }
}

public struct GenericHIDActionResolver: Equatable, Sendable {
    private var activeHoldSources: [ActionSourceID: GenericHIDInputBindingKey] = [:]
    private var activeRepeatSources: [ActionSourceID: GenericHIDInputBindingKey] = [:]

    public init() {}

    public mutating func resolve(
        event: GenericHIDEvent,
        mapping: [GenericHIDInputBindingKey: ActionTarget]
    ) -> [ActionEvent] {
        guard let input = event.element.persistentInput,
              let key = Self.bindingKey(for: event.phase, input: input),
              let target = mapping[key]
        else { return [] }

        let sourceID = Self.sourceID(for: event.sessionDeviceID, key: key)
        let sourceLabel = key.label
        switch event.phase {
        case .pressed:
            if target.behavior == .hold {
                activeHoldSources[sourceID] = key
            }
            if target.behavior == .acceleratingRepeat {
                activeRepeatSources[sourceID] = key
            }
            let phase: ActionPhase = target.behavior == .hold || target.behavior == .acceleratingRepeat
                ? .pressed
                : .triggered
            return [ActionEvent(
                target: target,
                phase: phase,
                sourceID: sourceID,
                sourceLabel: sourceLabel
            )]
        case .released:
            activeRepeatSources.removeValue(forKey: sourceID)
            guard activeHoldSources.removeValue(forKey: sourceID) != nil else { return [] }
            return [ActionEvent(
                target: target,
                phase: .released,
                sourceID: sourceID,
                sourceLabel: sourceLabel
            )]
        case let .relative(delta):
            return [ActionEvent(
                target: target,
                phase: .triggered,
                sourceID: sourceID,
                sourceLabel: sourceLabel,
                activationCount: Self.magnitude(of: delta)
            )]
        case .absolute:
            return []
        }
    }

    public func repeatedEvent(
        for sourceID: ActionSourceID,
        mapping: [GenericHIDInputBindingKey: ActionTarget]
    ) -> ActionEvent? {
        guard let key = activeRepeatSources[sourceID],
              let target = mapping[key],
              target.behavior == .acceleratingRepeat
        else { return nil }
        return ActionEvent(
            target: target,
            phase: .repeated,
            sourceID: sourceID,
            sourceLabel: key.label
        )
    }

    public func repeatedEvent(
        for key: GenericHIDInputBindingKey,
        mapping: [GenericHIDInputBindingKey: ActionTarget]
    ) -> ActionEvent? {
        guard let sourceID = activeRepeatSources.first(where: { $0.value == key })?.key else {
            return nil
        }
        return repeatedEvent(for: sourceID, mapping: mapping)
    }

    public mutating func reset(
        mapping: [GenericHIDInputBindingKey: ActionTarget]
    ) -> [ActionEvent] {
        let releases = activeHoldSources.compactMap { sourceID, key -> ActionEvent? in
            guard let target = mapping[key] else { return nil }
            return ActionEvent(
                target: target,
                phase: .released,
                sourceID: sourceID,
                sourceLabel: key.label
            )
        }
        activeHoldSources = [:]
        activeRepeatSources = [:]
        return releases
    }

    @available(*, deprecated, message: "Use GenericHIDInputBindingKey so relative direction is explicit.")
    public mutating func resolve(
        event: GenericHIDEvent,
        mapping: [GenericHIDInputDescriptor: ActionTarget]
    ) -> [ActionEvent] {
        resolve(event: event, mapping: Self.legacyDirectionalMapping(mapping))
    }

    @available(*, deprecated, message: "Use GenericHIDInputBindingKey so relative direction is explicit.")
    public func repeatedEvent(
        for input: GenericHIDInputDescriptor,
        mapping: [GenericHIDInputDescriptor: ActionTarget]
    ) -> ActionEvent? {
        repeatedEvent(
            for: GenericHIDInputBindingKey(input: input, activation: .press),
            mapping: Self.legacyDirectionalMapping(mapping)
        )
    }

    @available(*, deprecated, message: "Use GenericHIDInputBindingKey so relative direction is explicit.")
    public mutating func reset(
        mapping: [GenericHIDInputDescriptor: ActionTarget]
    ) -> [ActionEvent] {
        reset(mapping: Self.legacyDirectionalMapping(mapping))
    }

    private static func bindingKey(
        for phase: GenericHIDEventPhase,
        input: GenericHIDInputDescriptor
    ) -> GenericHIDInputBindingKey? {
        let activation: GenericHIDActivation
        switch phase {
        case .pressed, .released:
            activation = .press
        case let .relative(delta) where delta > 0:
            activation = .relativePositive
        case let .relative(delta) where delta < 0:
            activation = .relativeNegative
        case .relative, .absolute:
            return nil
        }
        return GenericHIDInputBindingKey(input: input, activation: activation)
    }

    private static func sourceID(
        for sessionDeviceID: String,
        key: GenericHIDInputBindingKey
    ) -> ActionSourceID {
        ActionSourceID(
            namespace: "generic-hid",
            identifier: "\(sessionDeviceID)|\(key.runtimeIdentifier)"
        )
    }

    private static func magnitude(of delta: Int) -> Int {
        let magnitude = delta.magnitude
        return magnitude > UInt(Int.max) ? Int.max : max(1, Int(magnitude))
    }

    private static func legacyDirectionalMapping(
        _ mapping: [GenericHIDInputDescriptor: ActionTarget]
    ) -> [GenericHIDInputBindingKey: ActionTarget] {
        var result: [GenericHIDInputBindingKey: ActionTarget] = [:]
        for (input, target) in mapping {
            result[GenericHIDInputBindingKey(input: input, activation: .press)] = target
            result[GenericHIDInputBindingKey(input: input, activation: .relativePositive)] = target
            result[GenericHIDInputBindingKey(input: input, activation: .relativeNegative)] = target
        }
        return result
    }
}

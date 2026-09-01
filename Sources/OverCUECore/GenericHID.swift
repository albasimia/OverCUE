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
    public let input: GenericHIDInputDescriptor
    public let target: ActionTarget

    public init(input: GenericHIDInputDescriptor, target: ActionTarget) {
        self.input = input
        self.target = target
    }
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
        guard let input = candidate.persistentInput else {
            throw GenericHIDLearnError.ambiguousPersistentInput
        }
        return GenericHIDLogicalInputBinding(input: input, target: target)
    }

    private static func isLearnActivation(_ phase: GenericHIDEventPhase) -> Bool {
        switch phase {
        case .pressed, .relative:
            true
        case .released, .absolute:
            false
        }
    }
}

public struct GenericHIDActionResolver: Equatable, Sendable {
    private var activeHoldInputs: Set<GenericHIDInputDescriptor> = []
    private var activeRepeatInputs: Set<GenericHIDInputDescriptor> = []

    public init() {}

    public mutating func resolve(
        event: GenericHIDEvent,
        mapping: [GenericHIDInputDescriptor: ActionTarget]
    ) -> [ActionEvent] {
        guard let input = event.element.persistentInput,
              let target = mapping[input]
        else { return [] }
        let sourceLabel = input.label
        switch event.phase {
        case .pressed:
            if target.behavior == .hold {
                activeHoldInputs.insert(input)
                return [ActionEvent(
                    target: target,
                    phase: .pressed,
                    sourceKey: nil,
                    sourceLabel: sourceLabel
                )]
            }
            if target.behavior == .acceleratingRepeat {
                activeRepeatInputs.insert(input)
            }
            let phase: ActionPhase = target.behavior == .acceleratingRepeat
                ? .pressed
                : .triggered
            return [ActionEvent(
                target: target,
                phase: phase,
                sourceKey: nil,
                sourceLabel: sourceLabel
            )]
        case .released:
            activeRepeatInputs.remove(input)
            guard activeHoldInputs.remove(input) != nil else { return [] }
            return [ActionEvent(
                target: target,
                phase: .released,
                sourceKey: nil,
                sourceLabel: sourceLabel
            )]
        case .relative:
            return [ActionEvent(
                target: target,
                phase: .triggered,
                sourceKey: nil,
                sourceLabel: sourceLabel
            )]
        case .absolute:
            return []
        }
    }

    public func repeatedEvent(
        for input: GenericHIDInputDescriptor,
        mapping: [GenericHIDInputDescriptor: ActionTarget]
    ) -> ActionEvent? {
        guard activeRepeatInputs.contains(input),
              let target = mapping[input],
              target.behavior == .acceleratingRepeat
        else { return nil }
        return ActionEvent(
            target: target,
            phase: .repeated,
            sourceKey: nil,
            sourceLabel: input.label
        )
    }

    public mutating func reset(
        mapping: [GenericHIDInputDescriptor: ActionTarget]
    ) -> [ActionEvent] {
        let releases = activeHoldInputs.compactMap { input -> ActionEvent? in
            guard let target = mapping[input] else { return nil }
            return ActionEvent(
                target: target,
                phase: .released,
                sourceKey: nil,
                sourceLabel: input.label
            )
        }
        activeHoldInputs = []
        activeRepeatInputs = []
        return releases
    }
}

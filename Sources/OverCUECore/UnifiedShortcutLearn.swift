import Foundation

public enum UnifiedShortcutLearnBackend: String, CaseIterable, Hashable, Sendable {
    case ack05
    case genericHID
}

public struct UnifiedShortcutLearnContext: Equatable, Sendable {
    public let id: UUID
    public let editorPresetID: String
    public let target: ActionTarget

    public init(id: UUID = UUID(), editorPresetID: String, target: ActionTarget) {
        self.id = id
        self.editorPresetID = editorPresetID
        self.target = target
    }
}

public enum UnifiedShortcutLearnPhase: Equatable, Sendable {
    case idle
    case listening(UnifiedShortcutLearnContext)
    case claimed(UnifiedShortcutLearnContext, UnifiedShortcutLearnBackend)
    case completed(UnifiedShortcutLearnContext, UnifiedShortcutLearnBackend)
    case cancelled(UnifiedShortcutLearnContext)
}

/// Pure state machine shared by the Shortcuts capture adapters. Backend
/// availability is independent and the first successful physical input owns the
/// session's single terminal path.
public struct UnifiedShortcutLearnSession: Equatable, Sendable {
    public private(set) var phase: UnifiedShortcutLearnPhase = .idle
    public private(set) var availableBackends: Set<UnifiedShortcutLearnBackend> = []
    public private(set) var failedBackends: Set<UnifiedShortcutLearnBackend> = []

    public init() {}

    @discardableResult
    public mutating func begin(
        editorPresetID: String,
        target: ActionTarget,
        id: UUID = UUID()
    ) -> UnifiedShortcutLearnContext? {
        switch phase {
        case .listening, .claimed:
            return nil
        case .idle, .completed, .cancelled:
            break
        }
        let context = UnifiedShortcutLearnContext(
            id: id,
            editorPresetID: editorPresetID,
            target: target
        )
        phase = .listening(context)
        availableBackends = []
        failedBackends = []
        return context
    }

    public mutating func backendStarted(_ backend: UnifiedShortcutLearnBackend) {
        guard case .listening = phase else { return }
        availableBackends.insert(backend)
        failedBackends.remove(backend)
    }

    public mutating func backendFailed(_ backend: UnifiedShortcutLearnBackend) {
        guard case .listening = phase else { return }
        availableBackends.remove(backend)
        failedBackends.insert(backend)
    }

    @discardableResult
    public mutating func claim(
        by backend: UnifiedShortcutLearnBackend
    ) -> UnifiedShortcutLearnContext? {
        guard case let .listening(context) = phase,
              availableBackends.contains(backend)
        else { return nil }
        phase = .claimed(context, backend)
        return context
    }

    public mutating func complete(by backend: UnifiedShortcutLearnBackend) {
        guard case let .claimed(context, winner) = phase, winner == backend else { return }
        phase = .completed(context, backend)
    }

    public mutating func cancel() {
        switch phase {
        case let .listening(context), let .claimed(context, _):
            phase = .cancelled(context)
        case .idle, .completed, .cancelled:
            break
        }
    }

    public var isListening: Bool {
        if case .listening = phase { return true }
        return false
    }

    public var hasAvailableBackend: Bool { !availableBackends.isEmpty }
}

import OverCUECore

/// One-shot handoff from the Shortcuts UI to the runtime bridge.
///
/// ShortcutSettingsModel already owns the ACK05 capture lifecycle and calls
/// runtimeBridge.stop() before opening ACK05 directly. Generic HID must not
/// actually close at that point because it already owns the bound device
/// exclusively. The unified Shortcuts adapter prepares this broker first;
/// OverCUECLIRuntime consumes it from stop() and switches the existing Generic
/// HID owner into capture mode instead of releasing the device.
@MainActor
final class GenericHIDShortcutCaptureBroker {
    static let shared = GenericHIDShortcutCaptureBroker()

    typealias Handler = (String, GenericHIDInputBindingKey) -> Void

    private var preparedHandler: Handler?

    private init() {}

    func prepare(_ handler: @escaping Handler) {
        preparedHandler = handler
    }

    func takePreparedHandler() -> Handler? {
        defer { preparedHandler = nil }
        return preparedHandler
    }

    func cancelPrepared() {
        preparedHandler = nil
    }
}

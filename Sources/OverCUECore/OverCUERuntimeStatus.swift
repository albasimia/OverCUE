import Foundation

public enum OverCUERuntimeNotificationScope: String, Equatable, Sendable {
    case device
    case global

    public func controls(activeDeviceID: String, targetDeviceID: String?) -> Bool {
        switch self {
        case .global:
            true
        case .device:
            targetDeviceID == activeDeviceID
        }
    }
}

/// Process-local gate used while Shortcuts is learning a physical input.
///
/// Multiple Logical Devices can legitimately run different Presets at the same
/// time. Runtime status therefore must not be allowed to retarget the editor in
/// the middle of Learn. The ACK05 helper is a separate process, so its gate is
/// independent; the GUI stops that helper before opening the ACK05 capture
/// monitor. Generic HID stays inside the GUI process and uses this gate while
/// the unified capture is active.
public final class OverCUERuntimeStatusDeliveryGate: @unchecked Sendable {
    public static let shared = OverCUERuntimeStatusDeliveryGate()

    private let lock = NSLock()
    private var suppressionDepth = 0

    private init() {}

    public var isSuppressed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return suppressionDepth > 0
    }

    public func beginSuppression() {
        lock.lock()
        suppressionDepth += 1
        lock.unlock()
    }

    public func endSuppression() {
        lock.lock()
        suppressionDepth = max(0, suppressionDepth - 1)
        lock.unlock()
    }
}

public enum OverCUERuntimeStatusNotification {
    private static let liveName = Notification.Name("com.overcue.runtime-status-changed")
    private static let suppressedName = Notification.Name(
        "com.overcue.runtime-status-changed.suppressed-during-shortcut-learn"
    )

    /// Observers register the live name during normal app startup. Publishers
    /// resolve this property at post time, so GUI-process runtime updates emitted
    /// during Learn are intentionally routed away from the editor observer.
    public static var name: Notification.Name {
        OverCUERuntimeStatusDeliveryGate.shared.isSuppressed ? suppressedName : liveName
    }

    public static let modeKey = "mode"
    public static let groupKey = "group"
    public static let presetGroupIDKey = "presetGroupID"
    public static let scopeKey = "scope"
    public static let deviceIDKey = "deviceID"
    public static let logicalDeviceIDKey = "logicalDeviceID"
    public static let profileNameKey = "profileName"
    public static let connectedKey = "connected"
}

public struct OverCUERuntimeTarget: Equatable, Sendable {
    public let deviceID: String
    public let logicalDeviceID: String?
    public let profileName: String

    public init(deviceID: String, logicalDeviceID: String?, profileName: String) {
        self.deviceID = deviceID
        self.logicalDeviceID = logicalDeviceID
        self.profileName = profileName
    }
}

public enum OverCUERuntimeTargetPolicy {
    public static func updatedTarget(
        current: OverCUERuntimeTarget?,
        defaultProfileName: String,
        deviceID: String,
        logicalDeviceID: String?,
        profileName: String,
        connected: Bool
    ) -> OverCUERuntimeTarget? {
        guard profileName == defaultProfileName else { return current }
        if !connected {
            return current?.deviceID == deviceID ? nil : current
        }
        return OverCUERuntimeTarget(
            deviceID: deviceID,
            logicalDeviceID: logicalDeviceID,
            profileName: profileName
        )
    }

    public static func controlDeviceID(
        target: OverCUERuntimeTarget?,
        defaultProfileName: String
    ) -> String? {
        guard target?.profileName == defaultProfileName else { return nil }
        return target?.deviceID
    }
}

public enum OverCUERuntimeControlNotification {
    public static let name = Notification.Name("com.overcue.runtime-control-requested")
    public static let modeKey = OverCUERuntimeStatusNotification.modeKey
    public static let groupKey = OverCUERuntimeStatusNotification.groupKey
    public static let presetGroupIDKey = OverCUERuntimeStatusNotification.presetGroupIDKey
    public static let scopeKey = OverCUERuntimeStatusNotification.scopeKey
    public static let deviceIDKey = OverCUERuntimeStatusNotification.deviceIDKey
    public static let profileNameKey = OverCUERuntimeStatusNotification.profileNameKey
}

public enum OverCUEInputStatusNotification {
    public static let name = Notification.Name("com.overcue.input-status-changed")
    public static let keysKey = "pressedKeys"
    public static let dialDirectionKey = "dialDirection"
    public static let deviceIDKey = "deviceID"
}

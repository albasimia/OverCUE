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

public enum OverCUERuntimeStatusNotification {
    public static let name = Notification.Name("com.overcue.runtime-status-changed")
    public static let modeKey = "mode"
    public static let groupKey = "group"
    public static let scopeKey = "scope"
    public static let deviceIDKey = "deviceID"
    public static let logicalDeviceIDKey = "logicalDeviceID"
    public static let profileNameKey = "profileName"
}

public enum OverCUERuntimeControlNotification {
    public static let name = Notification.Name("com.overcue.runtime-control-requested")
    public static let modeKey = OverCUERuntimeStatusNotification.modeKey
    public static let groupKey = OverCUERuntimeStatusNotification.groupKey
    public static let scopeKey = OverCUERuntimeStatusNotification.scopeKey
    public static let deviceIDKey = OverCUERuntimeStatusNotification.deviceIDKey
}

public enum OverCUEInputStatusNotification {
    public static let name = Notification.Name("com.overcue.input-status-changed")
    public static let keysKey = "pressedKeys"
    public static let dialDirectionKey = "dialDirection"
    public static let deviceIDKey = "deviceID"
}

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

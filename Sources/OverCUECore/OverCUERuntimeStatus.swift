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
    public static let presetGroupIDKey = "presetGroupID"
    public static let scopeKey = "scope"
    public static let deviceIDKey = "deviceID"
    public static let logicalDeviceIDKey = "logicalDeviceID"
    public static let profileNameKey = "profileName"
    public static let connectedKey = "connected"
}

public struct OverCUERuntimeDeviceState: Equatable, Sendable {
    public let mode: RekordboxMappingMode
    public let group: Int
    public let presetGroupID: String?
    public let target: OverCUERuntimeTarget

    public init(
        mode: RekordboxMappingMode,
        group: Int,
        presetGroupID: String?,
        target: OverCUERuntimeTarget
    ) {
        self.mode = mode
        self.group = group
        self.presetGroupID = presetGroupID
        self.target = target
    }
}

/// Device-scoped runtime status storage. It deliberately contains no editor
/// selection: Shortcuts Preset selection belongs to the editor, not runtime.
public struct OverCUERuntimeStateRegistry: Equatable, Sendable {
    public private(set) var statesByDeviceID: [String: OverCUERuntimeDeviceState] = [:]
    public private(set) var focusedDeviceID: String?

    public init() {}

    @discardableResult
    public mutating func apply(
        mode: RekordboxMappingMode,
        group: Int,
        presetGroupID: String?,
        deviceID: String,
        logicalDeviceID: String?,
        profileName: String,
        defaultProfileName: String,
        connected: Bool
    ) -> OverCUERuntimeDeviceState? {
        guard profileName == defaultProfileName else { return focusedState }
        if !connected {
            statesByDeviceID.removeValue(forKey: deviceID)
            if focusedDeviceID == deviceID { focusedDeviceID = nil }
            return focusedState
        }
        let state = OverCUERuntimeDeviceState(
            mode: mode,
            group: group,
            presetGroupID: presetGroupID,
            target: OverCUERuntimeTarget(
                deviceID: deviceID,
                logicalDeviceID: logicalDeviceID,
                profileName: profileName
            )
        )
        statesByDeviceID[deviceID] = state
        focusedDeviceID = deviceID
        return state
    }

    public var focusedState: OverCUERuntimeDeviceState? {
        focusedDeviceID.flatMap { statesByDeviceID[$0] }
    }
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

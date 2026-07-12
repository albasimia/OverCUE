import Foundation

public enum OverCUERuntimeStatusNotification {
    public static let name = Notification.Name("com.overcue.runtime-status-changed")
    public static let modeKey = "mode"
    public static let groupKey = "group"
}

public enum OverCUERuntimeControlNotification {
    public static let name = Notification.Name("com.overcue.runtime-control-requested")
    public static let modeKey = OverCUERuntimeStatusNotification.modeKey
    public static let groupKey = OverCUERuntimeStatusNotification.groupKey
}

public enum OverCUEInputStatusNotification {
    public static let name = Notification.Name("com.overcue.input-status-changed")
    public static let keysKey = "pressedKeys"
    public static let dialDirectionKey = "dialDirection"
}

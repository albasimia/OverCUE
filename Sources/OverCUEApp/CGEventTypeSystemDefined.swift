import ApplicationServices

// AppKit exposes NSSystemDefined as NSEvent.EventType.systemDefined, but
// CoreGraphics does not surface the corresponding CGEventType case in Swift.
// The event type has the stable raw value 14 in the macOS event ABI.
extension CGEventType {
    static let systemDefined = CGEventType(rawValue: 14)!
}

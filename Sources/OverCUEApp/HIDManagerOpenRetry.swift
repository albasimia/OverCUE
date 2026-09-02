import Foundation
import IOKit.hid

/// IOHIDManagerClose can return before macOS has fully released an exclusive
/// claim for a composite HID. Keep ownership handoff policy below the UI layer:
/// callers express the desired open mode and retry only the transient
/// kIOReturnExclusiveAccess result.
enum HIDManagerOpenRetry {
    static func open(
        _ manager: IOHIDManager,
        options: IOOptionBits,
        maximumAttempts: Int = 16,
        retryInterval: TimeInterval = 0.10
    ) -> IOReturn {
        let attempts = max(1, maximumAttempts)
        var result = IOHIDManagerOpen(manager, options)
        guard result == kIOReturnExclusiveAccess, attempts > 1 else { return result }

        for _ in 1..<attempts {
            Thread.sleep(forTimeInterval: retryInterval)
            result = IOHIDManagerOpen(manager, options)
            if result != kIOReturnExclusiveAccess {
                return result
            }
        }
        return result
    }
}

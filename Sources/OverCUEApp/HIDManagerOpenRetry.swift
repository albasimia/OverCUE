import Foundation
import IOKit.hid

/// IOHIDManagerClose can return before macOS has fully released an exclusive
/// claim for a composite HID. Retry the transient handoff case. Keyboard-class
/// HID devices may reject SeizeDevice for an ordinary user process; in that
/// case fall back to shared access and let GenericHIDNativeEventSuppressor drop
/// only the correlated downstream macOS event.
enum HIDManagerOpenRetry {
    static func open(
        _ manager: IOHIDManager,
        options: IOOptionBits,
        maximumAttempts: Int = 16,
        retryInterval: TimeInterval = 0.10
    ) -> IOReturn {
        let attempts = max(1, maximumAttempts)
        var result = IOHIDManagerOpen(manager, options)

        if result == kIOReturnNotPrivileged,
           options & IOOptionBits(kIOHIDOptionsTypeSeizeDevice) != 0 {
            return IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        guard result == kIOReturnExclusiveAccess, attempts > 1 else { return result }

        for _ in 1..<attempts {
            Thread.sleep(forTimeInterval: retryInterval)
            result = IOHIDManagerOpen(manager, options)
            if result == kIOReturnNotPrivileged,
               options & IOOptionBits(kIOHIDOptionsTypeSeizeDevice) != 0 {
                return IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            if result != kIOReturnExclusiveAccess {
                return result
            }
        }
        return result
    }
}

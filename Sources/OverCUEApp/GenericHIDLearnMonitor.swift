import Foundation
import IOKit.hid
import OverCUECore

enum GenericHIDLearnMonitorError: @preconcurrency LocalizedError {
    case openFailed(IOReturn)
    case missingPersistentIdentity

    @MainActor var errorDescription: String? {
        switch self {
        case let .openFailed(status):
            return L10n.text(
                "devices.identify.openFailed",
                String(format: "0x%08X", UInt32(bitPattern: status))
            )
        case .missingPersistentIdentity:
            return "Generic HID Learn requires a Serial Number backed Physical Binding."
        }
    }
}

final class GenericHIDLearnMonitor: @unchecked Sendable {
    var onCaptured: ((GenericHIDInputBindingKey) -> Void)?

    private let binding: OverCUEPhysicalDeviceBinding
    private let manager: IOHIDManager
    private var learnSession = GenericHIDLearnSession()
    private var isOpen = false
    private var didCapture = false

    init(binding: OverCUEPhysicalDeviceBinding) {
        self.binding = binding
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        var matching: [String: Any] = [
            kIOHIDVendorIDKey as String: binding.vendorID,
            kIOHIDProductIDKey as String: binding.productID,
        ]
        if let serialNumber = binding.serialNumber {
            matching[kIOHIDSerialNumberKey as String] = serialNumber
        }
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, genericLearnInputValueReceived, context)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
    }

    deinit {
        stop()
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )
    }

    func start() throws {
        guard !isOpen else { return }
        guard binding.kind == .genericHID,
              binding.serialNumber != nil
        else {
            throw GenericHIDLearnMonitorError.missingPersistentIdentity
        }
        learnSession.begin()
        didCapture = false

        // Learn targets one already-bound Physical Device. Seize only that
        // VID/PID/Serial match so its native keyboard / Consumer Control action
        // cannot reach macOS before OverCUE captures the descriptor. If the
        // normal runtime just released this composite HID, retry only the
        // transient ExclusiveAccess handoff instead of making the UI guess a delay.
        let result = HIDManagerOpenRetry.open(
            manager,
            options: IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
        )
        guard result == kIOReturnSuccess else {
            throw GenericHIDLearnMonitorError.openFailed(result)
        }
        isOpen = true
    }

    func stop() {
        guard isOpen else { return }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = false
        didCapture = false
        learnSession.cancel()
    }

    fileprivate func didReceiveValue(result: IOReturn, value: IOHIDValue) {
        guard result == kIOReturnSuccess, !didCapture else { return }
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        guard matchesBoundDevice(device) else { return }

        let reportID = UInt32(IOHIDElementGetReportID(element))
        let input = GenericHIDInputDescriptor(
            usagePage: IOHIDElementGetUsagePage(element),
            usage: IOHIDElementGetUsage(element),
            reportID: reportID == 0 ? nil : reportID,
            collectionPath: collectionPath(for: element)
        )
        let runtimeElement = GenericHIDRuntimeElementDescriptor(
            input: input,
            cookie: UInt64(IOHIDElementGetCookie(element)),
            isRelative: IOHIDElementIsRelative(element),
            matchingElementCount: matchingElementCount(for: element, input: input)
        )
        guard runtimeElement.persistentInput != nil else { return }

        let interfaceID = UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
        guard let event = GenericHIDEventNormalizer.normalize(
            GenericHIDRawValue(
                sessionDeviceID: "generic-learn:\(String(interfaceID, radix: 16))",
                element: runtimeElement,
                value: IOHIDValueGetIntegerValue(value)
            )
        ) else { return }

        guard case let .captured(candidate) = learnSession.observe(event),
              let bindingKey = candidate.persistentBindingKey
        else { return }

        didCapture = true
        onCaptured?(bindingKey)
    }

    private func matchesBoundDevice(_ device: IOHIDDevice) -> Bool {
        guard let expectedSerial = binding.serialNumber else { return false }
        let vendorID = (property(device, kIOHIDVendorIDKey) as? NSNumber)?.intValue ?? 0
        let productID = (property(device, kIOHIDProductIDKey) as? NSNumber)?.intValue ?? 0
        let serial = (property(device, kIOHIDSerialNumberKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return vendorID == binding.vendorID
            && productID == binding.productID
            && serial == expectedSerial
    }

    private func collectionPath(for element: IOHIDElement) -> [HIDUsage] {
        var path: [HIDUsage] = []
        var parent = IOHIDElementGetParent(element)
        while let current = parent {
            path.append(
                HIDUsage(
                    page: IOHIDElementGetUsagePage(current),
                    usage: IOHIDElementGetUsage(current)
                )
            )
            parent = IOHIDElementGetParent(current)
        }
        return path.reversed()
    }

    private func matchingElementCount(
        for element: IOHIDElement,
        input: GenericHIDInputDescriptor
    ) -> Int? {
        let device = IOHIDElementGetDevice(element)
        guard let elements = IOHIDDeviceCopyMatchingElements(
            device,
            nil,
            IOOptionBits(kIOHIDOptionsTypeNone)
        ) as? [IOHIDElement] else { return nil }
        return elements.filter { candidate in
            let reportID = UInt32(IOHIDElementGetReportID(candidate))
            return GenericHIDInputDescriptor(
                usagePage: IOHIDElementGetUsagePage(candidate),
                usage: IOHIDElementGetUsage(candidate),
                reportID: reportID == 0 ? nil : reportID,
                collectionPath: collectionPath(for: candidate)
            ) == input
        }.count
    }

    private func property(_ device: IOHIDDevice, _ key: String) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }
}

private func genericLearnInputValueReceived(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard let context else { return }
    Unmanaged<GenericHIDLearnMonitor>.fromOpaque(context).takeUnretainedValue()
        .didReceiveValue(result: result, value: value)
}

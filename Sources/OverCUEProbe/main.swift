import CoreFoundation
import Darwin
import Foundation
import IOKit.hid

private enum ACK05 {
    static let vendorID = 0x28BD
    static let productID = 0x0202
}

private struct Options {
    var matchAllDevices = false
    var seizeDevice = false

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()

        for argument in arguments.dropFirst() {
            switch argument {
            case "--all":
                options.matchAllDevices = true
            case "--seize":
                options.seizeDevice = true
            case "--help", "-h":
                printUsage()
                exit(EXIT_SUCCESS)
            default:
                throw ProbeError.invalidArgument(argument)
            }
        }

        guard !(options.matchAllDevices && options.seizeDevice) else {
            throw ProbeError.incompatibleArguments("--all cannot be combined with --seize")
        }

        return options
    }

    static func printUsage() {
        print(
            """
            Usage: overcue-probe [options]

            Observe HID reports and element values from the XPPen ACK05.

            Options:
              --all       Observe every HID device instead of ACK05 only.
              --seize     Open matching devices exclusively and suppress their OS input.
              -h, --help  Show this help.

            The default target is VID 0x28BD / PID 0x0202. Press Control-C to stop.
            """
        )
    }
}

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case incompatibleArguments(String)
    case managerOpenFailed(IOReturn)

    var description: String {
        switch self {
        case let .invalidArgument(argument):
            return "Unknown argument: \(argument)"
        case let .incompatibleArguments(message):
            return message
        case let .managerOpenFailed(result):
            if result == kIOReturnNotPermitted {
                return "HID access was denied by macOS. Grant Input Monitoring permission "
                    + "to the terminal running this command in System Settings > Privacy & Security, "
                    + "then restart that terminal."
            }
            return "Could not open IOHIDManager (IOReturn \(formatIOReturn(result)))."
        }
    }
}

private final class HIDProbe {
    private let manager: IOHIDManager
    private let options: Options
    private let timestampFormatter = ISO8601DateFormatter()

    init(options: Options) throws {
        self.options = options
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let context = Unmanaged.passUnretained(self).toOpaque()

        if options.matchAllDevices {
            IOHIDManagerSetDeviceMatching(manager, nil)
        } else {
            let matching: [String: Any] = [
                kIOHIDVendorIDKey as String: ACK05.vendorID,
                kIOHIDProductIDKey as String: ACK05.productID,
            ]
            IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        }

        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemoved, context)
        IOHIDManagerRegisterInputReportCallback(manager, inputReportReceived, context)
        IOHIDManagerRegisterInputValueCallback(manager, inputValueReceived, context)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetCurrent(),
            CFRunLoopMode.defaultMode.rawValue
        )
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetCurrent(),
            CFRunLoopMode.defaultMode.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func run() throws -> Never {
        let openOptions = options.seizeDevice
            ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
            : IOOptionBits(kIOHIDOptionsTypeNone)
        let result = IOHIDManagerOpen(manager, openOptions)

        guard result == kIOReturnSuccess else {
            throw ProbeError.managerOpenFailed(result)
        }

        if options.matchAllDevices {
            log("Listening to all HID devices.")
        } else {
            log(
                String(
                    format: "Looking for ACK05 (VID 0x%04X / PID 0x%04X).",
                    ACK05.vendorID,
                    ACK05.productID
                )
            )
        }

        if options.seizeDevice {
            log("Exclusive mode is ON; matching device input is suppressed system-wide.")
        } else {
            log("Shared mode is ON; matching device input can still reach macOS and other apps.")
        }
        log("Rotate the dial and press K1-K10. Press Control-C to stop.")

        CFRunLoopRun()
        exit(EXIT_SUCCESS)
    }

    func didMatch(device: IOHIDDevice, result: IOReturn) {
        guard result == kIOReturnSuccess else {
            log("Device match callback failed: \(formatIOReturn(result))")
            return
        }

        let identity = deviceIdentity(device)
        log("CONNECTED \(identity)")
        log(
            "  transport=\(propertyString(device, kIOHIDTransportKey)) "
                + "usagePage=\(propertyNumber(device, kIOHIDPrimaryUsagePageKey)) "
                + "usage=\(propertyNumber(device, kIOHIDPrimaryUsageKey))"
        )
        log(
            "  serialNumber=\(propertyDescription(device, "SerialNumber")) "
                + "physicalDeviceUniqueID=\(propertyDescription(device, "PhysicalDeviceUniqueID"))"
        )
        log(
            "  locationID=\(propertyDescription(device, "LocationID")) "
                + "deviceAddress=\(propertyDescription(device, "DeviceAddress"))"
        )
    }

    func didRemove(device: IOHIDDevice, result: IOReturn) {
        guard result == kIOReturnSuccess else {
            log("Device removal callback failed: \(formatIOReturn(result))")
            return
        }

        log("DISCONNECTED \(deviceIdentity(device))")
    }

    func didReceiveReport(
        result: IOReturn,
        sender: UnsafeMutableRawPointer?,
        reportType: IOHIDReportType,
        reportID: UInt32,
        report: UnsafeMutablePointer<UInt8>,
        reportLength: CFIndex
    ) {
        guard result == kIOReturnSuccess else {
            log("Input report failed: \(formatIOReturn(result))")
            return
        }

        let length = max(0, Int(reportLength))
        let bytes = UnsafeBufferPointer(start: report, count: length)
            .map { String(format: "%02X", $0) }
            .joined(separator: " ")
        let device = sender.map { Unmanaged<IOHIDDevice>.fromOpaque($0).takeUnretainedValue() }
        let source = device.map(deviceIdentity) ?? "unknown-device"

        log(
            "REPORT source={\(source)} type=\(reportTypeName(reportType)) "
                + "id=\(reportID) length=\(length) bytes=[\(bytes)]"
        )
    }

    func didReceiveValue(result: IOReturn, value: IOHIDValue) {
        guard result == kIOReturnSuccess else {
            log("Input value failed: \(formatIOReturn(result))")
            return
        }

        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let integerValue = IOHIDValueGetIntegerValue(value)
        let label = usageName(page: usagePage, usage: usage)

        log(
            String(
                format: "VALUE source={%@} page=0x%04X usage=0x%04X (%@) value=%lld",
                deviceIdentity(device),
                usagePage,
                usage,
                label,
                Int64(integerValue)
            )
        )
    }

    private func log(_ message: String) {
        let line = "[\(timestampFormatter.string(from: Date()))] \(message)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
    }

    private func deviceIdentity(_ device: IOHIDDevice) -> String {
        let product = propertyString(device, kIOHIDProductKey)
        let manufacturer = propertyString(device, kIOHIDManufacturerKey)
        let vendorID = propertyInt(device, kIOHIDVendorIDKey)
        let productID = propertyInt(device, kIOHIDProductIDKey)

        return String(
            format: "%@ / %@ VID=0x%04X PID=0x%04X",
            manufacturer,
            product,
            vendorID,
            productID
        )
    }
}

private func deviceMatched(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<HIDProbe>.fromOpaque(context).takeUnretainedValue()
        .didMatch(device: device, result: result)
}

private func deviceRemoved(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<HIDProbe>.fromOpaque(context).takeUnretainedValue()
        .didRemove(device: device, result: result)
}

private func inputReportReceived(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    reportType: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context else { return }
    Unmanaged<HIDProbe>.fromOpaque(context).takeUnretainedValue().didReceiveReport(
        result: result,
        sender: sender,
        reportType: reportType,
        reportID: reportID,
        report: report,
        reportLength: reportLength
    )
}

private func inputValueReceived(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard let context else { return }
    Unmanaged<HIDProbe>.fromOpaque(context).takeUnretainedValue()
        .didReceiveValue(result: result, value: value)
}

private func property(_ device: IOHIDDevice, _ key: String) -> Any? {
    IOHIDDeviceGetProperty(device, key as CFString)
}

private func propertyString(_ device: IOHIDDevice, _ key: String) -> String {
    property(device, key) as? String ?? "unknown"
}

private func propertyInt(_ device: IOHIDDevice, _ key: String) -> Int {
    (property(device, key) as? NSNumber)?.intValue ?? 0
}

private func propertyNumber(_ device: IOHIDDevice, _ key: String) -> String {
    guard let number = property(device, key) as? NSNumber else { return "unknown" }
    return String(format: "0x%04X", number.intValue)
}

private func propertyDescription(_ device: IOHIDDevice, _ key: String) -> String {
    guard let value = property(device, key) else { return "unavailable" }
    return String(describing: value)
}

private func reportTypeName(_ type: IOHIDReportType) -> String {
    switch type {
    case kIOHIDReportTypeInput:
        return "input"
    case kIOHIDReportTypeOutput:
        return "output"
    case kIOHIDReportTypeFeature:
        return "feature"
    default:
        return "unknown(\(type.rawValue))"
    }
}

private func usageName(page: UInt32, usage: UInt32) -> String {
    guard page == 0x07 else {
        return "usage-page-\(page)"
    }

    let keyboardUsages: [UInt32: String] = [
        0x04: "Keyboard A",
        0x11: "Keyboard N",
        0x12: "Keyboard O",
        0x16: "Keyboard S",
        0x1D: "Keyboard Z",
        0x2C: "Space",
        0x3E: "F5",
        0x56: "Keypad -",
        0x57: "Keypad +",
        0xE0: "Left Control",
        0xE1: "Left Shift",
        0xE2: "Left Alt/Option",
    ]
    return keyboardUsages[usage] ?? "Keyboard usage \(usage)"
}

private func formatIOReturn(_ result: IOReturn) -> String {
    String(format: "0x%08X", UInt32(bitPattern: result))
}

do {
    let options = try Options.parse(CommandLine.arguments)
    let probe = try HIDProbe(options: options)
    try probe.run()
} catch let error as ProbeError {
    fputs("overcue-probe: \(error)\n", stderr)
    Options.printUsage()
    exit(EXIT_FAILURE)
} catch {
    fputs("overcue-probe: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}

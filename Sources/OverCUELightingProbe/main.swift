import CoreFoundation
import Darwin
import Foundation
import IOKit.hid

private enum TargetDevice {
    static let vendorID = 0x0816
    static let productID = 0x246E
    static let usagePage = 0xFF00
    static let usage = 0x0002
    static let productName = "SIDE-KEYBOARD"
    static let reportID: CFIndex = 0
    static let reportLength = 64
}

private struct Options {
    let serial: String

    static func parse(_ arguments: [String]) throws -> Options {
        var serial: String?
        var requestedLightingGet = false
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--get-lighting":
                requestedLightingGet = true
            case "--serial":
                index += 1
                guard index < arguments.count else {
                    throw ProbeError.missingValue(argument)
                }
                serial = arguments[index]
            case "--help", "-h":
                printUsage()
                exit(EXIT_SUCCESS)
            default:
                throw ProbeError.invalidArgument(argument)
            }
            index += 1
        }

        guard requestedLightingGet else {
            throw ProbeError.invalidArgument("--get-lighting is required")
        }
        guard let serial, !serial.isEmpty else {
            throw ProbeError.invalidArgument("--serial is required")
        }

        return Options(serial: serial)
    }

    static func printUsage() {
        print(
            """
            Usage:
              overcue-led-probe --get-lighting --serial <SERIAL>

            Sends exactly one known SDTech Option lighting-settings query to one SIDE-KEYBOARD:
              VID 0x0816 / PID 0x246E / Usage Page 0xFF00 / Usage 0x0002
              Output Report ID 0, payload: 06 0A followed by 62 zero bytes

            Safety properties:
              - Serial is mandatory.
              - Device identity and Vendor Defined interface are fixed in code.
              - A 64-byte Output report capability is required before sending.
              - There is no arbitrary HID write mode.
              - The command is sent once; there is no retry.
            """
        )
    }
}

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case missingValue(String)
    case managerOpenFailed(IOReturn)
    case targetNotFound(String)
    case reportCapabilityMismatch
    case reportWriteFailed(IOReturn)
    case responseTimeout

    var description: String {
        switch self {
        case let .invalidArgument(argument):
            return "Invalid argument: \(argument)"
        case let .missingValue(argument):
            return "Missing value for \(argument)"
        case let .managerOpenFailed(result):
            return "Could not open IOHIDManager (IOReturn \(formatIOReturn(result)))."
        case let .targetNotFound(serial):
            return "No matching SIDE-KEYBOARD Vendor Defined interface found for serial \(serial)."
        case .reportCapabilityMismatch:
            return "Target interface does not expose the expected 64-byte Output Report ID 0. Nothing was sent."
        case let .reportWriteFailed(result):
            return "Lighting query write failed (IOReturn \(formatIOReturn(result)))."
        case .responseTimeout:
            return "The lighting query was sent once, but no matching input response arrived before timeout."
        }
    }
}

private final class LightingQueryProbe {
    private let options: Options
    private let manager: IOHIDManager
    private let timestampFormatter = ISO8601DateFormatter()
    private var didFindTarget = false
    private var didSend = false
    private var didReceiveResponse = false
    private var failure: ProbeError?

    init(options: Options) {
        self.options = options
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: TargetDevice.vendorID,
            kIOHIDProductIDKey as String: TargetDevice.productID,
            kIOHIDPrimaryUsagePageKey as String: TargetDevice.usagePage,
            kIOHIDPrimaryUsageKey as String: TargetDevice.usage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatched, context)
        IOHIDManagerRegisterInputReportCallback(manager, inputReportReceived, context)
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

    func run() throws {
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw ProbeError.managerOpenFailed(result)
        }

        log("One-shot lighting query armed for serial=\(options.serial).")
        log("Fixed target: VID=0x0816 PID=0x246E page=0xFF00 usage=0x0002 reportID=0 length=64.")
        log("Payload is fixed to [06 0A] + 62 zero bytes; automatic retry is disabled.")

        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline, failure == nil, !didReceiveResponse {
            RunLoop.current.run(mode: .default, before: deadline)
        }

        if let failure {
            throw failure
        }
        guard didFindTarget else {
            throw ProbeError.targetNotFound(options.serial)
        }
        guard didSend else {
            throw ProbeError.reportCapabilityMismatch
        }
        guard didReceiveResponse else {
            throw ProbeError.responseTimeout
        }
    }

    fileprivate func didMatch(device: IOHIDDevice, result: IOReturn) {
        guard result == kIOReturnSuccess, failure == nil, !didSend else { return }
        guard propertyString(device, kIOHIDSerialNumberKey) == options.serial else { return }
        guard propertyString(device, kIOHIDProductKey) == TargetDevice.productName else { return }
        guard propertyInt(device, kIOHIDVendorIDKey) == TargetDevice.vendorID,
              propertyInt(device, kIOHIDProductIDKey) == TargetDevice.productID,
              propertyInt(device, kIOHIDPrimaryUsagePageKey) == TargetDevice.usagePage,
              propertyInt(device, kIOHIDPrimaryUsageKey) == TargetDevice.usage else {
            return
        }

        didFindTarget = true
        log("Matched exact SIDE-KEYBOARD Vendor Defined interface for serial=\(options.serial).")

        guard outputReportLength(device: device, reportID: 0) >= TargetDevice.reportLength else {
            failure = .reportCapabilityMismatch
            return
        }

        var payload = [UInt8](repeating: 0, count: TargetDevice.reportLength)
        payload[0] = 0x06
        payload[1] = 0x0A

        let writeResult = payload.withUnsafeBufferPointer { buffer -> IOReturn in
            guard let baseAddress = buffer.baseAddress else {
                return kIOReturnBadArgument
            }
            return IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                TargetDevice.reportID,
                baseAddress,
                CFIndex(buffer.count)
            )
        }

        guard writeResult == kIOReturnSuccess else {
            failure = .reportWriteFailed(writeResult)
            return
        }

        didSend = true
        log("SENT ONCE reportID=0 length=64 bytes=[06 0A 00 ... 00].")
    }

    fileprivate func didReceiveReport(
        result: IOReturn,
        sender: UnsafeMutableRawPointer?,
        reportType: IOHIDReportType,
        reportID: UInt32,
        report: UnsafeMutablePointer<UInt8>,
        reportLength: CFIndex
    ) {
        guard result == kIOReturnSuccess,
              didSend,
              !didReceiveResponse,
              reportType == kIOHIDReportTypeInput,
              reportID == 0,
              let sender else {
            return
        }

        let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
        guard propertyString(device, kIOHIDSerialNumberKey) == options.serial,
              propertyInt(device, kIOHIDVendorIDKey) == TargetDevice.vendorID,
              propertyInt(device, kIOHIDProductIDKey) == TargetDevice.productID,
              propertyInt(device, kIOHIDPrimaryUsagePageKey) == TargetDevice.usagePage,
              propertyInt(device, kIOHIDPrimaryUsageKey) == TargetDevice.usage else {
            return
        }

        let length = max(0, Int(reportLength))
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        log("RESPONSE reportID=0 length=\(length) bytes=[\(hex)]")

        if bytes.count >= 16 {
            let settings = bytes[5...15].map { String(format: "%02X", $0) }.joined(separator: " ")
            log("RESPONSE offsets[5...15]=[\(settings)]")
        }

        didReceiveResponse = true
    }

    private func log(_ message: String) {
        let line = "[\(timestampFormatter.string(from: Date()))] \(message)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
    }
}

private func outputReportLength(device: IOHIDDevice, reportID: UInt32) -> Int {
    guard let elements = IOHIDDeviceCopyMatchingElements(
        device,
        nil,
        IOOptionBits(kIOHIDOptionsTypeNone)
    ) as? [IOHIDElement] else {
        return 0
    }

    let totalBits = elements.reduce(into: 0) { bits, element in
        guard IOHIDElementGetType(element) == kIOHIDElementTypeOutput,
              UInt32(IOHIDElementGetReportID(element)) == reportID else {
            return
        }
        bits += Int(IOHIDElementGetReportSize(element)) * Int(IOHIDElementGetReportCount(element))
    }
    return (totalBits + 7) / 8
}

private func deviceMatched(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<LightingQueryProbe>.fromOpaque(context).takeUnretainedValue()
        .didMatch(device: device, result: result)
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
    Unmanaged<LightingQueryProbe>.fromOpaque(context).takeUnretainedValue()
        .didReceiveReport(
            result: result,
            sender: sender,
            reportType: reportType,
            reportID: reportID,
            report: report,
            reportLength: reportLength
        )
}

private func property(_ device: IOHIDDevice, _ key: String) -> Any? {
    IOHIDDeviceGetProperty(device, key as CFString)
}

private func propertyString(_ device: IOHIDDevice, _ key: String) -> String {
    property(device, key) as? String ?? ""
}

private func propertyInt(_ device: IOHIDDevice, _ key: String) -> Int {
    (property(device, key) as? NSNumber)?.intValue ?? 0
}

private func formatIOReturn(_ result: IOReturn) -> String {
    String(format: "0x%08X", UInt32(bitPattern: result))
}

do {
    let options = try Options.parse(CommandLine.arguments)
    let probe = LightingQueryProbe(options: options)
    try probe.run()
} catch let error as ProbeError {
    fputs("overcue-led-probe: \(error)\n", stderr)
    Options.printUsage()
    exit(EXIT_FAILURE)
} catch {
    fputs("overcue-led-probe: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}

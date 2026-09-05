import CoreFoundation
import Darwin
import Dispatch
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

private enum Query: String {
    case lighting = "--get-lighting"
    case rgb = "--get-rgb"

    var payload: [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 64)
        bytes[0] = 0x06
        bytes[1] = self == .rgb ? 0x13 : 0x0A
        if self == .rgb { bytes[2] = 0x3A }
        return bytes
    }
}

private struct Options {
    let serial: String
    let query: Query

    static func parse(_ arguments: [String]) throws -> Options {
        var serial: String?
        var query: Query?
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--get-lighting", "--get-rgb":
                guard query == nil else {
                    throw ProbeError.invalidArgument("Select exactly one getter")
                }
                query = Query(rawValue: argument)
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

        guard let query else {
            throw ProbeError.invalidArgument("--get-lighting or --get-rgb is required")
        }
        guard let serial, !serial.isEmpty else {
            throw ProbeError.invalidArgument("--serial is required")
        }

        if query == .rgb, serial != "592B14678182" {
            throw ProbeError.invalidArgument("RGB getter is restricted to serial 592B14678182")
        }
        return Options(serial: serial, query: query)
    }

    static func printUsage() {
        print(
            """
            Usage:
              overcue-led-probe --get-lighting --serial <SERIAL>
              overcue-led-probe --get-rgb --serial 592B14678182

            Sends exactly one selected, known SDTech Option getter to one SIDE-KEYBOARD:
              VID 0x0816 / PID 0x246E / Usage Page 0xFF00 / Usage 0x0002
              Output Report ID 0:
                --get-lighting: 06 0A followed by 62 zero bytes
                --get-rgb: 06 13 3A followed by 61 zero bytes (first chunk only)

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
            return "Getter write failed (IOReturn \(formatIOReturn(result)))."
        case .responseTimeout:
            return "The getter was sent once, but no matching input response arrived before timeout."
        }
    }
}

private final class LightingQueryProbe {
    private let options: Options
    private let manager: IOHIDManager
    private let timestampFormatter = ISO8601DateFormatter()
    private var didFindTarget = false
    private var didSend = false
    private var didAttemptSend = false
    private var target: IOHIDDevice?
    private var sendStartedAt: UInt64?
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

        log("One-shot \(options.query.rawValue) query armed for serial=\(options.serial).")
        log("Fixed target: VID=0x0816 PID=0x246E page=0xFF00 usage=0x0002 reportID=0 length=64.")
        log("Selected getter has a fixed payload; automatic retry is disabled.")

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
        guard result == kIOReturnSuccess, failure == nil, !didAttemptSend else { return }
        guard propertyString(device, kIOHIDSerialNumberKey) == options.serial else { return }
        guard propertyString(device, kIOHIDProductKey) == TargetDevice.productName else { return }
        guard propertyString(device, kIOHIDManufacturerKey) == "SDINNOVATION" else { return }
        guard propertyInt(device, kIOHIDVendorIDKey) == TargetDevice.vendorID,
              propertyInt(device, kIOHIDProductIDKey) == TargetDevice.productID,
              propertyInt(device, kIOHIDPrimaryUsagePageKey) == TargetDevice.usagePage,
              propertyInt(device, kIOHIDPrimaryUsageKey) == TargetDevice.usage else {
            return
        }

        didFindTarget = true
        log("Matched exact SIDE-KEYBOARD Vendor Defined interface for serial=\(options.serial).")

        guard outputReportLength(device: device, reportID: 0) == TargetDevice.reportLength else {
            failure = .reportCapabilityMismatch
            return
        }

        let payload = options.query.payload

        target = device
        didAttemptSend = true
        log("Verified descriptor: Output Report ID 0 length=64; manufacturer=SDINNOVATION product=SIDE-KEYBOARD serial=\(options.serial).")
        log("SEND ATTEMPT 1 bytes=[\(payload.map { String(format: "%02X", $0) }.joined(separator: " "))]")
        sendStartedAt = DispatchTime.now().uptimeNanoseconds

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

        log("IOHIDDeviceSetReport returned \(formatIOReturn(writeResult)).")

        guard writeResult == kIOReturnSuccess else {
            failure = .reportWriteFailed(writeResult)
            return
        }

        didSend = true
        log("SENT ONCE reportID=0 length=64 query=\(options.query.rawValue).")
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
        guard let target, CFEqual(device, target),
              propertyString(device, kIOHIDProductKey) == TargetDevice.productName,
              propertyString(device, kIOHIDSerialNumberKey) == options.serial,
              propertyInt(device, kIOHIDVendorIDKey) == TargetDevice.vendorID,
              propertyInt(device, kIOHIDProductIDKey) == TargetDevice.productID,
              propertyInt(device, kIOHIDPrimaryUsagePageKey) == TargetDevice.usagePage,
              propertyInt(device, kIOHIDPrimaryUsageKey) == TargetDevice.usage else {
            return
        }

        let length = max(0, Int(reportLength))
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        if let sendStartedAt {
            let latency = Double(DispatchTime.now().uptimeNanoseconds - sendStartedAt) / 1_000_000
            log(String(format: "RESPONSE latencyFromSetReportStartMs=%.3f", latency))
        }
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

func outputReportLength(device: IOHIDDevice, reportID: UInt32) -> Int {
    // IOHID elements expand arrays into overlapping entries. Sum descriptor
    // Output items (including padding), not the expanded element sizes.
    guard let data = property(device, "ReportDescriptor") as? Data else { return 0 }
    return outputReportLength(descriptor: Array(data), reportID: reportID)
}

private func outputReportLength(descriptor: [UInt8], reportID: UInt32) -> Int {
    var size = 0
    var count = 0
    var currentID: UInt32 = 0
    var stack: [(Int, Int, UInt32)] = []
    var totalBits = 0
    var index = 0
    while index < descriptor.count {
        let prefix = descriptor[index]
        index += 1
        guard prefix != 0xFE else { return 0 } // Unsupported long item: fail closed.
        let length = [0, 1, 2, 4][Int(prefix & 3)]
        guard index + length <= descriptor.count else { return 0 }
        var value: UInt32 = 0
        for byte in 0..<length {
            value |= UInt32(descriptor[index + byte]) << (8 * byte)
        }
        index += length
        let type = (prefix >> 2) & 3
        let tag = prefix >> 4
        if type == 1 {
            switch tag {
            case 7: size = Int(value)
            case 8:
                guard value > 0, value <= 255 else { return 0 }
                currentID = value
            case 9: count = Int(value)
            case 10: stack.append((size, count, currentID))
            case 11:
                guard let state = stack.popLast() else { return 0 }
                (size, count, currentID) = state
            default: break
            }
        } else if type == 0, tag == 9, currentID == reportID {
            // Bound arithmetic for this fixed 64-byte query target.
            guard size > 0, count > 0, size <= 512, count <= 512 else { return 0 }
            totalBits += size * count
            guard totalBits <= 512 else { return 0 }
        }
    }
    guard stack.isEmpty, totalBits % 8 == 0 else { return 0 }
    return totalBits / 8
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

if CommandLine.arguments == [CommandLine.arguments[0], "--walk-key-indices"] {
    exit(KeyIndexWalk.run() ? EXIT_SUCCESS : EXIT_FAILURE)
}

if CommandLine.arguments == [CommandLine.arguments[0], "--breathing-play-pause-phase-a"] {
    exit(LiveRGBTest(serial: BreathingPlayPauseTrial.serial).runSession {
        BreathingPlayPauseTrial.run(send: $0)
    } ? EXIT_SUCCESS : EXIT_FAILURE)
}

if CommandLine.arguments == [CommandLine.arguments[0], "--breathing-play-pause-phase-b"] {
    exit(LiveRGBTest(serial: BreathingPlayPauseTrial.serial).runSession {
        BreathingPlayPauseTrial.runPhaseB(send: $0)
    } ? EXIT_SUCCESS : EXIT_FAILURE)
}

if CommandLine.arguments == [CommandLine.arguments[0], "--breathing-play-pause-rollback"] {
    exit(LiveRGBTest(serial: BreathingPlayPauseTrial.serial).runSession {
        BreathingPlayPauseTrial.rollback(send: $0)
    } ? EXIT_SUCCESS : EXIT_FAILURE)
}

if CommandLine.arguments == [CommandLine.arguments[0], "--binary-play-pause-pause"] {
    exit(LiveRGBTest(serial: BreathingPlayPauseTrial.serial).runSession {
        BreathingPlayPauseTrial.setBinaryMode(0, name: "pause", send: $0)
    } ? EXIT_SUCCESS : EXIT_FAILURE)
}

if CommandLine.arguments == [CommandLine.arguments[0], "--binary-play-pause-play"] {
    exit(LiveRGBTest(serial: BreathingPlayPauseTrial.serial).runSession {
        BreathingPlayPauseTrial.setBinaryMode(5, name: "play", send: $0)
    } ? EXIT_SUCCESS : EXIT_FAILURE)
}

let officialModeCommands: [String: UInt8] = [
    "--official-mode-0": 0,
    "--official-mode-1": 1,
    "--official-mode-2": 2,
    "--official-mode-3": 3,
    "--official-mode-4": 4,
    "--official-mode-5": 5,
]
if CommandLine.arguments.count == 2,
   let mode = officialModeCommands[CommandLine.arguments[1]] {
    exit(LiveRGBTest(serial: BreathingPlayPauseTrial.serial).runSession {
        BreathingPlayPauseTrial.setOfficialMode(mode, send: $0)
    } ? EXIT_SUCCESS : EXIT_FAILURE)
}

let officialSingleRedCommands: [String: UInt8] = [
    "--official-mode2-single-red": 2,
    "--official-mode3-single-red": 3,
]
if CommandLine.arguments.count == 2,
   let mode = officialSingleRedCommands[CommandLine.arguments[1]] {
    exit(LiveRGBTest(serial: BreathingPlayPauseTrial.serial).runSession {
        BreathingPlayPauseTrial.setSingleRed(mode, send: $0)
    } ? EXIT_SUCCESS : EXIT_FAILURE)
}

// Getter-only snapshot of the three known devices; first RGB chunk only.
if CommandLine.arguments == [CommandLine.arguments[0], "--read-three-lighting-rgb"] {
    var success = true
    for (serial, _) in ThreeSingleLights.targets {
        let captured = LiveRGBTest(serial: serial).runSession { send in
            let light = send("read-lighting", LiveRGBPlan.lightingGet)
            let rgb = send("read-rgb", LiveRGBPlan.rgbGet)
            return light != nil && rgb != nil
        }
        if !captured { success = false }
    }
    exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
}

if CommandLine.arguments == [CommandLine.arguments[0], "--set-three-deck-steady-colors"] {
    exit(ThreeDeckSteadyColors.run() ? EXIT_SUCCESS : EXIT_FAILURE)
}

if CommandLine.arguments == [CommandLine.arguments[0], "--three-single-lights"] {
    exit(ThreeSingleLights.run() ? EXIT_SUCCESS : EXIT_FAILURE)
}

if CommandLine.arguments.contains("--live-rgb-roundtrip") {
    guard CommandLine.arguments == [CommandLine.arguments[0], "--live-rgb-roundtrip", "--serial", "592B14678182"] else {
        fputs("Live test accepts only --live-rgb-roundtrip --serial 592B14678182\n", stderr)
        exit(EXIT_FAILURE)
    }
    exit(LiveRGBTest().run() ? EXIT_SUCCESS : EXIT_FAILURE)
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

import CoreFoundation
import Darwin
import Foundation
import IOKit.hid
import OverCUECore

private enum ACK05 {
    static let vendorID = 0x28BD
    static let productID = 0x0202
}

private enum ProbeMode {
    case observe
    case list
    case describe
}

private struct Options {
    var mode: ProbeMode = .observe
    var matchAllDevices = false
    var seizeDevice = false
    var vendorID: Int?
    var productID: Int?

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--all":
                options.matchAllDevices = true
            case "--seize":
                options.seizeDevice = true
            case "--list":
                try options.setMode(.list, argument: argument)
            case "--describe":
                try options.setMode(.describe, argument: argument)
            case "--vid":
                index += 1
                guard index < arguments.count else {
                    throw ProbeError.missingValue(argument)
                }
                options.vendorID = try parseInteger(arguments[index], for: argument)
            case "--pid":
                index += 1
                guard index < arguments.count else {
                    throw ProbeError.missingValue(argument)
                }
                options.productID = try parseInteger(arguments[index], for: argument)
            case "--help", "-h":
                printUsage()
                exit(EXIT_SUCCESS)
            default:
                throw ProbeError.invalidArgument(argument)
            }
            index += 1
        }

        guard !(options.matchAllDevices && options.seizeDevice) else {
            throw ProbeError.incompatibleArguments("--all cannot be combined with --seize")
        }
        guard !(options.matchAllDevices && (options.vendorID != nil || options.productID != nil)) else {
            throw ProbeError.incompatibleArguments("--all cannot be combined with --vid or --pid")
        }
        guard !(options.mode != .observe && options.seizeDevice) else {
            throw ProbeError.incompatibleArguments("--seize is only available in observe mode")
        }

        return options
    }

    static func printUsage() {
        print(
            """
            Usage: overcue-probe [options]

            Observe HID input or inspect connected HID devices without modifying them.

            Modes:
              --list       List matching HID interfaces, then exit.
              --describe   Print HID element/report capabilities for matching devices, then exit.

            Matching:
              --all        Match every HID device, including Generic HID candidates.
              --vid VALUE  Match a vendor ID (decimal or 0x-prefixed hex).
              --pid VALUE  Match a product ID (decimal or 0x-prefixed hex).

            Observe-only options:
              --seize      Open matching devices exclusively and suppress their OS input.

            General:
              -h, --help   Show this help.

            With no matching options, the target is ACK05 (VID 0x28BD / PID 0x0202).
            --list and --describe are read-only and never send Output or Feature reports.
            """
        )
    }

    private mutating func setMode(_ newMode: ProbeMode, argument: String) throws {
        guard mode == .observe else {
            throw ProbeError.incompatibleArguments("Only one inspection mode can be selected; repeated at \(argument)")
        }
        mode = newMode
    }

    private static func parseInteger(_ value: String, for argument: String) throws -> Int {
        let parsed: Int?
        if value.lowercased().hasPrefix("0x") {
            parsed = Int(value.dropFirst(2), radix: 16)
        } else {
            parsed = Int(value)
        }
        guard let parsed, parsed >= 0, parsed <= 0xFFFF else {
            throw ProbeError.invalidValue(argument: argument, value: value)
        }
        return parsed
    }
}

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case incompatibleArguments(String)
    case missingValue(String)
    case invalidValue(argument: String, value: String)
    case managerOpenFailed(IOReturn)

    var description: String {
        switch self {
        case let .invalidArgument(argument):
            return "Unknown argument: \(argument)"
        case let .incompatibleArguments(message):
            return message
        case let .missingValue(argument):
            return "Missing value for \(argument)"
        case let .invalidValue(argument, value):
            return "Invalid value for \(argument): \(value)"
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

private struct HIDReportCapability {
    let type: IOHIDReportType
    let reportID: UInt32
    let byteLength: Int
}

private final class HIDProbe {
    private let manager: IOHIDManager
    private let options: Options
    private let timestampFormatter = ISO8601DateFormatter()
    private var registry = HIDDeviceRegistry()

    init(options: Options) throws {
        self.options = options
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerSetDeviceMatching(manager, matchingDictionary(for: options))
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemoved, context)

        if options.mode == .observe {
            IOHIDManagerRegisterInputReportCallback(manager, inputReportReceived, context)
            IOHIDManagerRegisterInputValueCallback(manager, inputValueReceived, context)
        }

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

        switch options.mode {
        case .observe:
            logTargetSummary(prefix: "Looking for")
            if options.seizeDevice {
                log("Exclusive mode is ON; matching device input is suppressed system-wide.")
            } else {
                log("Shared mode is ON; matching device input can still reach macOS and other apps.")
            }
            log("Press controls on the target device. Press Control-C to stop.")
            CFRunLoopRun()
        case .list:
            logTargetSummary(prefix: "Listing")
            runInspectionWindow()
        case .describe:
            logTargetSummary(prefix: "Describing")
            log("Read-only inspection: no Output or Feature report will be sent.")
            runInspectionWindow()
        }

        exit(EXIT_SUCCESS)
    }

    func didMatch(device: IOHIDDevice, result: IOReturn) {
        guard result == kIOReturnSuccess else {
            log("Device match callback failed: \(formatIOReturn(result))")
            return
        }

        let descriptor = physicalDescriptor(device)
        registry.deviceConnected(descriptor)

        switch options.mode {
        case .observe:
            log("CONNECTED session=\(descriptor.sessionIdentifier) \(deviceIdentity(device))")
            logBasicProperties(device)
        case .list:
            log("DEVICE session=\(descriptor.sessionIdentifier) \(deviceIdentity(device))")
            log(
                "  transport=\(propertyString(device, kIOHIDTransportKey)) "
                    + "serial=\(propertyDescription(device, "SerialNumber")) "
                    + "usagePage=\(propertyNumber(device, kIOHIDPrimaryUsagePageKey)) "
                    + "usage=\(propertyNumber(device, kIOHIDPrimaryUsageKey))"
            )
        case .describe:
            describe(device)
        }
    }

    func didRemove(device: IOHIDDevice, result: IOReturn) {
        guard result == kIOReturnSuccess else {
            log("Device removal callback failed: \(formatIOReturn(result))")
            return
        }

        let descriptor = physicalDescriptor(device)
        registry.deviceDisconnected(sessionIdentifier: descriptor.sessionIdentifier)
        if options.mode == .observe {
            log("DISCONNECTED session=\(descriptor.sessionIdentifier) \(deviceIdentity(device))")
        }
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
        let source = device.map { physicalDescriptor($0).sessionIdentifier } ?? "unknown-device"

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
        let reportID = UInt32(IOHIDElementGetReportID(element))
        let cookie = UInt64(IOHIDElementGetCookie(element))
        let isRelative = IOHIDElementIsRelative(element)
        let sessionIdentifier = physicalDescriptor(device).sessionIdentifier
        let input = GenericHIDInputDescriptor(
            usagePage: usagePage,
            usage: usage,
            reportID: reportID == 0 ? nil : reportID,
            collectionPath: collectionPath(for: element)
        )
        let matchingElementCount = matchingElementCount(for: element, input: input)
        let runtimeElement = GenericHIDRuntimeElementDescriptor(
            input: input,
            cookie: cookie,
            isRelative: isRelative,
            matchingElementCount: matchingElementCount
        )
        let normalized = GenericHIDEventNormalizer.normalize(
            GenericHIDRawValue(
                sessionDeviceID: sessionIdentifier,
                element: runtimeElement,
                value: integerValue
            )
        )
        let normalizedDescription = normalized.map { eventDescription($0.phase) } ?? "ignored-zero"

        log(
            String(
                format: "VALUE session=%@ vid=0x%04X pid=0x%04X page=0x%04X "
                    + "usage=0x%04X (%@) reportID=%u cookie=%llu relative=%@ duplicates=%d "
                    + "persistable=%@ value=%lld event=%@",
                sessionIdentifier,
                propertyInt(device, kIOHIDVendorIDKey),
                propertyInt(device, kIOHIDProductIDKey),
                usagePage,
                usage,
                label,
                reportID,
                cookie,
                isRelative ? "true" : "false",
                matchingElementCount ?? -1,
                runtimeElement.persistentInput == nil ? "false" : "true",
                Int64(integerValue),
                normalizedDescription
            )
        )
    }

    private func runInspectionWindow() {
        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: deadline)
        }
    }

    private func logTargetSummary(prefix: String) {
        if options.matchAllDevices {
            log("\(prefix) all HID devices.")
            return
        }
        let vid = options.vendorID ?? ACK05.vendorID
        let pid = options.productID ?? ACK05.productID
        log(String(format: "%@ HID devices matching VID 0x%04X / PID 0x%04X.", prefix, vid, pid))
    }

    private func logBasicProperties(_ device: IOHIDDevice) {
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

    private func describe(_ device: IOHIDDevice) {
        let descriptor = physicalDescriptor(device)
        log("DEVICE session=\(descriptor.sessionIdentifier) \(deviceIdentity(device))")
        logBasicProperties(device)

        guard let elements = IOHIDDeviceCopyMatchingElements(
            device,
            nil,
            IOOptionBits(kIOHIDOptionsTypeNone)
        ) as? [IOHIDElement] else {
            log("  elements=unavailable")
            return
        }

        let capabilities = reportCapabilities(elements)
        let inputReports = capabilities.filter { $0.type == kIOHIDReportTypeInput }
        let outputReports = capabilities.filter { $0.type == kIOHIDReportTypeOutput }
        let featureReports = capabilities.filter { $0.type == kIOHIDReportTypeFeature }

        log(
            "  reports input=\(inputReports.count) output=\(outputReports.count) "
                + "feature=\(featureReports.count) writable=\((!outputReports.isEmpty || !featureReports.isEmpty) ? "yes" : "no")"
        )

        for capability in capabilities.sorted(by: reportCapabilityOrder) {
            log(
                "    \(reportTypeName(capability.type)) reportID=\(capability.reportID) "
                    + "maxElementBytes=\(capability.byteLength)"
            )
        }

        let interesting = elements.filter { IOHIDElementGetType($0) != kIOHIDElementTypeCollection }
        log("  elements=\(interesting.count)")
        for element in interesting {
            let type = IOHIDElementGetType(element)
            let usagePage = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            let reportID = UInt32(IOHIDElementGetReportID(element))
            let reportSize = Int(IOHIDElementGetReportSize(element))
            let reportCount = Int(IOHIDElementGetReportCount(element))
            let logicalMin = IOHIDElementGetLogicalMin(element)
            let logicalMax = IOHIDElementGetLogicalMax(element)
            let path = collectionPathDescription(for: element)
            log(
                String(
                    format: "    element type=%@ page=0x%04X usage=0x%04X reportID=%u "
                        + "bits=%d count=%d logical=[%lld,%lld] path=%@",
                    elementTypeName(type),
                    usagePage,
                    usage,
                    reportID,
                    reportSize,
                    reportCount,
                    Int64(logicalMin),
                    Int64(logicalMax),
                    path
                )
            )
        }
    }

    private func reportCapabilities(_ elements: [IOHIDElement]) -> [HIDReportCapability] {
        var maximumBytes: [String: HIDReportCapability] = [:]

        for element in elements {
            guard let reportType = reportType(for: IOHIDElementGetType(element)) else { continue }
            let reportID = UInt32(IOHIDElementGetReportID(element))
            let bitLength = Int(IOHIDElementGetReportSize(element)) * Int(IOHIDElementGetReportCount(element))
            let byteLength = max(0, (bitLength + 7) / 8)
            let key = "\(reportType.rawValue):\(reportID)"
            if let existing = maximumBytes[key], existing.byteLength >= byteLength {
                continue
            }
            maximumBytes[key] = HIDReportCapability(type: reportType, reportID: reportID, byteLength: byteLength)
        }

        return Array(maximumBytes.values)
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

    private func physicalDescriptor(_ device: IOHIDDevice) -> HIDPhysicalDeviceDescriptor {
        let vendorID = propertyInt(device, kIOHIDVendorIDKey)
        let productID = propertyInt(device, kIOHIDProductIDKey)
        let address = UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
        return HIDPhysicalDeviceDescriptor(
            kind: vendorID == ACK05.vendorID && productID == ACK05.productID
                ? .ack05
                : .genericHID,
            vendorID: vendorID,
            productID: productID,
            serialNumber: property(device, kIOHIDSerialNumberKey) as? String,
            productName: property(device, kIOHIDProductKey) as? String,
            manufacturerName: property(device, kIOHIDManufacturerKey) as? String,
            transport: property(device, kIOHIDTransportKey) as? String,
            locationID: (property(device, kIOHIDLocationIDKey) as? NSNumber)?.uint32Value,
            transportIdentifier: String(address, radix: 16)
        )
    }
}

private func matchingDictionary(for options: Options) -> CFDictionary? {
    if options.matchAllDevices {
        return nil
    }

    var matching: [String: Any] = [:]
    if let vendorID = options.vendorID {
        matching[kIOHIDVendorIDKey as String] = vendorID
    }
    if let productID = options.productID {
        matching[kIOHIDProductIDKey as String] = productID
    }
    if matching.isEmpty {
        matching[kIOHIDVendorIDKey as String] = ACK05.vendorID
        matching[kIOHIDProductIDKey as String] = ACK05.productID
    }
    return matching as CFDictionary
}

private func reportType(for elementType: IOHIDElementType) -> IOHIDReportType? {
    switch elementType {
    case kIOHIDElementTypeInput_Misc,
         kIOHIDElementTypeInput_Button,
         kIOHIDElementTypeInput_Axis,
         kIOHIDElementTypeInput_ScanCodes:
        return kIOHIDReportTypeInput
    case kIOHIDElementTypeOutput:
        return kIOHIDReportTypeOutput
    case kIOHIDElementTypeFeature:
        return kIOHIDReportTypeFeature
    default:
        return nil
    }
}

private func elementTypeName(_ type: IOHIDElementType) -> String {
    switch type {
    case kIOHIDElementTypeInput_Misc:
        return "input-misc"
    case kIOHIDElementTypeInput_Button:
        return "input-button"
    case kIOHIDElementTypeInput_Axis:
        return "input-axis"
    case kIOHIDElementTypeInput_ScanCodes:
        return "input-scan"
    case kIOHIDElementTypeOutput:
        return "output"
    case kIOHIDElementTypeFeature:
        return "feature"
    case kIOHIDElementTypeCollection:
        return "collection"
    default:
        return "unknown(\(type.rawValue))"
    }
}

private func reportCapabilityOrder(_ lhs: HIDReportCapability, _ rhs: HIDReportCapability) -> Bool {
    if lhs.type.rawValue != rhs.type.rawValue {
        return lhs.type.rawValue < rhs.type.rawValue
    }
    return lhs.reportID < rhs.reportID
}

private func collectionPathDescription(for element: IOHIDElement) -> String {
    let path = collectionPath(for: element)
    if path.isEmpty { return "[]" }
    let values = path.map { String(format: "0x%04X:0x%04X", $0.page, $0.usage) }
    return "[\(values.joined(separator: "/"))]"
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

private func eventDescription(_ phase: GenericHIDEventPhase) -> String {
    switch phase {
    case .pressed:
        "press"
    case .released:
        "release"
    case let .relative(delta):
        "relative(\(delta))"
    case let .absolute(value):
        "absolute(\(value))"
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

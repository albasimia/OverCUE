import Foundation
import Dispatch
import IOKit.hid

// A fixed, single round trip. No public packet, mode, key, or color parameters.
struct LiveRGBPlan {
    static func padded(_ prefix: [UInt8]) -> [UInt8] {
        precondition(prefix.count <= 64)
        return prefix + Array(repeating: 0, count: 64 - prefix.count)
    }
    static let lighting = padded([0xAA, 0x0A, 0x0B, 0, 0, 1, 0, 4, 4, 2, 0, 0, 7, 255, 255, 255])
    static let rgb = padded([0xAA, 0x13, 0x3A, 0, 0, 0, 0, 0] + Array(repeating: [UInt8(0), 255, 0], count: 6).flatMap { $0 })
    static let lightingGet = padded([6, 10])
    static let rgbGet = padded([6, 19, 58])
    static let custom = padded([6, 22, 0, 0, 0, 1, 0, 5])
    static let tidal = padded([6, 22, 0, 0, 0, 1, 0, 4])
    static let magenta = padded([6, 20, 3, 0, 0, 0, 0, 0, 255, 0, 255])
    static let green = padded([6, 20, 3, 0, 0, 0, 0, 0, 0, 255, 0])

    static func derived(_ response: [UInt8]?, mode: UInt8) -> [UInt8]? {
        guard let response, response.count == 64,
              response[0] == 0xAA, response[1] == 0x16, response[2] == 11,
              response[5] == 1,
              response[8] == lighting[8], response[9] == lighting[9],
              response[10] == lighting[10] else { return nil }
        var packet = padded([6, 11, 11, 0, 0] + response[5...15])
        packet[7] = mode
        return packet
    }

    // Transport is injected so every branch can be checked without HID access.
    static func run(send: (String, [UInt8]) -> [UInt8]?, hold: () -> Void,
                    log: (String) -> Void) -> Bool {
        let preLight = send("pre-light", lightingGet)
        let preRGB = send("pre-rgb", rgbGet)
        guard preLight == lighting, preRGB == rgb else {
            log("STOP baseline does not match both complete saved 64-byte responses; no mutation sent")
            return false
        }
        log("BASELINE full-byte match; mode=4 key0=00FF00")
        guard let customSet = derived(send("custom-prepare", custom), mode: 5) else {
            log("STOP custom 06 16 response absent/invalid or brightness/speed/direction differs; no 06 0B sent")
            return false
        }
        // Once a Custom write is attempted, prioritize rollback even if its ACK is missing.
        let customACK = send("custom-set", customSet)
        if customACK != nil {
            _ = send("magenta", magenta)
            hold()
        } else {
            log("Custom ACK missing; skip magenta and proceed directly to rollback")
        }
        let greenACK = send("green-rollback", green)
        log(greenACK == nil ? "Green rollback attempted; ACK unconfirmed" : "Green rollback response captured")
        guard let tidalSet = derived(send("tidal-prepare", tidal), mode: 4) else {
            log("STOP mode rollback incomplete; no guessed 06 0B; green rollback attempt already made")
            return false
        }
        _ = send("tidal-set", tidalSet)
        let postLight = send("post-light", lightingGet)
        let postRGB = send("post-rgb", rgbGet)
        for (name, before, after) in [("lighting", preLight, postLight), ("rgb", preRGB, postRGB)] {
            if let before, let after {
                let differences = before.indices.filter { before[$0] != after[$0] }
                log("DIFF \(name) offsets=\(differences)")
            } else { log("DIFF \(name) unavailable") }
        }
        let restored = postLight == lighting && postRGB == rgb
        log(restored ? "PASS baseline fully restored in both captured 64-byte chunks" : "FAIL post-check baseline differs or missing; no further sends")
        return restored
    }
}

final class LiveRGBTest {
    private let serial: String
    init(serial: String = "592B14678182") {
        precondition(["592B14678182", "2D3B07678182", "3F8701678182"].contains(serial))
        self.serial = serial
    }
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var device: IOHIDDevice?
    private var waitingFor: UInt8?
    private var response: [UInt8]?
    private var started: UInt64 = 0
    private var step = ""
    private var attempted = Set<String>()
    private var magentaStarted: UInt64?
    private let formatter = ISO8601DateFormatter()

    private func log(_ text: String) {
        FileHandle.standardOutput.write(Data("[\(formatter.string(from: Date()))] \(text)\n".utf8))
    }
    private func matches(_ d: IOHIDDevice) -> Bool {
        func number(_ key: String) -> Int { (IOHIDDeviceGetProperty(d, key as CFString) as? NSNumber)?.intValue ?? -1 }
        func string(_ key: String) -> String { IOHIDDeviceGetProperty(d, key as CFString) as? String ?? "" }
        return number(kIOHIDVendorIDKey) == 0x0816 && number(kIOHIDProductIDKey) == 0x246E
            && number(kIOHIDPrimaryUsagePageKey) == 0xFF00 && number(kIOHIDPrimaryUsageKey) == 2
            && string(kIOHIDProductKey) == "SIDE-KEYBOARD" && string(kIOHIDManufacturerKey) == "SDINNOVATION"
            && string(kIOHIDSerialNumberKey) == serial
            && outputReportLength(device: d, reportID: 0) == 64
    }
    func runSession(_ operation: ((String, [UInt8]) -> [UInt8]?) -> Bool) -> Bool {
        let matching: [String: Any] = [kIOHIDVendorIDKey: 0x0816, kIOHIDProductIDKey: 0x246E,
            kIOHIDPrimaryUsagePageKey: 0xFF00, kIOHIDPrimaryUsageKey: 2,
            kIOHIDSerialNumberKey: serial]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerRegisterInputReportCallback(manager, { context, result, sender, type, id, bytes, length in
            guard let context else { return }
            Unmanaged<LiveRGBTest>.fromOpaque(context).takeUnretainedValue()
                .receive(result, sender, type, id, bytes, length)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        defer {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            log("STOP manager open failed; no sends"); return false
        }
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []).filter { matches($0) }
        guard devices.count == 1 else { log("STOP exact matching interfaces=\(devices.count); no sends"); return false }
        device = devices.first
        log("TARGET SDINNOVATION SIDE-KEYBOARD VID=0816 PID=246E Serial=\(serial) Usage=FF00:0002 OutputID=0 length=64; unique interface")
        return operation(transact)
    }
    func run() -> Bool {
        runSession { send in
        LiveRGBPlan.run(send: send, hold: {
            guard let start = self.magentaStarted else { return }
            let end = start + 5_000_000_000
            while true {
                let now = DispatchTime.now().uptimeNanoseconds
                guard now < end else { break }
                Thread.sleep(forTimeInterval: min(Double(end - now) / 1e9, 0.05))
            }
            self.log("HOLD completed 5 seconds from magenta SetReport start; beginning rollback")
        }, log: log)
        }
    }
    private func transact(_ name: String, _ payload: [UInt8]) -> [UInt8]? {
        guard attempted.insert(name).inserted, payload.count == 64,
              let device, matches(device) else { log("STOP \(name) identity/capability or duplicate-step guard"); return nil }
        // Drain already queued events without allowing them to satisfy a new request.
        waitingFor = nil
        for _ in 0..<32 {
            if CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true) != .handledSource { break }
        }
        response = nil
        step = name
        waitingFor = payload[1]
        log("SEND \(name) reportID=0 length=64 bytes=[\(hex(payload))]")
        started = DispatchTime.now().uptimeNanoseconds
        if name == "magenta" { magentaStarted = started }
        let result = payload.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, 64)
        }
        log(String(format: "SETRESULT %@ IOReturn=0x%08X", name, UInt32(bitPattern: result)))
        guard result == kIOReturnSuccess else { waitingFor = nil; return nil }
        let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
        while response == nil && DispatchTime.now().uptimeNanoseconds < deadline {
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.01, true)
        }
        waitingFor = nil
        if response == nil { log("TIMEOUT \(name); no retry") }
        return response
    }
    private func receive(_ result: IOReturn, _ sender: UnsafeMutableRawPointer?, _ type: IOHIDReportType,
                         _ id: UInt32, _ bytes: UnsafeMutablePointer<UInt8>, _ length: CFIndex) {
        guard let waitingFor, let sender, let device else { return }
        let source = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
        guard CFEqual(device, source), type == kIOHIDReportTypeInput else { return }
        let data = Array(UnsafeBufferPointer(start: bytes, count: max(0, length)))
        let ms = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e6
        log(String(format: "INPUT %@ reportID=%u length=%ld latencyMs=%.3f IOReturn=0x%08X bytes=[%@]", step, id, length, ms, UInt32(bitPattern: result), hex(data)))
        // Header correspondence is a conservative gate, not proof of firmware success status.
        guard response == nil, result == kIOReturnSuccess, id == 0, data.count == 64,
              data[0] == 0xAA, data[1] == waitingFor else { return }
        response = data
    }
    private func hex(_ data: [UInt8]) -> String { data.map { String(format: "%02X", $0) }.joined(separator: " ") }
}

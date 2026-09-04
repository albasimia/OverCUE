import Foundation

// One finite 0 -> 1 -> 2 -> 3 observation sequence, then restore index 0.
enum KeyIndexWalk {
    static func keyPacket(_ index: Int, _ color: [UInt8]) -> [UInt8] {
        precondition((0...3).contains(index) && color.count == 3)
        return LiveRGBPlan.padded([6,20,3,UInt8(3 * index),0,0,0,0] + color)
    }
    static func expected(_ index: Int, _ color: [UInt8]) -> [UInt8] {
        var result = LiveRGBPlan.padded([0xAA,19,58,0,0,0,0,0])
        result.replaceSubrange((8+3*index)..<(11+3*index), with: color)
        return result
    }
    static func note(_ text: String) {
        FileHandle.standardOutput.write(Data((ISO8601DateFormatter().string(from: Date()) + " " + text + "\n").utf8))
    }
    static func run() -> Bool {
        for (serial, color) in ThreeSingleLights.targets {
            let ready = LiveRGBTest(serial: serial).runSession { send in
                let light = send("walk-baseline-light", LiveRGBPlan.lightingGet)
                let rgb = send("walk-baseline-rgb", LiveRGBPlan.rgbGet)
                return light?[7] == 5 && rgb == expected(0, color)
            }
            guard ready else { note("STOP baseline mismatch \(serial); no new changes"); return false }
        }
        note("OBSERVE key_index=0 for 5 seconds")
        Thread.sleep(forTimeInterval: 5)
        // Four fixed transitions; no retries or repeating animation.
        for (from, to) in [(0,1), (1,2), (2,3), (3,0)] {
            for (serial, color) in ThreeSingleLights.targets {
                let ok = LiveRGBTest(serial: serial).runSession { send in
                    guard send("walk-off-\(from)", keyPacket(from, [0,0,0])) != nil,
                          send("walk-on-\(to)", keyPacket(to, color)) != nil,
                          let rgb = send("walk-verify-\(to)", LiveRGBPlan.rgbGet),
                          rgb == expected(to, color) else { return false }
                    return true
                }
                guard ok else { note("STOP transition \(from)->\(to) failed \(serial); no retry; partial state possible"); return false }
            }
            if to != 0 {
                note("OBSERVE key_index=\(to) for 5 seconds")
                Thread.sleep(forTimeInterval: 5)
            }
        }
        note("PASS all three restored to key_index=0; RGB chunk verified")
        return true
    }
}

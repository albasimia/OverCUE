import Foundation

enum BreathingPlayPauseTrial {
    static let serial = "592B14678182"
    static let desired: [[UInt8]] = [[0,0,0], [0,0,0], [0,0,0], [255,0,0]]
    static func rgb(_ r: [UInt8]?) -> [[UInt8]]? {
        guard let r, r.count == 64, r[0] == 0xAA, r[1] == 0x13,
              r[2] == 0x3A, r[3] == 0, r[4] == 0 else { return nil }
        return (0..<4).map { Array(r[(8+3*$0)..<(11+3*$0)]) }
    }
    static func key(_ i: Int, _ color: [UInt8]) -> [UInt8] {
        LiveRGBPlan.padded([6,20,3,UInt8(3*i),0,0,0,0] + color)
    }
    static func hex(_ v: [UInt8]) -> String { v.map { String(format:"%02X",$0) }.joined(separator:" ") }
    static func run(send: (String,[UInt8])->[UInt8]?) -> Bool {
        guard let light = send("breath-baseline-light", LiveRGBPlan.lightingGet),
              light.count == 64, light[0] == 0xAA, light[1] == 0x0A, light[2] == 0x0B,
              let rawRGB = send("breath-baseline-rgb", LiveRGBPlan.rgbGet),
              let current = rgb(rawRGB) else {
            print("STOP invalid baseline; no mutation sent"); return false
        }
        print("BASELINE lighting64=[\(hex(light))]")
        print("BASELINE rgb64=[\(hex(rawRGB))]")
        print("BASELINE mode=\(light[7]) key0...3=\(current.map(hex).joined(separator:","))")
        for i in 0..<4 where current[i] != desired[i] {
            guard send("breath-key\(i)", key(i, desired[i])) != nil else {
                print("STOP key\(i) setter failed; no retry"); return false
            }
        }
        let prepare = LiveRGBPlan.padded([6,22,0,0,0,1,0,5])
        guard let set = ThreeSingleLights.modePacket(send("breath-mode5-prepare", prepare), 5) else {
            print("STOP invalid 06 16 response; no guessed 06 0B"); return false
        }
        guard send("breath-mode5-set", set) != nil else {
            print("STOP 06 0B failed; no retry"); return false
        }
        guard let readback = send("breath-custom-rgb-readback", LiveRGBPlan.rgbGet), rgb(readback) == desired else {
            print("STOP RGB readback mismatch; no retry/rollback"); return false
        }
        print("READBACK rgb64=[\(hex(readback))]")
        print("PHASE-A PASS mode5; key0=000000 key1=000000 key2=000000 key3=FF0000")
        return true
    }

    static func runPhaseB(send: (String,[UInt8])->[UInt8]?) -> Bool {
        let prepare = LiveRGBPlan.padded([6,22,0,0,0,1,0,2])
        guard let set = ThreeSingleLights.modePacket(send("breath-mode2-prepare", prepare), 2) else {
            print("STOP invalid mode2 06 16 response; no guessed 06 0B"); return false
        }
        guard send("breath-mode2-set", set) != nil else {
            print("STOP mode2 06 0B failed; no retry/rollback"); return false
        }
        print("PHASE-B SENT mode2 from response-derived 06 0B; visual gate pending")
        return true
    }

    static let baselineLighting = LiveRGBPlan.padded(
        [0xAA,0x0A,0x0B,0,0,1,0,1,4,2,1,0,7,0,255,255]
    )
    static let baselineRGB = LiveRGBPlan.padded(
        [0xAA,0x13,0x3A,0,0,0,0,0, 0,0,255]
    )

    static func rollback(send: (String,[UInt8])->[UInt8]?) -> Bool {
        guard send("breath-rollback-key0", key(0, [0,0,255])) != nil else {
            print("STOP rollback key0 failed; no retry"); return false
        }
        guard send("breath-rollback-key3", key(3, [0,0,0])) != nil else {
            print("STOP rollback key3 failed; no retry"); return false
        }
        let prepare = LiveRGBPlan.padded([6,22,0,0,0,1,0,1])
        guard let set = ThreeSingleLights.modePacket(send("breath-rollback-mode1-prepare", prepare), 1) else {
            print("STOP invalid rollback 06 16 response; no guessed 06 0B"); return false
        }
        guard send("breath-rollback-mode1-set", set) != nil else {
            print("STOP rollback 06 0B failed; no retry"); return false
        }
        let light = send("breath-post-light", LiveRGBPlan.lightingGet)
        let colors = send("breath-post-rgb", LiveRGBPlan.rgbGet)
        print("POST lighting64=[\(light.map(hex) ?? "unavailable")]")
        print("POST rgb64=[\(colors.map(hex) ?? "unavailable")]")
        guard light == baselineLighting, colors == baselineRGB else {
            print("ROLLBACK MISMATCH; no retry/further send"); return false
        }
        print("ROLLBACK PASS pre/post captured 64-byte lighting and RGB ranges match")
        return true
    }

    static func setBinaryMode(_ mode: UInt8, name: String,
                              send: (String,[UInt8])->[UInt8]?) -> Bool {
        precondition(mode == 0 || mode == 5)
        let prepare = LiveRGBPlan.padded([6,22,0,0,0,1,0,mode])
        guard let set = ThreeSingleLights.modePacket(send("binary-\(name)-prepare", prepare), mode) else {
            print("STOP invalid binary \(name) 06 16 response; no guessed 06 0B"); return false
        }
        guard send("binary-\(name)-set", set) != nil else {
            print("STOP binary \(name) 06 0B failed; no retry"); return false
        }
        print("BINARY \(name) mode=\(mode) accepted; visual gate pending")
        return true
    }

    static func setOfficialMode(_ mode: UInt8,
                                send: (String,[UInt8])->[UInt8]?) -> Bool {
        guard mode <= 5 else {
            print("STOP mode \(mode) is not an official SIDE-KEYBOARD mode")
            return false
        }
        guard let beforeLight = send("official-mode\(mode)-before-light", LiveRGBPlan.lightingGet),
              let beforeRGB = send("official-mode\(mode)-before-rgb", LiveRGBPlan.rgbGet),
              rgb(beforeRGB) != nil else {
            print("STOP invalid preflight; no mutation sent")
            return false
        }
        let prepare = LiveRGBPlan.padded([6,22,0,0,0,1,0,mode])
        guard let response = send("official-mode\(mode)-prepare", prepare),
              let set = ThreeSingleLights.modePacket(response, mode) else {
            print("STOP invalid mode\(mode) 06 16 response; no guessed 06 0B")
            return false
        }
        print("OFFICIAL mode=\(mode) prepare64=[\(hex(response))]")
        print("OFFICIAL mode=\(mode) derived-set64=[\(hex(set))]")
        guard send("official-mode\(mode)-set", set) != nil,
              let afterLight = send("official-mode\(mode)-after-light", LiveRGBPlan.lightingGet),
              let afterRGB = send("official-mode\(mode)-after-rgb", LiveRGBPlan.rgbGet),
              rgb(afterRGB) != nil else {
            print("STOP mode\(mode) set/readback failed; no retry")
            return false
        }
        print("OFFICIAL mode=\(mode) before-light64=[\(hex(beforeLight))]")
        print("OFFICIAL mode=\(mode) before-rgb64=[\(hex(beforeRGB))]")
        print("OFFICIAL mode=\(mode) after-light64=[\(hex(afterLight))]")
        print("OFFICIAL mode=\(mode) after-rgb64=[\(hex(afterRGB))]")
        guard afterLight[7] == mode else {
            print("STOP mode\(mode) readback mismatch; no retry")
            return false
        }
        print("OFFICIAL mode=\(mode) accepted; visual gate pending")
        return true
    }

    static func setSingleRed(_ mode: UInt8,
                             send: (String,[UInt8])->[UInt8]?) -> Bool {
        guard (1...4).contains(mode) else {
            print("STOP mode \(mode) does not expose the official single-color control")
            return false
        }
        guard let before = send("mode\(mode)-single-red-before", LiveRGBPlan.lightingGet),
              before.count == 64, before[0] == 0xAA, before[1] == 0x0A,
              before[2] == 0x0B, before[7] == mode else {
            print("STOP mode\(mode) preflight mismatch; no mutation sent")
            return false
        }
        // Exact SDTech setLightConfig semantics for the UI's single-color checkbox:
        // preserve type/mode/brightness/speed/direction, set color=1,
        // clear the UI's reserved singleColorIndex byte, and set HSV red.
        var packet = LiveRGBPlan.padded([6, 11, 11, 0, 0] + before[5...15])
        packet[11] = 1
        packet[12] = 0
        packet[13] = 0
        packet[14] = 255
        packet[15] = 255
        print("MODE\(mode) single-red set64=[\(hex(packet))]")
        guard send("mode\(mode)-single-red-set", packet) != nil,
              let after = send("mode\(mode)-single-red-after", LiveRGBPlan.lightingGet),
              after.count == 64, after[7] == mode, after[11] == 1,
              after[13] == 0, after[14] == 255, after[15] == 255 else {
            print("STOP mode\(mode) single-red set/readback failed; no retry")
            return false
        }
        print("MODE\(mode) single-red after64=[\(hex(after))]")
        print("MODE\(mode) single-red accepted; visual gate pending")
        return true
    }
}

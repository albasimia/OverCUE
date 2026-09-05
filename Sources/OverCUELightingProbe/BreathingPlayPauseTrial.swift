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
}

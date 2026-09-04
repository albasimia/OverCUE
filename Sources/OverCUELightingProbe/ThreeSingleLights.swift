import Foundation

// Fixed three-device preset, scoped to the user's one-light-per-device request.
enum ThreeSingleLights {
    static let targets: [(String, [UInt8])] = [
        ("592B14678182", [0, 0, 255]),
        ("2D3B07678182", [0, 255, 0]),
        ("3F8701678182", [255, 0, 0])
    ]
    static func modePacket(_ reply: [UInt8]?, _ mode: UInt8) -> [UInt8]? {
        guard let reply, reply.count == 64, reply[0] == 0xAA, reply[1] == 22,
              reply[2] == 11, reply[5] == 1 else { return nil }
        var p = LiveRGBPlan.padded([6, 11, 11, 0, 0] + reply[5...15])
        p[7] = mode
        return p
    }
    static func expectedRGB(_ color: [UInt8]) -> [UInt8] { color + Array(repeating: 0, count: 54) }
    static func bulk(_ rgb: [UInt8], offset: Int) -> [UInt8] {
        precondition(rgb.count == 57 && [0, 56].contains(offset))
        let data = Array(rgb[offset..<min(offset + 56, rgb.count)])
        return LiveRGBPlan.padded([6, 18, UInt8(data.count + 3), UInt8(offset), 0, 0, 0, 0] + data)
    }
    static let secondGet = LiveRGBPlan.padded([6, 19, 58, 56])
    static func rgb(_ first: [UInt8]?, _ second: [UInt8]?) -> [UInt8]? {
        guard let first, let second, first.count == 64, second.count == 64,
              first[0] == 0xAA, first[1] == 19, second[0] == 0xAA, second[1] == 19,
              first[3] == 0, first[4] == 0, second[3] == 56, second[4] == 0 else { return nil }
        return Array(first[8...63]) + [second[8]]
    }
    static func run() -> Bool {
        // Back up all three devices before changing any of them.
        for (serial, _) in targets {
            let ok = LiveRGBTest(serial: serial).runSession { send in
                let light = send("backup-light", LiveRGBPlan.lightingGet)
                let first = send("backup-rgb0", LiveRGBPlan.rgbGet)
                let second = send("backup-rgb56", secondGet)
                guard let light, light.count == 64, light[2] == 11,
                      let colors = rgb(first, second) else { return false }
                print("BACKUP serial=\(serial) config=\(Array(light[5...15])) rgb57=\(colors)")
                return true
            }
            guard ok else { print("STOP backup failed: \(serial); no new writes"); return false }
        }
        // First switch all three off, using the official mode transition.
        for (serial, _) in targets {
            let ok = LiveRGBTest(serial: serial).runSession { send in
                guard let off = modePacket(send("off-prepare", LiveRGBPlan.padded([6,22,0,0,0,1,0,0])), 0),
                      send("off-set", off) != nil,
                      let check = send("off-check", LiveRGBPlan.lightingGet), check[7] == 0 else { return false }
                return true
            }
            guard ok else { print("STOP off transition failed: \(serial); no retry"); return false }
        }
        for (serial, color) in targets {
            let colors = expectedRGB(color)
            let ok = LiveRGBTest(serial: serial).runSession { send in
                // Official bulk builder: 56-byte chunk then final one-byte chunk.
                guard send("rgb-set0", bulk(colors, offset: 0)) != nil,
                      send("rgb-set56", bulk(colors, offset: 56)) != nil else { return false }
                let first = send("verify-rgb0", LiveRGBPlan.rgbGet)
                let second = send("verify-rgb56", secondGet)
                guard rgb(first, second) == colors else { return false }
                guard let custom = modePacket(send("custom-prepare", LiveRGBPlan.custom), 5),
                      send("custom-set", custom) != nil,
                      let check = send("custom-check", LiveRGBPlan.lightingGet),
                      Array(check[5...15]) == Array(custom[5...15]) else { return false }
                print("PASS serial=\(serial) mode5 key0=\(color) all other 18 RGB entries zero")
                return true
            }
            guard ok else { print("STOP one-light setup failed: \(serial); no retry"); return false }
        }
        return true
    }
}

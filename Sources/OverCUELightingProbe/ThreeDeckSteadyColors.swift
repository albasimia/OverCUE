import Foundation

// Fixed, user-authorized setup for the three known SIDE-KEYBOARD units.
// Uses only the official mode-1 response-derived 06 0B path; no retry.
enum ThreeDeckSteadyColors {
    struct Target {
        let deck: Int
        let serial: String
        let name: String
        let hue: UInt8
    }

    // Physical Deck assignment confirmed by the user. Orange is biased toward
    // red (~20 degrees); cyan ~= 181 degrees; red = 0.
    static let targets = [
        Target(deck: 1, serial: "3F8701678182", name: "red-orange", hue: 14),
        Target(deck: 2, serial: "2D3B07678182", name: "cyan", hue: 128),
        Target(deck: 3, serial: "592B14678182", name: "red", hue: 0),
    ]

    static func run() -> Bool {
        for target in targets {
            let ok = LiveRGBTest(serial: target.serial).runSession { send in
                guard let before = send("deck\(target.deck)-before", LiveRGBPlan.lightingGet),
                      before.count == 64, before[0] == 0xAA,
                      before[1] == 0x0A, before[2] == 0x0B else {
                    print("STOP Deck\(target.deck) preflight failed; no mutation/retry")
                    return false
                }

                if before[7] == 1, before[8] == 2, before[11] == 1,
                   before[13] == target.hue, before[14] == 255,
                   before[15] == 127 {
                    print("SKIP Deck\(target.deck) serial=\(target.serial) already matches \(target.name) steady 50%")
                    return true
                }

                let prepare = LiveRGBPlan.padded([6, 22, 0, 0, 0, 1, 0, 1])
                guard let response = send("deck\(target.deck)-mode1-prepare", prepare),
                      var packet = ThreeSingleLights.modePacket(response, 1) else {
                    print("STOP Deck\(target.deck) invalid 06 16 response; no guessed 06 0B")
                    return false
                }

                // Official setLightConfig fields: mode 1, brightness 2/4,
                // single HSV, no reserved index, full saturation, 50% value.
                packet[7] = 1
                packet[8] = 2
                packet[11] = 1
                packet[12] = 0
                packet[13] = target.hue
                packet[14] = 255
                packet[15] = 127

                guard send("deck\(target.deck)-steady-set", packet) != nil,
                      let after = send("deck\(target.deck)-after", LiveRGBPlan.lightingGet),
                      after.count == 64, after[0] == 0xAA,
                      after[1] == 0x0A, after[2] == 0x0B,
                      after[7] == 1, after[8] == 2, after[11] == 1,
                      after[13] == target.hue,
                      after[14] == 255, after[15] == 127 else {
                    print("STOP Deck\(target.deck) set/readback mismatch; no retry")
                    return false
                }

                print("PASS Deck\(target.deck) serial=\(target.serial) color=\(target.name) mode=steady brightness=2/4 HSV=\(target.hue),255,127")
                return true
            }
            guard ok else { return false }
        }
        return true
    }
}

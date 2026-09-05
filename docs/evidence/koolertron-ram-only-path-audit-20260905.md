# Koolertron RAM-only lighting path audit

Date: 2026-09-05  
Target: SDINNOVATION SIDE-KEYBOARD `0816:246E`  
Branch: `codex/koolertron-led-probe`

## Conclusion

The two client generations bundled in SDTech Option 1.0.3 do not expose a
RAM-only lighting preview or live-output path. Both generations use the same
WebHID Output Report transport and the known lighting configuration/RGB
setters. The apparent live-lighting methods are stubs.

This is negative evidence about the official client, not proof that the
firmware has no undocumented volatile command. No unknown command was sent to
the device. The existing gate remains: do not use the persistent lighting
setters for Play/Pause runtime feedback.

## Client generations inspected

The ASAR contains two Next.js application generations:

| Bundle | SHA-256 | Finding |
|---|---|---|
| `_next/static/chunks/app/page-4309ee7c1dfd82c0.js` | `467225220ef0dd942dd3823a69023a7113bf9cb4234b5174c469a6608b4ac140` | `setRGBMode`, `setBrightness`, `setLightSpeed`, `setSingleColorState`, and `setLightColorHSV` only call `console.log` |
| `src/_next/static/chunks/app/page-58ff86c8ca1ede81.js` | `cf0bbdb35a701c77e6e2191564811126f4a75463e45fb5f159fa29cc8797e965` | the same five methods are empty stubs; `src` is the active Electron entry generation |

A recursive scan of all bundled JavaScript found no `navigator.usb`,
`navigator.serial`, `sendFeatureReport`, `receiveFeatureReport`,
`transferOut`, or `controlTransferOut` call. Both generations use
`navigator.hid` and `sendReport`.

For command `0x06`, the complete distinct call-site inventory across both
generations contains the known configuration/mapping paths:

- `06 0A` / `06 0B`: lighting config get/set
- `06 12` / `06 13` / `06 14`: RGB bulk set/get/single-key set
- `06 16`: response-derived lighting mode preparation
- `06 05`, `06 07`, `06 0F`, `06 40`, `06 41`, `06 FB`: keyboard
  configuration, mapping, URL/profile-related paths

There is no second lighting output call site used for hover preview, UI
animation preview, live frame streaming, or temporary state.

## HID transport evidence

Read-only `ioreg` inspection of the connected SIDE-KEYBOARD interfaces shows:

- the keyboard/consumer composite descriptor is input-only;
- the vendor-defined `FF00:0002` interface has Report ID 0, 64-byte Input and
  64-byte Output reports;
- the vendor report descriptor is
  `0600ff0902a10119002aff00150026ff0075089540810019002aff009100c0`;
- no useful Feature Report transport is declared for lighting.

Therefore the only host-to-device lighting transport exposed by the official
client and the live HID descriptors is the existing vendor Output Report
interface. This does not rule out undocumented subcommands on that interface.

## Firmware package inspection

The application bundles two 32 KiB images for this layout family:

| File | SHA-256 |
|---|---|
| `4keysd_v101.bin` | `eb04115e950d2e257311189de6e702f137ce4067df8adbc1691b4b577423098d` |
| `src/4keysd_v105.bin` | `05d4d2a439de90d16e828e5e05c888d17d8a1794f768a6b19338ae9b911b8b0b` |

They differ substantially (`17,593` byte positions). The active layout marks
the MCU family only as `951`; the client supplies memory sizes but no public
instruction-set or command-dispatch symbols. The connected device firmware was
not read and was not proven identical to either image. Inferring and sending an
undocumented volatile-light command from byte-pattern guesses would therefore
violate the safety gate.

## Safe boundary and next evidence

The official client/static path is exhausted without a RAM-only command.
Proceed only if one of these stronger sources becomes available:

1. vendor protocol documentation or source identifying a volatile LED command;
2. a separate official utility/feature that demonstrably performs temporary
   preview, followed by a USB trace of that exact operation;
3. a correctly identified MCU architecture and verified firmware disassembly
   that establishes command dispatch and storage behavior before any live send.

Until then, mode 2 red breathing remains a visual proof only. Known `06 0B` and
`06 14` writes must not be connected to rekordbox Play/Pause transitions.

## Safety / actions

- Device Output Reports sent during this audit: **0**.
- Feature Reports sent: **0**.
- Firmware operations: **0**.
- No retry, benchmark, mode change, RGB change, or other-Serial access occurred.
- The device remains in the pre-existing mode 2 / single-red breathing state.


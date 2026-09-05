# Koolertron lighting query — 2026-09-04

## Send result

- Branch: `codex/koolertron-led-probe`, pulled HEAD `0a046f8` plus local probe fixes.
- Command: `swift run overcue-led-probe --get-lighting --serial 592B14678182`
- Timestamp: 2026-09-04 03:48:36 UTC / 12:48:36 JST.
- Manufacturer / Product: `SDINNOVATION / SIDE-KEYBOARD`.
- VID / PID: `0816 / 246E`, USB.
- Serial: `592B14678182` only.
- Interface: Usage Page `FF00`, Usage `0002` (interface C in prior notes; not a USB interface number).
- Read-only preflight found exactly one matching interface, locationID `17895424`, IORegistry entry ID `4294986754` (session evidence, not persistent identity).
- Descriptor confirmed Input/Output Report ID 0, 64 bytes. The CLI rechecked all requested matching fields and exact descriptor-derived Output length before sending.
- Output Report ID: 0.
- Payload: `06 0A` + 62 zero bytes, 64 bytes total.
- `IOHIDDeviceSetReport`: `0x00000000` (`kIOReturnSuccess`). Process exit code: 0.
- Send attempts: **1**. No retry or alternate target.

Raw stdout/stderr: [query log](evidence/koolertron-light-query-20260904-592B14678182.log).

## Response

- Same selected IOHIDDevice; Input Report ID 0; length 64.
- Latency from start of SetReport to callback processing: **2.659 ms**, measured with monotonic uptime. Includes host call and callback scheduling overhead; not an isolated firmware execution time.
- Captured the first post-send matching Input report. CLI completed without another send.

```text
AA 0A 0B 00 00 01 00 04 04 02 00 00 07 FF FF FF
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

| Offset | Hex | Observed / static-client interpretation |
|---|---|---|
| 0 | AA | Response leading byte; differs from request's 06. Header vs status semantics remain unknown |
| 1 | 0A | Matches query subcommand; likely response command echo |
| 2 | 0B | 11, consistent with 11-byte lighting config |
| 3 | 00 | Observed zero; reserved/status semantics unconfirmed |
| 4 | 00 | Observed zero; reserved/status semantics unconfirmed |
| 5 | 01 | type=1 |
| 6 | 00 | zero slot in static config |
| 7 | 04 | mode=4, layout resource calls this 潮汐 |
| 8 | 04 | brightness=4 (client UI 0–4) |
| 9 | 02 | speed=2 (client UI 0–4) |
| 10 | 00 | direction=0; physical meaning unconfirmed |
| 11 | 00 | color switch=0; exact device effect unconfirmed |
| 12 | 07 | **Not zero**. Read parser calls this singleColorIndex=7; writer uses zero |
| 13 | FF | H=255; client conversion floor(360*255/255)=360 degrees |
| 14 | FF | S=255 → 100% |
| 15 | FF | V=255 → 100% |

Offsets 5–15: `01 00 04 04 02 00 00 07 FF FF FF`.

## Static-analysis comparison

### Confirmed

- One allowed query was submitted successfully and followed by a 64-byte Input Report ID 0 from the same selected interface.
- The exact raw response, including `AA 0A 0B` and nonzero offset 12, is captured above.
- Response header is different from the request header. The previous setter layout's zero at offset 12 must not be imposed on the response.

### Strong inference

- `06 0A` is effective on this firmware as a lighting-config query: matching subcommand 0A, length-like 0B, the 11-byte field block expected by the static getter, and short post-send latency all agree.
- Response byte 1 echoes the subcommand; byte 2 is config data length 11, not total report length.
- Static getter interpretation yields mode 4, brightness 4, speed 2, direction 0, color switch 0, singleColorIndex 7, HSV bytes FF/FF/FF.
- Setter/getter share the field positions at 5–15 but do not necessarily share header or fixed-zero values.

### Unknown

- Whether AA is a generic response marker, success status, or both. No error reply was intentionally produced.
- Transaction identifiers, negative responses, repeated-query behavior, and firm causality beyond this single correlated reply. The probe does not validate a complete response protocol.
- Actual visible lighting and the meaning of direction/color switch/preset index on this unit. No eye-witness confirmation.
- The current effect may not use HSV directly; FF/FF/FF does not prove the visible light is red.
- RAM/flash/profile persistence, setter safety, firmware version, and behavior of the other two Serial devices.

## Probe fixes / verification

Before sending, changed only `Sources/OverCUELightingProbe/main.swift`:

1. Replaced summation of expanded HID element sizes and `>=64` acceptance with descriptor Output-item bit counting and exact `==64` gate. Array elements may overlap; summing them is not report length.
2. Marked the attempt before SetReport and pinned Input capture to that IOHIDDevice.
3. Logged full payload, SetReport return code, and monotonic response latency.

Validation before the single send:

- `aal context build --mode exploration`: succeeded; context read. Rebuilt after pull and read the new query decision.
- Initial sandboxed `swift build` failed on Swift cache access, then succeeded with the normal cache accessible. No HID send was attempted during this failure.
- `swift build`: succeeded.
- `swift test`: 35 tests, 0 failures.
- Offline descriptor checks: 8 passed; actual vendor descriptor, wrong ID, missing Output, short/oversized/truncated data, and global push/pop coverage. Extracted pure parser only, no IOKit or device access.
- `./Scripts/verify-macos.sh`: succeeded, including 405 Core checks, Universal Binary build, ad-hoc codesign verification. Build artifacts were regenerated; no application was launched.
- `aal doctor`: 0 failures / 0 warnings.
- `git diff --check`: succeeded.

No changes to OverCUEApp, OverCUEBridge, GenericHIDRuntimeCoordinator, ActionLayer, or config schema. Prior untracked static-analysis notes were preserved. No commit was made for this run.

## Safety

Only the explicitly authorized `06 0A` query was sent once, to Serial `592B14678182`. No retries, alternate interfaces/Serials, Feature reports, RGB/brightness setters, mode transitions, firmware operations, or manufacturer-app launches. No claim is made that unobserved firmware side effects or visible state were independently ruled out.

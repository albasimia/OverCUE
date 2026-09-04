# USB reconnect getter readback — 2026-09-04 17:46:52 JST

Each of the three known serials received 06 0A once and 06 13 chunk0 once. Six Output getter requests total; no retries, setters, Feature reports or manufacturer apps. All SetReport and Input IOReturn values were zero, Report ID0 / 64 bytes.

| Serial | Mode | Key0 | Keys1-3 | Light latency ms | RGB latency ms | Difference from setup |
|---|---|---|---|---|---|---|
| 592B14678182 | 5 | #0000FF | #000000 | 2.787 | 1.777 | None (both full64-byte responses) |
| 2D3B07678182 | 5 | #00FF00 | #000000 | 1.997 | 1.784 | None (both full64-byte responses) |
| 3F8701678182 | 5 | #FF0000 | #000000 | 2.202 | 1.782 | None (both full64-byte responses) |

All three lighting configs: type1 / mode5 / brightness4 / speed2 / direction0 / colorSwitch0 / singleColorIndex7 / HSV FF FF FF. RGB chunk0 contains key0 followed by zeros. The final byte of the57-byte RGB array was not fetched this time.

These captures establish current values after the user reported USB reconnect; they support persistence but do not identify storage medium, commit command or endurance. No automatic restoration was performed.

## Full responses

### 592B14678182 / read-lighting

```text
AA 0A 0B 00 00 01 00 05 04 02 00 00 07 FF FF FF
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

### 592B14678182 / read-rgb

```text
AA 13 3A 00 00 00 00 00 00 00 FF 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

### 2D3B07678182 / read-lighting

```text
AA 0A 0B 00 00 01 00 05 04 02 00 00 07 FF FF FF
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

### 2D3B07678182 / read-rgb

```text
AA 13 3A 00 00 00 00 00 00 FF 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

### 3F8701678182 / read-lighting

```text
AA 0A 0B 00 00 01 00 05 04 02 00 00 07 FF FF FF
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

### 3F8701678182 / read-rgb

```text
AA 13 3A 00 00 00 00 00 FF 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Raw log: [evidence](evidence/koolertron-reconnect-read-20260904.log). Only LED probe main.swift gained a fixed --read-three-lighting-rgb getter-only entry. No runtime integration or commit.

Verification: swift build / swift test / overcue-checks / verify-macos.sh passed; aal doctor zero failures/warnings; git diff --check passed. git status --short checked. No HID rerun during verification.

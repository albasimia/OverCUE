# Koolertron lighting query probe gate

## Decision

Koolertron / SDINNOVATION `SIDE-KEYBOARD` LED protocol exploration remains isolated on `codex/koolertron-led-probe` and does not connect to OverCUE runtime.

Static analysis of SDTech Option 1.0.3 identified the target Vendor Defined HID interface as VID `0x0816`, PID `0x246E`, Usage Page `0xFF00`, Usage `0x0002`, with Report ID 0 and a 64-byte Output payload. The lighting settings read command is `06 0A` followed by zero padding to 64 bytes.

A dedicated executable target `overcue-led-probe` is allowed to send exactly this one known query for the next live gate.

## Safety boundary

- `--serial` is mandatory and must match one physical SIDE-KEYBOARD.
- VID/PID/Usage Page/Usage/Product are fixed in code and cannot be overridden from the CLI.
- A 64-byte Output Report ID 0 capability must be present before sending.
- The only payload is `06 0A` + 62 zero bytes.
- Send exactly once. No retry.
- No arbitrary HID write mode is introduced.
- No RGB setter (`06 14`), global lighting setter (`06 0B`), array write (`06 12`), mode transition (`06 16`), firmware command, or persistence command is permitted in this gate.
- OverCUEApp, OverCUEBridge, GenericHIDRuntimeCoordinator, ActionLayer, and config schema remain unchanged.

## Completion gate

Run the dedicated probe on macOS against exactly one known serial and capture the 64-byte input response. Compare response offsets 5...15 with the statically recovered lighting configuration layout.

A successful read response establishes command compatibility only. It does not establish that RGB writes are volatile or safe for high-frequency runtime synchronization.

Before any live LED state synchronization, persistence behavior (RAM vs flash/profile storage), key-index mapping, safe send cadence, and response/error semantics must be established separately.

# Generic HID cleanup and latency audit — 2026-09-04

Scope: preserve mapping, Preset ownership, capture lifecycle, suppression and
ACK05 behavior. No real-device input was available for this audit. SIDE latency
and Deck3 knob Learn failure are separate, still unconfirmed hardware cases.

## Inventory

| Item | Disposition | Evidence / reason |
| --- | --- | --- |
| Runtime Status suppression gate and capture broker | Already removed in `ffd5dc0` | No remaining source references |
| `GenericHIDLearnMonitor` and its private callback/error | Deleted | No callers; superseded by capture on the running Generic HID coordinator; old exclusive manager must not return |
| Learn save diagnostic count read | Deleted | Read the sidecar only to log its count, including when diagnostics were off |
| Capture log interpolation | Lazy | Disabled diagnostics no longer construct their message |
| `finishingCapture`, `isCaptureMode`, capture handler | Retained | Still participate in active teardown/reentrancy paths; not dead code; lifecycle changes need a separate regression-backed change |
| HID open retry | Retained | Still called by Generic HID Identify |
| Native suppression and 8ms correlation wait | Retained | Required live functionality, not an unused experiment; no change to timing or filtering |
| Optional runtime diagnostics | Retained | Needed for unresolved hardware cases; disabled by default |

## Hot-path changes

- Group Preset status handling checks the config file revision, then reuses decoded
  configuration if unchanged. Revision includes inode, size and nanosecond mtime.
  Config notifications invalidate explicitly. Missing, invalid and unsupported
  files throw rather than returning stale configuration. A read racing a file
  replacement is not cached under the newer revision. This cache is read-only;
  GUI merge baselines and locked writers are unchanged.
- Generic HID caches immutable element metadata by live interface + cookie.
  Removal clears that interface's entries; runtime stop/start clears all entries.
  Cookie is never persisted. Failed enumeration is retried; ambiguous descriptors
  remain rejected. Physical binding validation still runs before cache use.
- Parsed shortcuts are reused by their exact source string and invalidated with
  the existing mode mapping cache. Action phases and output ordering are unchanged.
- Optional input diagnostics now include the original IOHID timestamp at callback
  entry, before metadata resolution, alongside existing monotonic log times.

## Measurements and limits

Debug XCTest, default-config temporary fixture, 500 reads: final run full JSON
read/decode ~39.4ms total; revision cache including symlink resolution ~7.37ms total.
Symlink targets are resolved so replacing the destination cannot retain stale data.
This is a microbenchmark,
not an end-to-end latency measurement or a realtime performance guarantee. The
test prints timings without flaky machine-dependent pass/fail thresholds.

The GUI main runloop still owns Generic HID actions. GUI work may delay delivery;
ACK05 output runs in its separate CLI process. Moving HID/actions off-main would
change state and teardown synchronization and is deliberately not bundled here.
The first lookup after cache invalidation still loads rekordbox XML synchronously;
preloading would move the snapshot time and needs an explicit invalidation design.

Existing suppression bypasses this GUI process's generated CGEvents. Previous
logs showed `pass-self`; its 8ms wait is not a fixed per-SIDE-action delay. Event
tap queueing under load remains a measurement target.

## Next hardware session

1. Compare ACK05 and SIDE on the same action, measuring key press, knob rotation
   and knob push separately (mechanical actuation can affect the presses).
2. Use `OVERCUE_GENERIC_HID_DIAGNOSTICS=1` for a short diagnostic run. Correlate
   IOHID timestamp, callback log, input/route and shortcut trigger. IOHID ticks
   require Mach timebase conversion; do not subtract them directly from seconds.
3. Compare idle GUI vs active GUI and first action vs warm repeated actions.
4. Measure release/hold/repeat, multi-device operation, reconnect and three
   consecutive Learn sessions. Investigate Deck3 Consumer inputs separately.
5. Diagnostic logging itself adds work; do not treat verbose timing as normal-run
  latency. No runtime settings or user mappings were changed during this audit.

## Automated validation

- `swift build`, `swift test`: 35 tests passed (7 read-cache tests added).
- `swift run overcue-checks`: all existing 405 checks passed; none removed.
- `Scripts/verify-macos.sh`: debug/release builds, arm64 + x86_64 app/helper,
  ad-hoc signing and deep/strict codesign verification.

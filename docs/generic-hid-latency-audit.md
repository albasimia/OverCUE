# Generic HID cleanup and latency audit — 2026-09-04 / 2026-09-05

Scope: preserve mapping, Preset ownership, capture lifecycle, suppression and
ACK05 behavior. No real-device input was available for the September 4 audit.
September 5 user-provided diagnostic logs establish a first-touch callback/input
gap; post-fix hardware measurement and Deck3 Learn investigation remain pending.

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
- Generic HID now builds immutable metadata for all interface elements at match,
  rather than on first use of each descriptor. Removal clears that interface's
  catalog; runtime stop/start clears all catalogs and retained interface handles.
  Cookie is never persisted. Routing uses the existing binding-resolved session
  registry (rebuilt on match/remove/config reload), not property reads on input.
- Parsed shortcuts are reused by their exact source string and invalidated with
  the existing mode mapping cache. Action phases and output ordering are unchanged.
- Optional input diagnostics now include the original IOHID timestamp at callback
  entry, before metadata resolution, alongside existing monotonic log times.

## Measurements and limits

September 5 user evidence: Deck1 Right callback ~66071.905 → input ~66072.669
(764ms); Left raw/callback ~66072.663 → input ~66073.413 (750ms), with similar
Click stalls and queued bursts. Three SIDE devices route to separate Deck1/2/3
Presets/commands correctly. Deck2 Right/Click lack mappings by user configuration;
their misses are expected, not evidence of a routing bug.

Code cause: each first descriptor performed a complete
`IOHIDDeviceCopyMatchingElements` scan and rebuilt every candidate collection path.
The warm cache introduced September 4 did not remove those first-touch scans.
The new catalog enumerates once, snapshots every descriptor, and counts identical
descriptors in a batch. Full descriptor equality (including report/path) is
unchanged; duplicate counts >1 stay unpersistable. Duplicate cookie keys are
omitted fail-closed. Input is interface/cookie lookup → normalize → existing route.

Preload runs synchronously at match on the existing IOHID main-runloop owner,
before the new interface can process input. This deliberately avoids introducing
cross-thread IOHID lifetime/removal races: Apple's public implementation of
[IOHIDDeviceCopyMatchingElements](https://github.com/apple-oss-distributions/IOKitUser/blob/main/hid.subproj/IOHIDDevice.c)
also updates device/element internals, rather than being a pure read. No new
threading ownership is introduced. Startup/hotplug may still pause the UI/other
interfaces; this is not a real-time guarantee or a measured end-to-end improvement.
Ready catalogs survive ordinary config reload. Nil/empty enumeration stays
unready and inputs fail closed, without replay or an input-triggered retry.
Match/config reload/restart retries preload; reconnect starts a fresh catalog.
Diagnostic `metadata preparing` / `ready` / `failed` timestamps expose preload
cost, and `metadata miss` identifies dropped unready/unknown-cookie input.
Callback/input timestamps remain available; diagnostic interpolation stays lazy.

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

For this fix first run each of Deck1, Deck2, Deck3 in order: Right ×3, Left ×3,
Click ×3, with diagnostics enabled and catalogs ready. Confirm no ~750ms
callback→input first-touch gap or subsequent burst, routing remains isolated,
and hit/miss matches saved mappings (Deck2 Right/Click misses are expected).
Then check reconnect catalog rebuild and unchanged hold/release behavior.

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

- September 5: `swift build`, `swift test`: 42 tests passed (7 catalog tests added
  to the previous 35). Includes structural callback no-scan guard, exact metadata,
  ambiguity, unique E9/EA/E2, report/path identity, three-interface lifecycle and
  failed preload retry without input-side enumeration. No timing thresholds.
- `swift run overcue-checks`: 412 checks passed (7 added); none removed.
- `Scripts/verify-macos.sh`: debug/release builds, arm64 + x86_64 app/helper,
  ad-hoc signing and deep/strict codesign verification.
- `aal doctor`: 0 failures / 0 warnings; `git diff --check`: passed.

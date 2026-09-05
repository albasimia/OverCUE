# Three devices / single light request — 2026-09-04

## Status: completed after explicit approval

User requested all three devices off, then one switch lit per device, with one blue. Proposed mapping: 592B14678182 blue; 2D3B07678182 green; 3F8701678182 red; key_index0 only.

Prepared fixed LED probe --three-single-lights. Plan: read all three baseline lighting configs and both RGB chunks (57 bytes); switch all to mode0 via official06 16/0B; write two RGB chunks with only key0 nonzero; read back all57 bytes; transition to custom mode5 via official06 16/0B; verify config. No retry or arbitrary CLI payload.

Automatic approval review rejected execution before process launch. Reason: multiple HID mutations overwrite all three RGB arrays/modes, missing rollback on later-device failure, and green/red choices and persistence-affecting sequence were not explicitly approved. No alternative or indirect device execution was attempted. No device reports were sent for this request.

Manufacturer apps/Web apps were not launched. Flash/RAM persistence remains unknown. Prepared code is not a completed device change. Await explicit user confirmation of the concrete mapping and mutation behavior before any live execution; failure recovery needs review before resuming.

Static packet checks reconstruct all57 RGB bytes from the two official bulk packets; other18 entries are zero. Build passed.

## Approved execution — 16:00:45 JST

User explicitly approved the proposed colors and persistence/partial-failure conditions. The fixed sequence then ran once successfully. All three were switched to mode0 first, then configured to mode5 with only key0 nonzero. Full57-byte RGB readback matched each desired array. Mode config readback matched each response-derived custom setter.

- 592B14678182: key0 #0000FF; other18 entries zero.
- 2D3B07678182: key0 #00FF00; other18 entries zero.
- 3F8701678182: key0 #FF0000; other18 entries zero.

All three baseline lighting configs and full57-byte RGB arrays are preserved in `docs/evidence/koolertron-three-single-lights-baseline.json`. Raw request/response log: `docs/evidence/koolertron-three-single-lights-20260904.log`. No retry, Feature or firmware command. Physical appearance remains for user confirmation.

Build, offline packet checks, swift test, Core checks, macOS verification and AAL doctor passed during preparation. No code edits in the approved execution turn; no commit.

## 2026-09-04: USB reconnect retention — user observation

The user reports that the LED colors did not change after unplugging and reconnecting USB at home.

- Confirmed (user observation): color retention across USB unplug/reconnect. No HID requests or manufacturer apps were run by the assistant in this reporting turn.
- Strong inference: the preceding mode/bulk RGB setup persisted in device-side nonvolatile storage. Do not assume these settings are RAM-only.
- Unknown: storage medium (flash/EEPROM), immediate versus delayed commit, endurance, and which command triggers persistence. This observation after a sequence containing 06 12/06 0B/06 16 does not isolate persistence of 06 14 alone.
- The report does not specify unplug duration, per-Serial test coverage, or raw post-reconnect values. Do not promote it to verified 57-byte equality or independently verified power-cycle tests on each of the three units.

This observation does not establish suitability for high-frequency LED writes.

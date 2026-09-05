# SIDE-KEYBOARD official lighting modes and global color fields

## Scope

- Date: 2026-09-05 JST
- Exact live target only: Serial `592B14678182`, VID/PID `0816:246E`, Usage `FF00:0002`, Report ID 0, 64-byte Input/Output.
- Official SDTech Option 1.0.3 modes and setter fields only. No unknown mode, `06 12`, Feature Report, Layer, firmware operation, retry, loop, or other Serial.
- Static source: `app.asar/src/_next/static/chunks/app/page-58ff86c8ca1ede81.js`, SHA-256 `cf0bbdb35a701c77e6e2191564811126f4a75463e45fb5f159fa29cc8797e965`.
- Target layout: chunk `2166.7386f653e56f5890.js`, SHA-256 `e25436e7c2543ed161598c65aacfd96820502a429716c3481be9bbd77191a038`.

## Static result

The target layout defines exactly these modes:

| Mode | Resource name | Controls exposed by the official UI |
|---:|---|---|
| 0 | 关闭 | none |
| 1 | 常亮 | brightness, global color/palette |
| 2 | 呼吸 | brightness, speed, global color/palette |
| 3 | 按亮 | brightness, speed, global color/palette |
| 4 | 潮汐 | brightness, speed, global color/palette |
| 5 | custom | brightness and per-key RGB editor |

`setLightConfig` constructs offsets 5...15 as:

```text
type, 00, mode, brightness, speed, direction, color, 00, H, S, V
```

Offset 11 `color` is the official UI's single-color checkbox: `0` selects the effect palette and `1` selects offsets 13...15 HSV. Offset 12 is read as `singleColorIndex`, but the public setter always transmits zero. No effect target key, key mask, or per-key palette-source field exists in the target layout or lighting UI call sites. Per-key RGB is a separate `06 13` / `06 14` / `06 12` table used by Custom mode 5.

The bundled `4keysd_v101.bin` is 32,768 opaque bytes (SHA-256 `eb04115e950d2e257311189de6e702f137ce4067df8adbc1691b4b577423098d`). Plain strings do not expose the lighting field implementation, so no firmware claim is based on that binary.

## Official `06 16` response comparison

Each row is the 11-byte response block at offsets 5...15. Modes 0, 2, 4, and 5 reuse earlier captures from the same Serial; modes 1 and 3 were captured in this trial. Each live transition used `06 16(mode)` followed by `06 0B` derived from that response.

| Mode | offsets 5...15 (`type reserved mode brightness speed direction color index H S V`) |
|---:|---|
| 0 | `01 00 00 83 15 00 00 25 01 75 01` |
| 1 | `01 00 01 04 02 01 00 07 00 FF FF` |
| 2 | `01 00 02 04 02 00 00 07 FF FF FF` |
| 3 | `01 00 03 04 02 00 00 07 FF FF FF` |
| 4 | `01 00 04 04 02 00 00 07 FF FF FF` |
| 5 | `01 00 05 04 02 01 00 07 FF FF FF` |

Mode 0's inactive fields contain values outside the UI ranges and must not be interpreted as valid brightness/speed parameters. Direction values are also present for modes whose target layout hides direction. Only fields enabled for a mode should be treated as semantically active.

## Mode 3: per-key RGB versus global palette

Before mode 3, RGB readback was key0 `000000`, key1 `000000`, key2 `7FFF08`, key3 `FF0000`. The unexpected key2 value was already present in the first preflight and remained byte-identical through all mode transitions; this trial sent no RGB setter.

With the response-derived mode 3 config (`color=0`), the user observed:

- every switch lights only while pressed and goes dark on release;
- every switch changes color on each press;
- the stored per-key RGB values do not determine the visible pressed color.

The official single-color setter semantics were then applied once: mode 3, `color=1`, HSV `00 FF FF` (red). The user observed that every switch lights red while pressed, no longer changes color, and goes dark on release. Device readback kept `color=1` and HSV red, while offset 12 changed from the transmitted `00` to `FF`. This rules out offset 12 as a direct effect target key mask in this path.

## Mode 2: single-color breathing

Mode 2 was selected through the official response-derived sequence, then the same official single-color red fields were applied once. The user observed:

- all switches breathe red;
- the color does not change during the effect;
- speed remains comparable to the earlier palette breathing test;
- the fade reaches full darkness.

Therefore mode 2 supports an all-key, fixed-HSV breathing state. It still does not use or mask by the per-key RGB table.

## Final state and interpretation

The device was returned to mode 5 through the official sequence without an RGB write. Final `06 0A` and `06 13` readbacks succeeded. The RGB table remained key0/key1 black, key2 `#7FFF08`, key3 red.

Confirmed candidate behavior, without adopting runtime integration in this change:

```text
PLAY  -> mode 5, per-key Custom display
PAUSE -> mode 2, color=1, Deck-color HSV, all keys breathe
```

Mode changes and color settings may be nonvolatile. Storage medium and write endurance remain unknown; this result does not authorize high-frequency runtime writes.

## Power-cycle retention

At `10:57:38Z`, the same Serial was switched from mode 5 to its already-saved mode 2 single-red config. The response-derived transition and immediate getter both returned:

```text
offsets 5...15: 01 00 02 04 02 00 01 FF 00 FF FF
```

The user unplugged only this device, waited approximately ten seconds, reconnected it without opening the official app or operating OverCUE, and visually confirmed that all keys immediately resumed red breathing.

One read-only `06 0A` at `10:58:40Z` returned the same 11-byte config exactly. One read-only `06 13` at `10:58:53Z` also returned the same RGB chunk as before power loss: key0/key1 black, key2 `7FFF08`, key3 `FF0000`.

This is strong device-side evidence that the selected mode and its global color parameters survive full USB power loss. It does not identify flash versus EEPROM or establish endurance, but it makes frequent Play/Pause-driven `06 0B` mode writes unsafe to adopt without further evidence. Final device state is mode 2, all-key single-red breathing.

# Koolertron breathing trial — Phase A

- Time: `2026-09-05T09:31:09Z`
- Target only: SDINNOVATION SIDE-KEYBOARD `0816:246E`, Serial `592B14678182`, `FF00:0002`, Report ID 0, 64-byte Input/Output
- No automatic retry, bulk write, Feature Report, layer, brightness, speed or direction write.

## Baseline responses

`06 0A` response, 64 bytes:

```text
AA 0A 0B 00 00 01 00 01 04 02 01 00 07 00 FF FF 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Interpreted current mode: `1`. Unchanged config fields captured at offsets 5...15: `01 00 01 04 02 01 00 07 00 FF FF`.

`06 13` response, 64 bytes:

```text
AA 13 3A 00 00 00 00 00 00 00 FF 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Key 0...3 RGB: `0000FF`, `000000`, `000000`, `000000`.

## Phase A writes and readback

Only differing entries were written with `06 14`: key0 → `000000`, key3 → `FF0000`. Key1/key2 were already black and received no setter. Custom mode used `06 16(mode=5)` followed by `06 0B` derived from response offsets 5...15, changing offset 7 only.

Final `06 13` readback, 64 bytes:

```text
AA 13 3A 00 00 00 00 00 00 00 00 00 00 00 00 00 00 FF 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Confirmed by protocol readback: key0 `000000`, key1 `000000`, key2 `000000`, key3 `FF0000`. Phase A stops in mode 5 pending visual gate A. No breathing command and no rollback have been sent.

## Visual gate A and Phase B

Visual gate A: user confirmed Deck3 SIDE SW4 alone was steadily red.

At `2026-09-05T09:34:40Z`, mode 2 was selected on the same Serial only. `06 16(mode=2)` response, 64 bytes:

```text
AA 16 0B 00 00 01 00 02 04 02 00 00 07 FF FF FF 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

The response-derived `06 0B` request copied offsets 5...15 and changed offset 7 only to `02`. Response, 64 bytes:

```text
AA 0B 01 00 00 01 00 02 04 02 00 00 07 FF FF FF 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Both transactions returned successful IOReturn and corresponding 64-byte responses. No retry, RGB write, other-device send or rollback occurred. Device remains in mode 2 pending visual gate B.

## Visual gate B

User observation:

- All four switches breathe; SW4 is not isolated.
- SW1...3 do not remain dark.
- SW4 does not remain red; all switches cycle through multiple colors.
- Breathing speed itself is practical for a Play/Pause indication.

Therefore built-in mode 2 is not suitable for the requested per-key, Deck-color Play/Pause display. It is a global multicolor effect on this hardware/configuration.

## Rollback

At `2026-09-05T09:37:22Z`, only key0 and key3 were restored by `06 14`: key0 `0000FF`, key3 `000000`. The original mode 1 was restored using `06 16(mode=1)` and the response-derived `06 0B`, preserving response offsets 5...15 except the requested mode byte.

Post-rollback `06 0A`, 64 bytes:

```text
AA 0A 0B 00 00 01 00 01 04 02 01 00 07 00 FF FF 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Post-rollback `06 13`, 64 bytes:

```text
AA 13 3A 00 00 00 00 00 00 00 FF 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Both captured 64-byte ranges match Phase 1 byte-for-byte. Every SetReport returned success and every expected 64-byte response arrived. No automatic retry, `06 12`, Feature Report, Layer change, other Serial, intentional brightness/speed/direction change, loop or high-frequency update was used.

## Result classification

| Item | Classification | Result |
| --- | --- | --- |
| Mode 2 request/response | Confirmed | Official response-derived sequence accepted |
| Per-key RGB respected visibly | Visual | No |
| Black keys remain dark | Visual | No |
| Only key3 breathes | Visual | No; all keys breathe |
| Key3 stays red | Visual | No; colors cycle |
| Breathing speed | Visual | Usable |
| RGB storage while mode 2 is active | Unknown | No RGB getter was permitted during gate B |
| Rollback captured ranges | Confirmed | Lighting and RGB 64-byte responses equal baseline |

# Koolertron binary Play/Pause finite trial

## Scope

- Date: 2026-09-05 JST
- Exact target only: SIDE-KEYBOARD Serial `592B14678182`, `0816:246E`, `FF00:0002`, Report ID 0, 64-byte Input/Output.
- Visual convention tested: PLAY = Custom mode 5 with key3 red/key0...2 black; PAUSE = mode 0.
- One finite PLAY → PAUSE → PLAY transition. No loop, retry, bulk RGB write, Feature Report, Layer change or other Serial.

## Starting PLAY state

At `10:23:42Z`, key0 was changed from baseline blue to black and key3 from black to red using only required `06 14` writes. Key1/2 were already black and were not written. Mode 5 was applied with `06 16` followed by response-derived `06 0B`; `06 13` readback was key0...3 `000000 / 000000 / 000000 / FF0000`. User visually confirmed SW4 alone was steadily red.

## PAUSE

At `10:24:45Z`, `06 16(mode=0)` returned:

```text
AA 16 0B 00 00 01 00 00 83 15 00 00 25 01 75 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Its offsets 5...15 were copied into `06 0B`, changing only the requested mode byte to 0. The setter response carried the same config block. User visually confirmed all switches were dark.

## PLAY restoration

At `10:25:36Z`, without any RGB rewrite, `06 16(mode=5)` returned:

```text
AA 16 0B 00 00 01 00 05 04 02 00 00 07 FF FF FF 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Response-derived `06 0B` was accepted. User visually confirmed SW4 alone was steadily red and SW1...3 stayed dark.

Final getter-only verification:

```text
lighting: AA 0A 0B 00 00 01 00 05 04 02 00 00 07 FF FF FF 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
rgb:      AA 13 3A 00 00 00 00 00 00 00 00 00 00 00 00 00 00 FF 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Final state is intentionally PLAY: mode 5, key3 red, key0...2 black.

## Conclusion and remaining gate

Confirmed by protocol and visual observation: mode 0/5 can express the required binary state, and mode 0 does not erase the saved per-key RGB. This does not prove writes are volatile or safe over a product lifetime. Runtime integration must avoid synchronous HID writes on the input hot path, suppress duplicate state writes, serialize transitions, and establish an acceptable persistence/write-cadence policy. It must not implement blinking by repeated writes.

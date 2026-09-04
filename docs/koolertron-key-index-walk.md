# Key index walk — 2026-09-04

User requested key_index0,1,2,3 illuminated one at a time. Executed once on the three known serials, retaining blue / green / red. Fixed five-second holds; restored index0 afterward. Baseline mode5 and first RGB chunk matched expected before any mutation. Every transition extinguished the previous key and lit the next, then verified the full64-byte RGB chunk.

## Timeline (UTC; JST = +9h)

```text
2026-09-04T08:50:28Z OBSERVE key_index=0 for 5 seconds
2026-09-04T08:50:33Z OBSERVE key_index=1 for 5 seconds
2026-09-04T08:50:38Z OBSERVE key_index=2 for 5 seconds
2026-09-04T08:50:43Z OBSERVE key_index=3 for 5 seconds
2026-09-04T08:50:48Z PASS all three restored to key_index=0; RGB chunk verified
```

All stages passed readback on all3 devices. Final key0 blue (592B14678182), green (2D3B07678182), red (3F8701678182); remaining captured RGB zero. No mode/brightness/firmware/Feature commands, retry or repeated walk. Forty-two getter/setter Output requests total: six baseline getters,24 single-key06 14 writes,12 verification06 13 getters. All returned success and64-byte corresponding responses. Physical LED/index mapping awaits user observation. RGB final array byte56 not fetched this time.

Raw log: [evidence](evidence/koolertron-key-index-walk-20260904.log).

Implementation is limited to LED probe KeyIndexWalk.swift and a strict --walk-key-indices entry. Fixed three devices, finite transitions, no arbitrary payload or index CLI. Build and offline index packet verification passed. No commit.

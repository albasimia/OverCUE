# Decision: Koolertron LED protocol exploration stays isolated from runtime

## Context

Koolertron系Generic HIDのLEDを将来的にrekordbox状態へ同期したい。現行`codex/performance-4deck`はGeneric HID runtime / Learn / suppression / ownershipに実機未完了ゲートを残しており、LED探索を同じruntimeへ混ぜると入力経路の回帰原因になる。

## Decision

- LED protocol探索は`codex/koolertron-led-probe`で行う。
- 最初の段階では`overcue-probe`だけを変更し、OverCUEApp / OverCUEBridge / GenericHIDRuntimeCoordinator / ActionLayer / config schemaへ接続しない。
- `--list` / `--describe`はshared-openのread-only inspectionとし、Output Report / Feature Reportを書き込まない。
- VID/PID、interface metadata、HID element type、Usage Page / Usage、Report ID、Report size/count、Output/Feature要素の存在を観測証拠として採取する。
- 未知デバイスへ推測したReportを総当たり送信しない。
- HID Output/Featureの意味が実機証拠で特定されるまで、LED driver・rekordbox MIDI OUT・state manager・GUI/config統合へ進まない。
- 将来の書き込み実験を追加する場合も、明示的なtarget指定と単一Report送信に限定し、通常runtimeから呼ばない。

## Consequences

既存の入力→Action→rekordbox経路へ変更を入れずにKoolertronの出力能力を調査できる。プロトコル確定後の本体統合は別decision・別commitとして扱う。

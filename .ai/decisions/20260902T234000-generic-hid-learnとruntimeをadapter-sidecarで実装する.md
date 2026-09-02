# Generic HID Learnとruntimeをadapter sidecarで実装する

- Date: 2026-09-02
- Status: accepted
- AAL-Change-Id: 20260902T234000-generic-hid-learn-runtime

## Context

`SDINNOVATION / SIDE-KEYBOARD`実機でGeneric HIDのPhysical Bindingと入力descriptorを確認した。

Physical identityはVID / PID / Serial Numberで成立し、同じUSB portへの抜き差しと別hub portへの移動の双方で既存Logical Deviceへ復帰した。Key 1〜4、Knob Right / Left / Pushはすべて既存`GenericHIDInputDescriptor`でpersistableなpress/releaseとして取得できる。

次の段階として、Generic HID入力をrekordbox / OverCUE ActionへLearnし、ACK05と同時にruntimeで使用する必要がある。

現行`config.json`はversion 10であり、Preset / Group Preset / Logical Device / Physical Bindingのmigrationと3-way mergeが既に安定している。Generic HID固有の入力descriptor配列を急いでmain schemaへ追加すると、adapter固有データのためにconfig migration面を広げる。

## Decision

- `config.json`はversion 10のまま維持する。
- Generic HIDのLearn済み入力割り当ては`~/Library/Application Support/OverCUE/generic-hid.json`へ保存する。
- sidecar schemaはversion 1とし、Logical Device ID → Preset stable ID → Generic HID input assignmentで保持する。
- assignmentは`GenericHIDInputBindingKey`と`ActionTarget.configurationValue`を保存する。rekordboxのDeck scopeは選択したActionTarget側に保持し、Generic HID側へ別Deck設定を作らない。
- UIはDevices内のGeneric HID Logical Device detailへLearnを置き、Preset単位で入力を割り当てる。
- Learn時は登録済みPhysical BindingのVID / PID / Serialへ限定し、`GenericHIDLearnSession`とpersistent input判定を使う。
- Generic HID runtimeはOverCUEアプリ側で動かし、既存`overcue-cli`と同じ入力ON/OFF lifecycleへ接続する。
- runtimeは登録済みGeneric HIDだけをIOHID matchingし、通常動作時はexclusive captureする。これによりConsumer Control型ノブがmacOSのVolume+/Volume-/Muteとして同時発火することを防ぐ。
- Identify / Learnはshared modeのままとし、不特定のkeyboard / mouseをseizeしない。
- composite HIDはlive attachment内でpersistent identity + locationIDを使って1 runtime Physical Deviceへ束ねる。locationIDはpersistent identityへ昇格させない。
- runtimeは標準`OverCUERuntimeStatusNotification` / `OverCUERuntimeControlNotification`を使用し、既存Group Preset coordinatorとLogical Device scopeへ接続する。
- Action実行は`GenericHIDActionResolver`から既存Action Layerへ流し、rekordbox command ID / KeyMappings XML / keyboard outputをGeneric descriptor層へ持ち込まない。
- 実機固有VID / PID / usage値をproduction runtimeへハードコードしない。

## Consequences

- Generic HID adapter固有schema変更でmain config versionを上げずに済む。
- Learn mappingはLogical DeviceとPreset stable IDへ追従し、Physical Device sessionやUSB port位置には依存しない。
- Group Preset変更後も既存device-scoped runtime controlでGeneric HIDのPresetを切り替えられる。
- SIDE-KEYBOARDのVolume系Consumer Controlは通常runtime中macOSへ漏らさず、OverCUE専用入力として扱える。
- sidecarを将来main configへ統合する場合は、adapter-neutral input mapping schemaが固まった時点で明示的migrationを設計する。

## 未確認

- 本実装のmacOS local build / test / verify。
- Learn UIで7入力を実際に登録し、rekordbox前面時にActionが発火すること。
- runtime中にSIDE-KEYBOARDのVolume+/Volume-/MuteがmacOSへ漏れないこと。
- 同型Generic HID複数台を同時接続した場合のSerial個体差。

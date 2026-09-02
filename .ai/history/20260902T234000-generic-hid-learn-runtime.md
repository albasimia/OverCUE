# Generic HID Learn / runtimeを実装

- Date: 2026-09-02
- AAL-Change-Id: 20260902T234000-generic-hid-learn-runtime

## 実機確認の更新

`SDINNOVATION / SIDE-KEYBOARD`を登録後、同じUSB portへの抜き差しと別hub portへの移動の両方で既存`SIDE-KEYBOARD 1`へ解決した。VID / PID / Serial NumberによるGeneric HID persistent bindingが実機で成立した。

## 実装

- Generic HID Learn mapping sidecar `generic-hid.json`を追加。
- Logical Device ID × Preset stable IDでGeneric HID input→ActionTargetを保存。
- Devices detailへGeneric HID mapping sectionを追加。
- rekordbox KeyMappingsから実際のscope付きActionTargetを選択し、実機入力をLearnできるUIを追加。
- LearnはPhysical BindingのVID / PID / Serialへ限定し、persistent descriptorだけ保存。
- app-side Generic HID runtimeを追加。
- runtimeは登録済みGeneric HIDだけをIOHID matchingし、exclusive captureする。
- composite interfaceはpersistent identity + locationIDでlive attachmentを束ねる。
- `GenericHIDEventNormalizer` → `GenericHIDActionResolver` → Action Layerへ入力を流す。
- rekordbox前面時のみ選択中KeyMappingsのshortcutをkeyboard eventとして送る。
- Cue hold、Jump accelerating repeat、Cycle Preset、Preset単位mapping、Group Preset device-scoped controlをGeneric HID runtimeへ接続。
- runtime statusを既存通知へpublishし、Devicesの接続状態とGroup Preset coordinatorがGeneric HIDを扱えるようにした。
- ACK05 CLI runtimeとGeneric HID app runtimeを同じ入力ON/OFF lifecycleへ接続。
- SIDE-KEYBOARDのConsumer ControlノブがmacOS音量操作として漏れないよう、通常runtimeはbound Generic HIDのみexclusive captureする。Identify / Learnはsharedのまま。
- 実機固有VID / PID / usageはruntimeへハードコードしていない。

## 保存境界

main `config.json`はversion 10を維持する。Generic HID adapter固有のLearn mappingはversion 1 sidecarへ分離し、main configのPreset / Group Preset / Logical Device / Physical Binding schemaを変更しない。

## 検証状況

GitHub connector経由で実装したため、macOS local build / test / verifyは未実施。次の実機ゲートはアプリをbuildし、SIDE-KEYBOARDの接続表示、Learn、rekordbox Action発火、Volume系Consumer Control抑止を確認すること。

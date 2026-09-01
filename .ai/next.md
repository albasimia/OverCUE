# Next

## 現在のフェーズ

Preset Group / Shortcut Scope version 10に、ACK05複数台の実機証拠を反映したDevices UIとPreset Group管理を追加した。GitHub connector経由の実装なので、現HEADのローカルbuild / test / verifyは未実施。

## ACK05複数台 実機確認済み

- [x] ACK05 2台を同時接続し、別IOHID sessionとして認識。
- [x] REPORT / normalized VALUEのsourceが2台で分離。
- [x] 片方の電源OFF / ONでsession更新と入力復帰を確認。
- [x] PhysicalDeviceUniqueID / locationID / DeviceAddressはACK05電源OFF / ONを跨いで維持。
- [x] Mac再起動後もPhysicalDeviceUniqueID / locationID / DeviceAddressを維持。
- [x] Serial Numberは2台とも取得不可。
- [x] Bluetooth再ペアリング後はPhysicalDeviceUniqueID / locationID / DeviceAddressがすべて変化。

Decision `20260901T234500-6f42c1`により、ACK05ではPhysicalDeviceUniqueIDをPairing Identityとして使用し、再ペアリング時はIdentify / Rebindする。

## 今回実装したUI

- [x] top navigation: Shortcuts / Devices / Settings。
- [x] Shortcutsは既存2カラムを維持し、第3カラムを追加しない。
- [x] Devices画面: Logical Device一覧 / detail。
- [x] Add ACK05 / Identify / Rebind / Forget Binding。
- [x] Logical Device rename / existing Profile assignment。
- [x] Pairing IDとruntime connection状態表示。
- [x] Identify中はACK05 runtimeを一時停止し、完了後に元の有効状態へ復帰。
- [x] Preset Group Add / Rename / Delete。
- [x] Preset Group上限24、opaque stable IDで追加。
- [x] 最初のPresetと最後の1個は削除不可。
- [x] Settings top-level画面。

## 最優先: macOSローカル検証

- [ ] `aal context build --mode implementation`
- [ ] `swift build`
- [ ] `swift test`
- [ ] `swift run overcue-checks`
- [ ] `./Scripts/verify-macos.sh`
- [ ] `aal doctor`
- [ ] `git diff --check`

## UI実機ゲート

- [ ] Devices > Add ACK05で2台を別Logical Deviceとして登録できる。
- [ ] 2台それぞれのPairing IDが異なることをUIで確認。
- [ ] 通常の電源OFF / ONとMac再起動後に同じLogical Deviceへ復帰する。
- [ ] Bluetooth再ペアリング後は旧Bindingへ自動復帰せず、Rebindで復旧する。
- [ ] Identify中に通常runtimeとのIOHID exclusive access競合が起きない。
- [ ] Preset Groupを5個以上まで追加し、name selector / Cycle Presetが存在するPresetだけをorder順に巡回する。
- [ ] Preset rename / delete後もstable ID選択とruntime controlが破綻しない。

## Generic HID 実機ゲート

- [ ] `overcue-probe --all`でKoolertron候補のVID / PID / Serial / Usage / Report ID / press-release / relative deltaを採取。
- [ ] 同型Generic HID複数台のSerial有無と再接続時descriptor安定性を確認。
- [ ] Generic HID identity証拠に基づいてDevicesのAdd Generic HID / Learnを有効化する。

## その他

- [ ] Deck 4 shortcutを含むrekordbox KeyMappings XMLで`33xx`を直接確認。
- [ ] 最初のPresetへ埋め込まれているCycle Preset操作を将来global mappingへ分離し、最初のPreset削除制約を解消する。
- [ ] Parent Preset / Scene。
- [ ] GitHub Actions復旧。
- [ ] Developer ID署名とnotarization。

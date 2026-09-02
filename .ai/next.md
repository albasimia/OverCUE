# Next

## 現在のフェーズ

Preset / Shortcut Scope version 10に、ACK05複数台の実機証拠を反映したDevices UI、Preset管理、Group Presetを追加した。Group Preset専用画面をトップレベルへ追加し、全Logical Deviceのinclusion / Preset参照を一画面で編集できるようにした。GitHub connector経由の実装なので、現HEADのローカルbuild / test / verifyは未実施。

Group PresetはLogical Deviceごとに参照するPreset stable IDを保持する親設定とする。Group Preset切替時は接続中の各Logical Deviceへdevice-scoped runtime controlを送り、指定Presetを初期状態として適用する。以後のCycle Presetは各デバイスの一時runtime stateとして維持し、通常のstatus/config更新ではGroup Presetの初期値へ巻き戻さない。

## ACK05複数台 実機確認済み

- [x] ACK05 2台を同時接続し、別IOHID sessionとして認識。
- [x] REPORT / normalized VALUEのsourceが2台で分離。
- [x] 片方の電源OFF / ONでsession更新と入力復帰を確認。
- [x] PhysicalDeviceUniqueID / locationID / DeviceAddressはACK05電源OFF / ONを跨いで維持。
- [x] Mac再起動後もPhysicalDeviceUniqueID / locationID / DeviceAddressを維持。
- [x] Serial Numberは2台とも取得不可。
- [x] Bluetooth再ペアリング後はPhysicalDeviceUniqueID / locationID / DeviceAddressがすべて変化。

Decision `20260901T234500-6f42c1`により、ACK05ではPhysicalDeviceUniqueIDをPairing Identityとして使用し、再ペアリング時はIdentify / Rebindする。

## 今回実装したUI / 設定

- [x] top navigation: Shortcuts / Devices / Group Preset / Settings。
- [x] Shortcutsは既存2カラムを維持し、第3カラムを追加しない。
- [x] Devices画面: Logical Device一覧 / detail。
- [x] Add ACK05 / Identify / Rebind / Forget Binding。
- [x] Logical Device rename / existing Profile assignment。
- [x] Pairing IDとruntime connection状態表示。
- [x] Identify中はACK05 runtimeを一時停止し、完了後に元の有効状態へ復帰。
- [x] Preset Add / Rename / Delete。
- [x] Preset上限24、opaque stable IDで追加。
- [x] 最初のPresetと最後の1個は削除不可。
- [x] UI上の旧Preset Group表記をPresetへ統一。
- [x] Group Preset Add / Rename / Delete / active selector。
- [x] Group PresetごとにLogical Device inclusionと参照Presetを設定。
- [x] Group Preset専用画面で全Logical Deviceのinclusion / Preset参照を一覧編集。
- [x] Devices画面内のGroup Preset個別編集導線も維持。
- [x] Preset削除・Profile変更時にGroup Presetのdangling referenceを残さない。
- [x] Group Preset assignmentをconfig 3-way merge対象に追加。
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
- [ ] Presetを5個以上まで追加し、name selector / Cycle Presetが存在するPresetだけをorder順に巡回する。
- [ ] Preset rename / delete後もstable ID選択とruntime controlが破綻しない。
- [ ] Group Presetを複数作成し、ACK05ごとに異なるPresetを指定して一括切替できる。
- [ ] Group Preset専用画面で複数Logical Deviceを一覧し、include / Presetを横断編集できる。
- [ ] Group Preset切替後に各ACK05でCycle Presetし、他ACK05操作や通常config更新で初期Presetへ巻き戻らない。
- [ ] Group Presetから除外したLogical Deviceのruntime stateを意図せず変更しない。

## Generic HID 実機ゲート

- [ ] `overcue-probe --all`でKoolertron候補のVID / PID / Serial / Usage / Report ID / press-release / relative deltaを採取。
- [ ] 同型Generic HID複数台のSerial有無と再接続時descriptor安定性を確認。
- [ ] Generic HID identity証拠に基づいてDevicesのAdd Generic HID / Learnを有効化する。

## その他

- [ ] Deck 4 shortcutを含むrekordbox KeyMappings XMLで`33xx`を直接確認。
- [ ] 最初のPresetへ埋め込まれているCycle Preset操作を将来global mappingへ分離し、最初のPreset削除制約を解消する。
- [ ] GitHub Actions復旧。
- [ ] Developer ID署名とnotarization。

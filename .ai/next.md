# Next

## 現在のフェーズ

Preset / Shortcut Scope version 10に、ACK05複数台の実機証拠を反映したDevices UI、Preset管理、Group Presetを追加した。Group Preset専用画面をトップレベルへ追加し、全Logical Deviceのinclusion / Preset参照を一画面で編集できるようにした。ACK05 USB接続については、Serial / PhysicalDeviceUniqueIDを取得できない実機に対し、USB topologyの`locationID`をSlot Identityとして使う実装を追加した。Generic HIDについては`SDINNOVATION / SIDE-KEYBOARD`実機でSerialと全7入力descriptorを確認し、Serial Numberを持つGeneric HIDのDevices登録を有効化した。GitHub connector経由の実装なので、現HEADのローカルbuild / test / verifyは未実施。

Group PresetはLogical Deviceごとに参照するPreset stable IDを保持する親設定とする。Group Preset切替時は接続中の各Logical Deviceへdevice-scoped runtime controlを送り、指定Presetを初期状態として適用する。以後のCycle Presetは各デバイスの一時runtime stateとして維持し、通常のstatus/config更新ではGroup Presetの初期値へ巻き戻さない。

## ACK05複数台 実機確認済み

- [x] ACK05 2台を同時接続し、別IOHID sessionとして認識。
- [x] REPORT / normalized VALUEのsourceが2台で分離。
- [x] 片方の電源OFF / ONでsession更新と入力復帰を確認。
- [x] PhysicalDeviceUniqueID / locationID / DeviceAddressはACK05電源OFF / ONを跨いで維持。
- [x] Mac再起動後もPhysicalDeviceUniqueID / locationID / DeviceAddressを維持。
- [x] Serial Numberは2台とも取得不可。
- [x] Bluetooth再ペアリング後はPhysicalDeviceUniqueID / locationID / DeviceAddressがすべて変化。

Decision `20260901T234500-6f42c1`により、ACK05ではPhysicalDeviceUniqueIDをBLE Pairing Identityとして使用し、再ペアリング時はIdentify / Rebindする。

## ACK05 USB 実機確認済み

- [x] USB接続ではSerial Numberが空白、PhysicalDeviceUniqueID / DeviceAddressは取得不可。
- [x] 1台のACK05が`usagePage=0x0001 / 0x000D / 0xFF0A`の3 IOHID interfaceとして見える。
- [x] 3 interfaceは同一接続中に同じ`locationID`を共有する。
- [x] 同じUSBハブの同じポートへ抜き差し後も`locationID=0x01140000`を維持。
- [x] 同じUSBハブの別ポートへ移すと`0x01130000`→`0x01140000`のように`locationID`が変化。
- [x] IORegistryの`Shortcut Remote@01140000`と`locationID=0x01140000`が一致。

Decision `20260902T215700-ack05-usb-slot-identity`により、ACK05 USBでは`locationID`を物理個体IDではなくUSB Slot Identityとして使う。同じslotの3 IOHID interfaceは1 runtime sessionへ束ね、ポートを移した場合は別slotとして扱う。Generic HIDへは一般化しない。

## Generic HID 実機確認済み

対象: `SDINNOVATION / SIDE-KEYBOARD`, VID `0x0816`, PID `0x246E`。

- [x] Serial Number `3F8701678182`を取得。
- [x] 1台が3 IOHID interfaceとして列挙され、3 interfaceでVID / PID / Serial / locationIDが一致。
- [x] Key 1〜4: Keyboard page `0x0007`, usage `0x0059`〜`0x005C`, persistable=true。
- [x] Knob Right: Consumer page `0x000C`, usage `0x00E9`, report 3, persistable=true。
- [x] Knob Left: Consumer page `0x000C`, usage `0x00EA`, report 3, persistable=true。
- [x] Knob Push: Consumer page `0x000C`, usage `0x00E2`, report 3, persistable=true。
- [x] ノブはrelative deltaではなく、Right / Left / Pushが独立Consumer Control press/releaseとして取得される。

Decision `20260902T231600-generic-hid-register`により、SerialをGeneric HID persistent identityとして使い、Identify中はpersistent identity + locationIDで同一live attachmentの複数interfaceを束ねる。locationID自体はpersistent identityへ昇格させず、同一Serialが別live attachmentに同時出現した場合はambiguityで拒否する。

## 今回実装したUI / 設定

- [x] top navigation: Shortcuts / Devices / Group Preset / Settings。
- [x] Shortcutsは既存2カラムを維持し、第3カラムを追加しない。
- [x] Devices画面: Logical Device一覧 / detail。
- [x] Add ACK05 / Identify / Rebind / Forget Binding。
- [x] Add Generic HID / Serial binding / Generic HID Rebind。
- [x] Generic HID Identifyで同一Serial + locationIDの複数interfaceを1 live Physical Device候補へ束ねる。
- [x] Binding解除後はACK05 / Generic HIDのIdentify種別を明示して再登録できる。
- [x] Logical Device rename / existing Profile assignment。
- [x] Physical IDとruntime connection状態表示。
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
- [x] ACK05 USB Slot Identityと同一slot内3 interfaceのruntime session統合。

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
- [ ] USB ACK05をDevices > Add ACK05で登録できる。
- [ ] USB ACK05を同じhub portへ抜き差し後、同じLogical Deviceへ復帰する。
- [ ] USB ACK05を別hub portへ移した場合は旧slot bindingへ自動一致しない。
- [ ] USB ACK05の3 IOHID interfaceがUI / runtime上で1 Physical Deviceとして扱われる。
- [ ] Presetを5個以上まで追加し、name selector / Cycle Presetが存在するPresetだけをorder順に巡回する。
- [ ] Preset rename / delete後もstable ID選択とruntime controlが破綻しない。
- [ ] Group Presetを複数作成し、ACK05ごとに異なるPresetを指定して一括切替できる。
- [ ] Group Preset専用画面で複数Logical Deviceを一覧し、include / Presetを横断編集できる。
- [ ] Group Preset切替後に各ACK05でCycle Presetし、他ACK05操作や通常config更新で初期Presetへ巻き戻らない。
- [ ] Group Presetから除外したLogical Deviceのruntime stateを意図せず変更しない。

## Generic HID 実機ゲート

- [x] `overcue-probe --all`でSIDE-KEYBOARDのVID / PID / Serial / Usage / Report ID / press-release / persistabilityを採取。
- [x] 4キー + Knob Right / Left / Pushのpersistent input descriptorを確認。
- [x] Generic HID identity証拠に基づいてDevicesのAdd Generic HIDを有効化する。
- [ ] Devices > Add Generic HIDでSIDE-KEYBOARDをLogical Deviceへ登録し、SerialがPhysical IDとして表示されることを確認。
- [ ] 同じSIDE-KEYBOARDを抜き差しし、Serialが維持されることを確認。
- [ ] 同型Generic HID複数台のSerialが個体ごとに異なるか確認。異ならない場合はambiguityで拒否されることを確認。
- [ ] Generic HID Learn UIを有効化し、Key 1〜4 / Knob Right / Left / PushをそれぞれActionへ割り当てる。
- [ ] Generic HID runtimeを既存Action Layerへ接続し、Group Preset / Logical Device scopeでACK05と同時使用する。

## その他

- [ ] Deck 4 shortcutを含むrekordbox KeyMappings XMLで`33xx`を直接確認。
- [ ] 最初のPresetへ埋め込まれているCycle Preset操作を将来global mappingへ分離し、最初のPreset削除制約を解消する。
- [ ] GitHub Actions復旧。
- [ ] Developer ID署名とnotarization。

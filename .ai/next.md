# Next

## 現在のフェーズ

runtime/config同期の残存P1を閉じ、Devices UIなしのDevice Management CoreとGeneric HID観測・Learn・Action変換基盤まで実装した。追加レビューで見つかったAction sourceのACK05依存、relative方向消失、stale descriptor Rebindの3件はソース上修正済み。configはversion 9を維持し、Generic HID mappingの永続schemaとruntime接続は実機で安定identityを確認するまで追加しない。

## 今回完了したゲート

- [x] CLIが保存したMode等をGUIの`configuration` / `persistedConfiguration`へdisk stateからreconcileし、Group往復で古いModeを送り返さない。
- [x] GUIの未保存local差分はbaseline / local / remoteの3-way mergeで保持し、remoteの別fieldを吸収しない。
- [x] config変更通知とGroup切替時のdisk refreshを追加し、Deck / waveformPosition / Profile / Logical Device / Physical Bindingも最新化する。
- [x] CLIはACK05 report処理前にconfig file revisionを確認し、変更時はProfile / Group mappingとbindingを再構築する。
- [x] config内容とrevisionを同じ`config.json.lock`取得中に読むsnapshot APIを追加し、古い内容へ新しいrevisionを対応させる競合窓を閉じる。
- [x] legacy `location:`をpersistent match対象から明示的に除外する。
- [x] session ID単位の`HIDDeviceRegistry`を追加し、接続・切断・binding / ambiguous / Profile / Location hintを表現する。
- [x] `HIDIdentifySession`、serial-onlyのRebind、Physical Bindingだけを消すForgetをCore/APIとして追加する。
- [x] ambiguous serial、serialなし、他Logical Deviceへbinding済みのPhysical DeviceをRebindで自動確定しない。
- [x] Generic HIDのkeyboard / consumer / button / relative / absolute event正規化、source-lock Learn、既存`ActionEvent`への変換をCoreへ追加する。
- [x] IOHID cookieを診断専用にし、永続descriptorはUsage Page / Usage / Report ID / collection pathで表す。同一signatureが複数の場合は永続化不可とする。
- [x] `overcue-probe --all`でsession device ID、VID/PID、Serial、Product、Manufacturer、transport、Usage、Report ID、cookie、relative、duplicate count、press/release/deltaを表示できる。
- [x] `ActionEvent`の正本source identityをgenericな`ActionSourceID`へ移し、ACK05の`sourceKey`は互換accessorへ限定した。
- [x] Generic HID mapping keyへ`press / relativePositive / relativeNegative` activationを含め、encoder相当の正負方向を別Actionへ割り当てられるCore構造にした。
- [x] relative deltaの絶対値を`ActionEvent.activationCount`として保持し、Core境界で回転量を1回へ潰さない。
- [x] RebindはIdentify済みdescriptorのsessionが現在のconnected setへ残っていることを必須にし、切断後のstale descriptorを拒否する。
- [x] 上記3件の回帰用に`OverCUECoreTests`を追加した。
- [x] Devices SwiftUI画面、Learn UI、Koolertron固有処理、Parent Preset / Sceneは追加していない。

## 追加レビュー修正のローカル検証

GitHub connectorから直接修正したため、この新しいHEADについてはmacOSローカル検証前である。親commit `bef4c46`の374 Core checks成功を今回の成功扱いにしない。

- [ ] `aal context build --mode implementation`
- [ ] `swift build`
- [ ] `swift test`
- [ ] `swift run overcue-checks`
- [ ] `./Scripts/verify-macos.sh`
- [ ] `aal doctor`
- [ ] `git diff --check`

## 次に人間が確認すること

- [ ] ACK05 ×2でdefault / non-default Profileを割り当て、non-default操作後もGUI controlがdefault deviceだけへ届くことを確認する。
- [ ] ACK05の切断・再接続、同一／空Serial、ambiguous binding時のdefault Profile fallbackを確認する。
- [ ] `overcue-probe --all`でKoolertron候補機のキー、encoder CW/CCW、encoder pushのUsage / Report / relative deltaを採取する。
- [ ] 同型Generic HID複数台のSerial有無と再接続時descriptor安定性を確認する。
- [ ] 実機データを根拠にGeneric HID persistent mapping schema（必要ならconfig v10）を決める。
- [ ] 実機を見ながらDevices / Identify / Rebind / Forget / Learn UIを設計する。

## 停止理由

非UIで安全に実装できるCore境界は整えた。Generic HID mappingの永続化・実runtime接続には、実機Report、relative delta単位、同一Usage重複時の安定識別情報が必要である。ここから先はKoolertron／複数ACK05実機データまたはUI判断なしでは推測実装になる。

## 保留

- Parent Preset / Scene。
- 標準3Deckリグの完全独立物理構成。
- Deck 4=`33xx`規則の実データ確認。
- GitHub Actionsの復旧。
- Developer ID署名とnotarization。
- Ableton Live / Launchpad Xの統合検討。

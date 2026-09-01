# Next

## 現在のフェーズ

Preset Group / Shortcut Scope version 10を実装した。Group-level `targetDeck` / `rekordboxDeck`、GUI Deck selector、Bridgeのactive Deck stateはcurrent schema/runtimeから削除済み。

## 完了した実装

- [x] `aal context build --mode implementation`で最新Decisionを確認。
- [x] `ActionTarget.rekordboxAction`へsemantic Action IDと選択shortcut commandIdを保持。
- [x] Generic `rekordbox:<commandId>`とInternal Actionを無変換で維持。
- [x] Cue hold / Jump repeat等のsemantic behaviorをscope付きtargetでも維持。
- [x] 1〜24個の`OverCUEPresetGroup`（opaque stable ID、必須name、order、mapping）を導入。
- [x] Preset cycleを存在するPresetのorder順・双方向wrapへ変更。
- [x] GUIの4分割segmentをPreset名menuへ変更し、Deck selectorを削除。
- [x] Runtime Status / Controlへstable Preset IDを追加し、並べ替え・削除時の誤送信を防止。
- [x] GUI選択中Presetをstable IDで維持し、remote reorder後も同じPresetを参照。
- [x] BridgeのProfile mappingを実在Preset数から構築し、固定4 Group依存を撤去。
- [x] v9→v10 migrationで旧GroupのMode、waveformPosition、mapping、EXPORT用途を維持。
- [x] 旧`rekordboxDeck`を標準Actionのscope付きreference変換だけに使用し、v10 encodeから除外。
- [x] v10の3-way mergeをPreset stable ID単位・mapping field/entry単位へ更新。
- [x] DefaultKeyMappingをv10 Preset / scoped shortcut表現へ更新。
- [x] Core checksを397件へ拡張。

## commit前の最終検証

- [x] `swift build`
- [x] `swift test`（3件成功）
- [x] `swift run overcue-checks`（397件成功）
- [x] `./Scripts/verify-macos.sh`
- [x] `aal doctor`（0 failures / 0 warnings）
- [x] `git diff --check`
- [x] `OverCUE` / `overcue-cli`のarm64 + x86_64とad-hoc codesignを確認。
- [x] Universal Binary / ad-hoc codesign結果をhistoryへ記録。

## 次の実機ゲート

- [ ] ACK05 2台以上で同時操作、切断、再接続、異なるLogical Device / Profileを確認。
- [ ] `overcue-probe --all`でKoolertron候補のVID / PID / Serial / Usage / Report ID / press-release / relative deltaを採取。
- [ ] 同型Generic HID複数台のSerial有無と再接続時descriptor安定性を確認。
- [ ] Deck 4 shortcutを含むrekordbox KeyMappings XMLで`33xx`を直接確認。

## UI待ち

- Devices画面の詳細レイアウト、Logical Device命名、Profile assignment、Identify / Rebind / Forget / Learn。
- Parent Preset / Scene。

## 保留

- Generic HID mappingの永続schemaとruntime接続。実機identityの証拠待ち。
- GitHub Actionsの復旧。
- Developer ID署名とnotarization。

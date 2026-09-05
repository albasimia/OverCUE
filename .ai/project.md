# Project Context

## 目的

OverCUEは物理入力をrekordboxのActionへ変換するmacOSアダプター。ACK05はFirst-class、Generic HIDはAdvanced / Best-effort。Freeプランで使えるキーボード／マウス出力を主経路とし、DDJ-SX互換MIDIは補助。標準リグは3Deck、ソフトウェアはPERFORMANCE 4Deckを扱う。

## 現在のフェーズ

branch: `codex/performance-4deck`。Swift PackageのCore / SwiftUI App / CLI bridge / probe / checksで構成する。config v10、Generic HID sidecar v1。Preset・Group Preset・複数device・Shortcuts Unified Learnは実装済みだが、連続LearnとSIDE遅延の実機ゲートは未完了。未解決事項・直近検証は`.ai/next.md`を正本とする。

## 採用済みの決定

### Preset / runtime / editorの所有者

- Presetはstable ID・name・order・Mode・独立waveformPosition・mappingを持つ可変1〜24個。Cycleは実在Presetのorder順にwrapする。
- ShortcutsのPreset / Modeはeditor専用。editor選択からRuntime Controlを送らず、Runtime Statusでeditor選択・Mode・mapping表示を変更しない。
- Group PresetはLogical Device→開始Preset stable IDのruntime baseline。最低1個を維持し、assignmentの存在が参加を表す。Physical ID/sessionは保存しない。
- 起動・runtime再構築・Group Preset切替/assignment変更・device接続・明示再適用でbaselineを適用。Cycle Presetはdeviceごとの一時状態で、通常status/config/editor更新では巻き戻さない。Group Presetからの除外でruntimeを暗黙停止しない。
- Generic HID mappingの保存・表示・削除はLogical Device + editor Preset + descriptor。Learn開始時editor IDを固定し、runtime/Group Preset assignmentを保存先にしない。対象Preset削除時は別Presetへfallbackしない。
- 通常Actionの競合scopeは同じPreset内。Cycle Preset系のみ全Preset横断の既存競合仕様を維持する。全面的な回帰網羅は未完了。
- Unified Learnは単一session owner、ACK05 / Generic HID backendは独立。先に有効入力をclaimしたsourceだけが保存し、別device入力を混在させない。source切断はcancel。現行の終了フラグは使用中であり、未使用コードとみなして削除しない。
- Shortcutsは唯一のmapping編集UI（既存2カラム）。Devicesはbinding/device管理、Group Presetはorchestration、Settingsは設定。Scene / Parent Presetを先回り実装しない。

### Action / config

- targetDeck / rekordboxDeckをPresetへ再導入しない。Deck scopeは選択されたaction/shortcut自身が保持する。semantic commandId解決はRekordboxActionAdapterが正本。Generic `rekordbox:<id>`はそのまま使う。
- Cue hold / Jump repeat / chord / dial / waveform操作を維持する。ActionSourceIDはadapter非依存。Generic relativeは正負を分けdelta量をactivationCountへ保持し、必ずAction Layer経由で出力する。
- config v1〜9 migrationとbackupを維持。v9の旧Deck意味をscope付きActionへ移し、Mode・座標・割当を失わない。既存v10のGroup Preset欠落はDefaultを補完する。
- config.json更新は共通FileStoreのlock付きlatest read-modify-write。GUIはbaseline/local/remoteの3-way merge（dictionary entry、Preset、Logical Device、assignment単位）。古いsnapshot保存やmigrationでremote更新を消さない。
- CLIは入力/config revision変更時、control適用前に最新binding/Profile/mappingを解決。GUIも最新diskとlocal差分をreconcileし、古いModeを後から送り返さない。
- status/controlはdevice/session/Logical Device/Profile scopeを保持。non-default Profileはdefault UI targetを奪わず、切断時targetを解放しglobal controlへfallbackしない。
- config読込cacheはrevision確認付きread-onlyで、編集baselineや書込lockの代替ではない。HID metadataはinterface match時に全件preloadし、入力はcookie lookupのみ。曖昧性判定を維持し、失敗は入力外でretry。disconnect/restartで破棄（既存main runloop所有は維持）。

### Device / HID

- Physical Device→Physical Binding→Logical Device→Profile→Action→rekordboxの境界を維持。Device Registryは接続session、永続bindingはconfigが正本。
- Identifyは最初の候補sourceへ固定。Rebindは接続中かつ一意なidentityのみ受理しbindingだけ交換する。ForgetはLogical Device/Profileを残す。変更中に旧Profileのlive出力を残さない。
- Generic identityはVID+PID+Serial。同一Serialの別attachmentはambiguousとして拒否。1台の複数interface束ねにlocationをhintとして使うが、Genericのpersistent identityへ昇格しない。cookieも永続化しない。
- ACK05 BLEは実機確認済みPhysicalDeviceUniqueIDをPairing Identityに使用（再ペアリングで変化）。ACK05 USBは例外的にlocationをUSB Slot Identityとして使用し、個体IDとは呼ばない。他Generic HIDへ一般化しない。
- Generic descriptorはUsage Page / Usage / Report ID / collection path。同一signature重複は実機根拠なしに確定しない。未知の製品・encoder形式を推測しない。
- Generic runtimeは最初からshared IOHID。登録deviceのraw evidenceと一致したnative eventだけ抑止し、未登録deviceはfail-open。root/helper前提やvendor固有hard-codeへ戻さない。
- Generic runtimeは各startでrunloopを再scheduleし、current-device snapshotをmatchと共通の登録/preload経路へ渡す。Close後のmatch再配送を前提にせず、stopでlive stateを全破棄する。
- ACK05 CLI / Generic runtimeは独立backend。一方のfailureで他方を止めない。CLIはGUI parent消失で終了。Identify/Rebindの一時停止でcontroller input設定をOFF保存しない。controller input OFF時は両runtime/抑止を停止する。

## 制約

- macOS 13+ / Swift 6+。Input MonitoringとAccessibilityが必要。XPPenPenTabletとの競合に注意。rekordbox最前面時だけ出力。
- build/check成功と実機確認済みを区別する。Deck1〜3の30xx/31xx/32xxはXML確認済みだがDeck4の33xxは実データ未確認。
- ローカル検証をSSOTとする：`swift build`、`swift test`、`swift run overcue-checks`、`./Scripts/verify-macos.sh`、`aal doctor`、`git diff --check`。
- dist/OverCUE.appのapp/helper両方arm64+x86_64、ad-hoc codesign deep/strictを維持する。Actionsだけを検証根拠にしない。
- 現行仕様を変える大規模リファクタや抑止待機変更は、実測・回帰なしに行わない。`.aal/logos/`は直接編集しない。
- Windows実装はdevelop側。bin/obj/artifactsと_siteは生成物としてignore済み。無関係なソース・ユーザー設定を変更しない。Ableton/Launchpad探索を製品へ無断混入しない。

## 参照文書

必要な対象だけ追加読込する。完了履歴や実機証拠を本ファイルへ再展開しない。

- 実装仕様：`specs/current-spec.md`
- 遅延・棚卸し・次回測定：`docs/generic-hid-latency-audit.md`
- ownership：Decision `20260904T014017-89c027`
- cache境界：Decision `20260904T084205-a76908`
- Deck廃止 / v10：Decision `20260901T201000-91c4e7`（旧`20260830T200000-28631d`を置換）
- Group Preset：Decision `20260902T003000-group-preset`
- ACK05 BLE / USB：Decision `20260901T234500-6f42c1` / `20260902T215700-ack05-usb-slot-identity`
- Generic登録 / shared backend：Decision `20260902T231600-generic-hid-register` / `20260903T025020-generic-hid-shared-runtimeとinput-backend分離を採用する`
- 整理前の完了項目・実機証拠・詳細UIゲートはGit `777f9be:.ai/project.md` と `777f9be:.ai/next.md`へ保存済み（`git show <commit>:<path>`）。当時の記録であり現在の仕様を上書きしない。

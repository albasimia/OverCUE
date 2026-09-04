# Next

## 現在地

2026-09-04。ownership分離は`ffd5dc0`、未使用Learn monitor削除とhot-path cache化は`19a7fe1`でpush済み。最新コードの自動検証：35 unit tests / 405 Core checks、debug/release Universal Binary、ad-hoc codesign deep/strict成功。AAL doctor 0 failures / 0 warnings。実機で体感改善を確認したわけではない。

AALはglobal CLI / localとも`d807f62`へ更新済み。projectは現在仕様、nextは未完了作業に限定し、詳細記録はhistory/decision/specを必要時だけ読む。

## 最優先：実機入力待ち

1. Deck3-sideのノブ右/左/押し込みがLearnできない。登録・Consumer要素の列挙は確認したが操作ログ未採取。Keyboard割当は保存済み。raw入力→normalize→capture→保存のどこで止まるか観測し、推測修正しない。
2. SIDEだけキー/ノブに体感遅延（Learnとは別件）。ACK05と同じActionで比較し、初回/warm、GUI負荷、受信/出力時刻を測る。機械的アクチュエーションも押下の候補であり、回転遅延とは分ける。`docs/generic-hid-latency-audit.md`参照。
3. 3回以上連続Learn、ACK05/Generic片側失敗、editor Preset往復、Group Presetと異なるeditorへの保存・表示・削除を確認。終了管理にはisCaptureMode/handler/finishingCaptureが残る。owner整理完了やDeck3修正済みとは記録しない。

ユーザーは現在実機操作不可。常時monitorや自動再起動は行わない。実機待ち中はコード監査・synthetic検証の範囲を明示する。

## 実機確認ゲート

- ACK05 BLE/USB：Devices登録・別Logical Device識別、電源/再接続、BLE再ペアリング→Rebind、USB同slot復帰/別slot不一致、3interface統合、Identify競合なし。
- Preset管理：5個以上の追加・order巡回・rename/deleteとstable ID維持、Group Preset複数deviceへの適用、Cycle一時state維持、除外device不変、status交互受信でもeditor不変。
- Generic：複数SIDEのbinding・再接続・同Preset別device割当・native抑止・全7入力のAction動作。過去の一部操作成功を現行全入力の確認済みに拡張しない。
- 詳細な未完了チェックリストと当時の実機観測は`git show 777f9be:.ai/next.md`。現在のbindingはconfigをread-only確認し、古いSerial→Deck対応表を固定値として使わない。

## 並行実験：Koolertron LED

- branch `codex/koolertron-led-probe`で、本体runtimeから隔離してLED protocol探索を行う。
- read-only inspectionで、対象は `SDINNOVATION / SIDE-KEYBOARD`、VID `0x0816`、PID `0x246E`、Vendor Defined interface `0xFF00 / 0x0002`、Report ID 0、64-byte Input/Outputであることを実機確認済み。3個体にSerialあり。
- SDTech Option 1.0.3の静的解析で、照明設定取得 `06 0A`、全体照明設定 `06 0B`、単一キーRGB `06 14`、RGB配列書込 `06 12`、RGB配列取得 `06 13`、mode前段 `06 16` のpacket builderを確認。実firmware上の発光・永続化挙動は未確認。
- 次のlive gateは専用target `overcue-led-probe`のみを使う。`--serial`必須、VID/PID/Usage/Product固定、64-byte Output capability必須で、`06 0A` + zero paddingを1回だけ送信しInput responseを保存する。自動再送・任意writeは実装しない。
- `06 0A`成功はcommand互換性の確認に限定する。RGB setterをruntime同期へ使う前に、RAM/flash/profile保持、key index、送信間隔、response/error semanticsを別途確認する。
- driver / MIDI OUT / state manager / GUI/configへはまだ接続しない。
- 方針の正本はDecision `20260904T120000-koolertron-lighting-query-gate`。初期隔離方針は`20260904T113800-koolertron-led-probe-isolated`。

## 追加実装は別段階

- Generic入力のmain-thread依存と初回XML同期読込は残る。background移動はteardown/state ownership、preloadはsnapshot/更新検知を設計してから。8ms抑止待機を実測なしに短縮しない。
- ownership仕様の回帰網羅：editor操作でcontrolなし、status fan-out隔離、Preset別通常mappingとCycle全Preset例外、ACK05起動時baseline、Learn終了一度だけ。現行Core成功だけでUI lifecycleまで証明したとしない。
- Deck4 `33xx`のXML/実機確認、SerialなしGenericの永続binding、最初PresetのCycle割当分離と削除制約、Actions復旧、Developer ID/notarizationは保留。Scene / Parent Preset UIは対象外。

## 次の完了判定

コード変更時はproject記載の全macOS検証とAAL更新を行う。実機確認済みと自動テストを区別し、設定やdevice identityを根拠なしに変更しない。Koolertron LED branchではone-shot lighting queryまでをprotocol compatibility gateとし、RGB runtime実装済みとは扱わない。

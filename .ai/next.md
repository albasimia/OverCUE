# Next

## 現在地

2026-09-05。ユーザーの実機ログでConsumer初回callback→inputに約750〜764ms停止を確認。usage初回ごとの全element走査をinterface match時の一括catalogへ移した。自動検証：42 unit tests / 412 Core checks、debug/release Universal Binary、ad-hoc codesign deep/strict成功。AAL doctor 0 failures / 0 warnings。修正後の実機改善は未確認。

AALはglobal CLI / localとも`d807f62`へ更新済み。projectは現在仕様、nextは未完了作業に限定し、詳細記録はhistory/decision/specを必要時だけ読む。

## 最優先：実機入力待ち

1. `OVERCUE_GENERIC_HID_DIAGNOSTICS=1`でcatalog ready後、Deck1→2→3を順にRight×3 / Left×3 / Click×3。初回callback→inputの約750ms停止・後続burstが消え、routing/mapping結果が維持されるか確認。Deck2 Right/Clickのmapping missは未割当による期待値。今回Learn・mapping修正へ進まない。
2. 3台SIDEのLogical Device→Deck1/2/3 Preset→30xx/31xx/32xx分離とrekordboxショートカット動作はユーザー実機確認済み。修正後の再接続・初回/warm比較は未確認。match時のmain-thread preloadによる起動/hotplug停止は残り得る。`docs/generic-hid-latency-audit.md`参照。Deck3 Learn不調は別件として未解決。
3. 3回以上連続Learn、ACK05/Generic片側失敗、editor Preset往復、Group Presetと異なるeditorへの保存・表示・削除を確認。終了管理にはisCaptureMode/handler/finishingCaptureが残る。owner整理完了やDeck3修正済みとは記録しない。

常時monitorや自動再起動は行わない。今回修正のcommit/push後は上記実機結果を待つ。ユーザー提供の修正前ログと、自動検証・修正後実機確認を区別する。

## 実機確認ゲート

- ACK05 BLE/USB：Devices登録・別Logical Device識別、電源/再接続、BLE再ペアリング→Rebind、USB同slot復帰/別slot不一致、3interface統合、Identify競合なし。
- Preset管理：5個以上の追加・order巡回・rename/deleteとstable ID維持、Group Preset複数deviceへの適用、Cycle一時state維持、除外device不変、status交互受信でもeditor不変。
- Generic：複数SIDEのbinding・再接続・同Preset別device割当・native抑止・全7入力のAction動作。過去の一部操作成功を現行全入力の確認済みに拡張しない。
- 詳細な未完了チェックリストと当時の実機観測は`git show 777f9be:.ai/next.md`。現在のbindingはconfigをread-only確認し、古いSerial→Deck対応表を固定値として使わない。

## 追加実装は別段階

- Generic入力のmain-thread依存と初回XML同期読込は残る。background移動はteardown/state ownership、preloadはsnapshot/更新検知を設計してから。8ms抑止待機を実測なしに短縮しない。
- ownership仕様の回帰網羅：editor操作でcontrolなし、status fan-out隔離、Preset別通常mappingとCycle全Preset例外、ACK05起動時baseline、Learn終了一度だけ。現行Core成功だけでUI lifecycleまで証明したとしない。
- Deck4 `33xx`のXML/実機確認、SerialなしGenericの永続binding、最初PresetのCycle割当分離と削除制約、Actions復旧、Developer ID/notarizationは保留。Scene / Parent Preset UIは対象外。

## 次の完了判定

コード変更時はproject記載の全macOS検証とAAL更新を行う。実機確認済みと自動テストを区別し、設定やdevice identityを根拠なしに変更しない。metadata失敗はmatch/config reload/restartで再試行し、入力内走査へ戻さない。

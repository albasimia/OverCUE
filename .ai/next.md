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
- 2026-09-04、専用`overcue-led-probe`でSerial `592B14678182`へ`06 0A`を1回だけ送信。SetReport成功、2.659 msでReport ID 0 / 64-byte応答`AA 0A 0B ...`を取得。詳細・raw logは`docs/koolertron-light-query-result.md`。この許可分は実行済みであり、再送しない。
- 静的getterに従う解釈はmode=4 / brightness=4 / speed=2 / direction=0 / HSV=FF,FF,FF。offset 12は07で、setterのzero固定と異なる。field解釈は高確度推定、目視・status意味・永続化は未確認。専用CLIのReport長判定をDescriptor由来のexact 64へ修正し、送信結果・遅延を記録。35 tests / 405 checks / Universal Binary・署名検証成功。
- 2026-09-04、Serial `592B14678182`へ固定RGB getter `06 13 3A` + 61 zerosを1回だけ送信。64-byte `AA 13 3A ...`応答、2.709 ms、key0〜3は静的getter対応で`#00FF00`。key0のrollback payloadを`docs/koolertron-rgb-query-result.md`へ保存（未送信）。この許可分は実行済みで再送しない。第2chunkは未取得。mode移行/復帰の応答依存packetとsetter成功条件は未確定。
- 2026-09-04 14:11 JST、Serial `592B14678182`の許可済み1往復live testを実施。pre getters完全一致→06 16/0BでCustom→key0 magenta→5秒→green→06 16/0Bでmode4→post getters。全10送信成功、pre/post照明・RGB chunkは64-byte完全一致。`docs/koolertron-live-roundtrip-result.md`参照。許可分は完了、再実行しない。物理発光は現地目視結果待ち、RAM/flashは未確定。
- 2026-09-04 16:00 JST、明示承認後に3台を一度消灯しCustom mode5でkey0だけ点灯へ設定。592B14678182=青、2D3B07678182=緑、3F8701678182=赤。他18 RGB entriesは0。各台57-byte RGB/照明configの読み戻し一致。元config/RGB全量をdocs/evidence/koolertron-three-single-lights-baseline.jsonへ保存。docs/koolertron-three-single-lights.md参照。現在は潮汐mode4ではなくこの1キー点灯設定。実際の見え方と電源断保持は未確認。
- 2026-09-04 user observation: LED colors retained after USB unplug/reconnect at home. Nonvolatile device storage is strongly suggested; medium, commit timing and 06 14-only persistence remain unknown. Per-Serial coverage and raw post-reconnect values were not provided. See docs/koolertron-three-single-lights.md. No HID sends during recording.
- 2026-09-04 17:46 JST: read 06 0A / 06 13 chunk0 once per known Serial after reported USB reconnect. All3 mode5; key0 blue/green/red, remaining captured RGB zero. Both64-byte responses match setup logs on every device. See docs/koolertron-reconnect-read-result.md. Six getter sends only, no setters/retry. Storage medium/commit remain unknown.
- 2026-09-04 17:50 JST: user-authorized finite key0->1->2->3 walk on all3 devices,5 seconds each, retained blue/green/red, restored key0. Every RGB chunk verified. Physical index mapping awaits user observation. See docs/koolertron-key-index-walk.md. No mode change or retry; do not repeat without request.
- 2026-09-05 18:31 JST: Serial `592B14678182`だけでkey3赤・他3key黒のCustom目視成功後、公式response-derived mode2を試験。全4keyが多色呼吸し、黒/per-key RGBを視覚上無視。速度は実用的だがSW4単独・Deck色維持のPlay/Pause表示には不採用。元mode1・key0青/他黒へrollbackし、06 0A/06 13の64-byte範囲はbaseline完全一致。retry/06 12/他Serialなし。`docs/evidence/koolertron-breathing-phase-a-20260905.md`参照。
- 2026-09-05 19:23 JST: ユーザー承認後、同じ1台でPLAY=mode5/key3赤、PAUSE=mode0を有限1往復。目視でSW4赤のみ→全消灯→RGB再書込なしでSW4赤のみ復帰。最終06 0A/06 13もmode5・key3赤/他黒。binary表示は成立するが、06 16/0Bの揮発性/write wearはUnknown。runtime hot pathへ同期writeせず、重複抑止・直列化・永続性policy確定前に統合しない。現在deviceはPLAY状態。`docs/evidence/koolertron-binary-play-pause-20260905.md`参照。
- 2026-09-05 19:50 JST: 同じ1台で公式mode/fieldを追加検証。mode3は押下キーを発光するがper-key RGBではなくglobal paletteを使用し、offset11=1 + HSV赤で全キーの押下色を赤に固定できた。mode2も同設定で全キーが赤のまま消灯まで呼吸。mode1〜5の06 16 configを比較し、effect対象key/mask fieldは公式UI/call siteに見つからず、offset12もmaskではない。最終mode5へ復帰、readback成功。開始時点ですでにkey2 RGBが`7FFF08`へ変わっており、本試験はRGB setterを送らず保持した。runtime採用は未決定。`docs/evidence/koolertron-official-mode-fields-20260905.md`参照。
- 2026-09-05 19:58 JST: Serial `592B14678182`をmode2・単色赤にし、USBを約10秒抜いて公式app/OverCUE操作なしで再接続。直後から全key赤呼吸を目視、read-only 06 0Aは電源断前config `01 00 02 04 02 00 01 FF 00 FF FF`とbyte一致、06 13 chunkも一致。mode/global color parameterがUSB電源断を越えてdevice側保持される強い証拠。媒体/耐久はUnknownのため、Play/Pauseごとの06 0B高頻度writeをruntime採用しない。現在deviceはmode2赤呼吸。詳細は同evidence。
- 2026-09-05 20:06 JST: SDTech Option 1.0.3に同梱された旧/現行2世代の全JS call site、live HID descriptor、v101/v105 firmware packageをread-only監査。公式clientのlive-lighting名メソッドはstubで、既知の永続設定系WebHID Output以外のpreview/WebUSB/WebSerial/Feature経路は存在しない。firmwareには未文書commandがあり得るが、接続個体image/MCU ISA/dispatchを証明できず推測送信は禁止。Output送信0、deviceはmode2赤呼吸のまま。`docs/evidence/koolertron-ram-only-path-audit-20260905.md`参照。
- `06 0A`成功はcommand互換性の確認に限定する。RGB setterをruntime同期へ使う前に、RAM/flash/profile保持、key index、送信間隔、response/error semanticsを別途確認する。
- driver / MIDI OUT / state manager / GUI/configへはまだ接続しない。
- 方針の正本はDecision `20260904T120000-koolertron-lighting-query-gate`。初期隔離方針は`20260904T113800-koolertron-led-probe-isolated`。

## 追加実装は別段階

- Generic入力のmain-thread依存と初回XML同期読込は残る。background移動はteardown/state ownership、preloadはsnapshot/更新検知を設計してから。8ms抑止待機を実測なしに短縮しない。
- ownership仕様の回帰網羅：editor操作でcontrolなし、status fan-out隔離、Preset別通常mappingとCycle全Preset例外、ACK05起動時baseline、Learn終了一度だけ。現行Core成功だけでUI lifecycleまで証明したとしない。
- Deck4 `33xx`のXML/実機確認、SerialなしGenericの永続binding、最初PresetのCycle割当分離と削除制約、Actions復旧、Developer ID/notarizationは保留。Scene / Parent Preset UIは対象外。

## 次の完了判定

コード変更時はproject記載の全macOS検証とAAL更新を行う。実機確認済みと自動テストを区別し、設定やdevice identityを根拠なしに変更しない。Koolertron LED branchではone-shot lighting queryまでをprotocol compatibility gateとし、RGB runtime実装済みとは扱わない。

# Project Context

## 目的

OverCUEは、任意の物理入力インターフェースとrekordboxの間をつなぐソフトウェアアダプターである。XPPen ACK05を標準・First-classデバイスとして扱い、macOS版rekordboxのCUE仕込み、波形移動、Deck操作を一貫したAction体系へ変換する。rekordbox Freeプランでも利用できるキーボード・マウス操作を主経路としつつ、将来的なGeneric HIDや他入力アダプターを同じAction Layerへ接続できる構造を維持する。

## 現在のフェーズ

PERFORMANCE Deck 1〜4対応とmacOSローカルビルドは成立している。runtime/config同期の残存P1を閉じ、Devices UIなしのDevice Registry、Identify、Rebind、Forget、およびGeneric HID観測・Learn・Action変換Coreまで実装した。configはversion 9を維持し、Generic HID mappingの永続化と実runtime接続は実機identityの証拠待ちである。次は複数ACK05とKoolertron候補機で境界を確認する。

## 現在地

- Swift Package ManagerでCore、SwiftUIアプリ、CLI bridge、probe、core checksを管理している。
- ACK05のHID入力、キー／任意数コード、Cue hold、Jump長押しリピート、ダイヤル操作をAction Layerへ変換する。
- 4つのGroupがあり、各Groupは`rekordboxMode`、`rekordboxDeck`、`waveformPosition`、キー／コード／ダイヤル割り当てを独立して保持する。
- PERFORMANCEではDeck 1〜4を選択できる。EXPORTではDeck指定を保持するが操作解決には使わない。
- rekordboxの選択中KeyMappings XMLを読み、commandIdから実際のキーボードショートカットを解決する。
- configはversion 9。version 1〜8からのmigrationとバックアップを持つ。旧`deviceProfiles`はLogical Device + legacy Physical Bindingへ移行する。
- `Scripts/verify-macos.sh`でdebug build、core checks、Universal Binary app生成、ad-hoc codesign検証を一括実行できる。
- 2026-08-30時点の4Deck対応はcommit `28631d4de001331d8aceaa96bf57f778cd9c2ac6`、branch `codex/performance-4deck`へpush済み。
- ACK05 1台のProfile切り替えによるDeck 1〜3操作は、実際のDJ運用で成立済み。
- DJM-750 original + macOS Tahoe 26.6.2 + DJM-750 driver 4.0.1 + rekordbox PERFORMANCE / External Mixerで、4ch独立出力を実機確認済み。
- 標準物理リグは3Deckを基本とし、1DeckあたりACK05 + 小型Generic HID（4キー + endless encoder想定）を組み合わせる。ソフトウェア上は4Deckを維持する。
- Generic HIDの候補実機としてKoolertron系小型マクロパッドを検証するが、OverCUEのUI・データモデルを特定製品へ依存させない。
- CLI bridgeのlive session identityはIOHID接続インスタンス由来transport identifierを使い、Serial由来persistent identityと分離する。
- 同時接続deviceが同じVID / PID / Serialを名乗る場合はbindingをambiguousとしてdefault Profileへ戻し、接続トポロジ変更を既存controllerへ即時通知する。
- Runtime Status / Controlはsession device ID、Logical Device ID、Profile名とdevice / global scopeを保持する。GUIはstatus受信だけで設定を書き戻さない。
- default Profile用GUIのruntime targetはdefault Profileのdeviceだけで更新する。non-default Profileのstatusはdefault UIのcontrol targetを奪わない。
- CLIは通常のACK05キー／ダイヤル入力時にもdevice-scoped runtime statusをpublishし、default Profile UIのcontrol targetを実際に操作したdeviceへ追従させる。
- default Profile device切断時はGUI targetを解放し、再接続statusで新しいsession targetへ更新する。live default targetがない場合、GUIはglobal controlへフォールバックしない。
- GUI / CLIによる`config.json`更新は共通`OverCUEConfigurationFileStore`のlock付きread-modify-writeを使う。GUIは最後に読み込んだbaseline、GUIローカル変更、最新disk stateの3-way mergeを行い、CLI由来の無関係な変更を古いin-memory configで上書きしない。
- version 1〜8 migrationもlock取得後の最新dataを再判定し、別processが既にcurrentへ移行・更新したstateを古いmigration snapshotで上書きしない。
- CLIはGUI runtime controlを処理する直前に最新configをreloadし、Group / Mode / Deck / Action mappingを最新値から再解決する。CLI自身のMode / waveform保存も最新disk stateへ局所更新する。
- version 9 migrationのlegacy `location:`値は`lastKnownLocationID` hintだけへ移し、persistent match対象へ残さない。
- ACK05 Learn / Captureは最初のsource physical deviceへ固定し、別ACK05の入力を混在させない。source切断時はcaptureをキャンセルする。
- GUIはruntime/config変更時にdiskの最新baselineと未保存local差分をreconcileし、CLI保存済みModeをGroup往復で古い値へ戻さない。
- CLIはACK05入力前にconfig revisionを確認し、変更時はbinding、Profile、Group mappingを再構築する。config内容とrevisionは同じlock内のsnapshotとして読む。
- `HIDDeviceRegistry`は接続中Physical Deviceをsession identityで管理し、persistent binding、ambiguous状態、Profile、Location hintを派生する。
- Identifyは最初の入力sourceへ固定する。Rebindは一意なSerial identityだけを受理し、ForgetはLogical Device / Profileを残してPhysical Bindingだけを削除する。
- Generic HIDはUsage / Report / collection pathから入力を表現し、cookieはruntime診断専用とする。重複signatureは実機根拠なしに永続化しない。
- Generic HID eventは既存Action Layerへ変換し、rekordbox commandIdやkeyboard送信をGeneric層へ持ち込まない。
- `overcue-probe --all`はdevice metadata、Usage / Report、press/release、relative delta、永続化可否をdevice session別に観測できる。

## 制約

- 対象はmacOS 13以降、Swift 6以降、Apple Silicon／IntelのUniversal Binary。
- HID取得には入力監視、キーボード／マウス送信にはアクセシビリティ権限が必要。
- XPPenPenTabletがACK05入力を消費する場合がある。
- rekordboxが最前面のときだけキーボード／マウスイベントを送る。
- GitHub Actionsを唯一の検証経路にしない。macOSローカル検証を正本とする。
- 現在選択中の`Performance 1 (Preset)`ではDeck 1=`30xx`、Deck 2=`31xx`、Deck 3=`32xx`を実データで確認したが、Deck 4の割り当て行は存在しない。Deck 4=`33xx`は未確認事項として扱う。
- Core checksの成功だけで実機確認済みとは扱わない。
- Generic HIDはAdvanced / Best-effortとし、任意のvendor-specific HIDを無条件にサポートすると約束しない。
- Generic HIDの実際のUsage / Report / encoder形式とpersistent descriptorは実機確認前に確定しない。

## 採用済みの決定

- 新しいDeck modeは作らず、既存の4 Groupへ対象Deckを持たせる。
- Deck依存操作は`ActionID + RekordboxDeck`からcommandIdへ解決し、Deck別Action定義を複製しない。
- commandIdの操作suffixは`RekordboxActionAdapter`をSingle Source of Truthとする。
- ユーザーが明示したGeneric `rekordbox:<commandId>`はDeck変換しない。
- 既存configの意味を優先し、旧既定Group 2だけをDeck 2 + 標準Actionへmigrationする。Group 3のEXPORT用途は変更しない。
- 波形ドラッグ座標はProfile共通ではなくGroupごとに保存・復元する。
- Freeプラン向けの主運用はマウス／キーボード出力とし、DDJ-SX互換MIDIは補助経路として残す。
- release appは`dist/OverCUE.app`へ生成し、`OverCUE`と`overcue-cli`の両方をarm64 + x86_64にする。
- ACK05はOfficial / First-class device、Generic HIDはAdvanced / Best-effortとして扱う。
- Physical DeviceとLogical Deviceを分離し、Profileや将来のParent PresetはLogical Deviceを参照する。
- Generic HID入力は可能な限りIOHIDのdevice sourceを保持した状態で扱い、同じキーコードを送る同型デバイス同士を区別できるようにする。
- 未登録Generic HIDの検出は受動的に行い、勝手に登録・画面遷移しない。登録はDevicesからAdd Generic Device → Identify/Learnで明示的に行う。
- 物理デバイス識別は固有Serialを最優先し、USB topology / locationは補助ヒントに留める。曖昧な場合はユーザーに対象デバイスを操作してもらいIdentify / Rebindする。
- runtime statusは「現在の画面の編集対象」と「他Profileの演奏状態」を混同しない。default Profile UIはnon-default Profileのstatusでcontrol targetを書き換えない。
- `config.json`は単一ファイルを正本とし、複数processがそれぞれ古い全体snapshotを後勝ち保存しない。永続更新はlock付き最新read-modify-writeまたはbaseline差分のmergeとして扱う。
- Device Registryは接続sessionのruntime状態だけを管理し、永続bindingの正本はconfigのPhysical Binding / Logical Deviceとする。
- Identifyは最初に操作された候補sessionを返し、RebindはPhysical Bindingだけを交換する。LocationIDや曖昧なSerialを自動確定に使わない。
- Generic HID descriptorはUsage Page / Usage / Report ID / collection pathを候補とし、IOHIDElement cookieをpersistent identityにしない。同一signatureが複数なら永続化を保留する。
- Generic HIDは必ず既存Action Layerを通し、Generic層からrekordbox commandId解決やkeyboard outputを直接行わない。
- 標準物理構成は3Deckとし、4Deckはソフトウェア能力とオプション拡張として残す。

## 変更してよい範囲

- 現行Action Layer、Group構造、migration方針に沿う局所的な実装・テスト・ドキュメント更新。
- 複数ACK05を物理個体ごとに分離する入力状態管理。
- config永続化の競合防止、process間runtime scope、Logical Device bindingの安全性改善。
- Generic HIDのdevice-aware入力、Logical Device binding、Identify / Rebind、Learn。Devices UIはユーザーの明示があるまで対象外。
- ローカル検証の再現性、エラー表示、未割り当て時の診断改善。
- 既存挙動を保持するための可逆なCore checks追加。

## 変更してはいけない範囲

- 明示なしにGroup 3の既定EXPORT用途や既存ユーザー設定の意味を変えない。
- Generic `rekordbox:<commandId>`を標準Action扱いして勝手にDeck変換しない。
- Generic HID対応をKoolertron固有モデルとして設計しない。
- 同型デバイスをVID/PIDだけで恒久的に個体識別したことにしない。
- Serialが存在するという理由だけで、同時接続中の同一Serial deviceを同一live sessionまたは同一Logical Deviceとして無条件に扱わない。
- USB topology / locationを永続的なLogical Device IDとして扱わない。
- legacy `location:`値をpersistent Physical Bindingとして復活させない。
- Runtime Status / Controlのsource deviceを失ったまま、別controllerや`defaultProfile`へ状態を伝播させない。
- non-default Profileのruntime statusでdefault Profile用GUIのcontrol targetを置き換えない。
- GUI / CLIが古い`OverCUEConfiguration`全体をそのまま後勝ち保存し、他processの変更を消さない。
- Learn / Captureで複数physical deviceの入力を1つのコードへ混在させない。
- 未登録HIDの接続を理由に設定画面へ自動遷移しない。
- 実データや実機で確認できていない項目を成功済みと記録しない。
- `.aal/logos/`を直接編集しない。
- 未追跡の`Windows/`、`_site/`をOverCUE macOS実装の一部として勝手に削除・追加しない。
- Ableton Live / Launchpad Xを使う演奏体系の検討を、明示なしにOverCUE製品機能へ取り込まない。現時点ではexplorationとして扱う。

## 未決事項

- 複数ACK05実機でのSerial有無、IOHID identity、同時入力・切断・再接続の確認。
- 同型deviceが同一Serialまたは空Serialを返す場合の再binding UX。
- Koolertron系Generic HIDのキー、encoder CW/CCW、encoder pushがmacOS IOHID上でどのUsage / Reportとして見えるか。
- 同型Generic HIDが固有Serialを持たない場合のbinding永続化と再接続UX。
- Devices画面、Logical Device命名、Profile assignment、Rebind / Forgetの最終UI。
- Parent Preset / Sceneの名称と実装時期。
- Deck 4の実際のKeyMapping commandIdを、Deck 4ショートカットが保存されたrekordbox XMLまたは実機動作で直接確認する。
- GitHub Actionsを復旧する場合、独自手順を重複させず`Scripts/verify-macos.sh`を呼ぶ構造にする。

## 参照文書

- `README.md`
- `specs/current-spec.md`
- `Sources/OverCUECore/RekordboxActionAdapter.swift`
- `Sources/OverCUECore/OverCUEConfiguration.swift`
- `Sources/OverCUECore/OverCUEConfigurationPersistence.swift`
- `Sources/OverCUECore/HIDDeviceBinding.swift`
- `Sources/OverCUECore/Resources/DefaultKeyMapping.json`
- `Sources/OverCUEChecks/main.swift`
- `Scripts/verify-macos.sh`
- `.ai/decisions/20260830T200000-28631d.md`
- `.ai/decisions/20260901T110700-c8f4b1.md`
- `.ai/decisions/20260901T110701-e31a76.md`
- `.ai/decisions/20260901T125000-8f0c2a.md`
- `.ai/history/20260901T115131-b701a4.md`
- `.ai/history/20260901T120837-f34729.md`
- `.ai/history/20260901T125000-8f0c2a.md`

## 有効なモード

- implementation
- review
- reporting
- exploration
- conversation

## 次の行動

ACK05 ×2でruntime/binding境界を確認し、`overcue-probe --all`でGeneric HID実機Reportとidentityを採取する。その証拠を基にpersistent mapping schemaとDevices UIを決める。

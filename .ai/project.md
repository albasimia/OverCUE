# Project Context

## 目的

OverCUEは、任意の物理入力インターフェースとrekordboxの間をつなぐソフトウェアアダプターである。XPPen ACK05を標準・First-classデバイスとして扱い、macOS版rekordboxのCUE仕込み、波形移動、Deck操作を一貫したAction体系へ変換する。rekordbox Freeプランでも利用できるキーボード・マウス操作を主経路としつつ、Generic HIDや他入力アダプターを同じAction Layerへ接続できる構造を維持する。

## 現在のフェーズ

PERFORMANCE Deck 1〜4対応、複数Physical Deviceのruntime分離、Device Management Core、Generic HID観測・Learn・Action変換Coreに加え、Preset / shortcut scope schema、Group Presetまで実装済み。現行configはversion 10である。

2026-09-01のUI/ユースケース再検討に基づき、Group単位の`rekordboxDeck` / GUIの「対象Deck」を廃止した。対象scopeは選択されたrekordbox action/shortcut自身へ保持し、別のtargetDeck設定を持たせない。既存の4 Groupは、名前と安定IDを持つ可変Presetへversion 10 migrationで置き換えた。

2026-09-02のGroup Preset実装により、複数Logical Deviceの開始構成はGroup Presetとして保存する。Group PresetはLogical Deviceごとに参照Preset stable IDを持ち、Physical Device/session identityは保存しない。Group Preset適用後のCycle Presetは各デバイスの一時runtime stateとして維持する。

## 現在地

- Swift Package ManagerでCore、SwiftUIアプリ、CLI bridge、probe、core checksを管理している。
- ACK05のHID入力、キー／任意数コード、Cue hold、Jump長押しリピート、ダイヤル操作をAction Layerへ変換する。
- 現行実装は1〜24個のPresetで、各Presetがstable ID、name、order、`rekordboxMode`、`waveformPosition`、キー／コード／ダイヤル割り当てを保持する。
- Group Presetはstable ID、name、order、Logical Device→Preset stable ID assignmentを保持する。Logical Device IDがassignmentに存在することをGroup Presetへの参加として扱う。
- rekordboxの選択中KeyMappings XMLを読み、commandIdから実際のキーボードショートカットを解決する。
- rekordboxショートカット一覧は対象scopeごとに分類されており、ユーザーがDeck別項目を選択した時点で対象scopeは確定している。別途Deck selectorを要求しない。
- configはversion 10。version 1〜9からのmigrationとバックアップを持つ。旧`deviceProfiles`はLogical Device + legacy Physical Bindingへ移行し、v9 Groupはnamed Presetへ移行する。
- 既存version 10 configにGroup Presetが無い場合はDefault Group Presetを補完する。version 9以前からのmigration終端でも既存Logical Deviceを各Profileの先頭Presetへ割り当てる。
- `Scripts/verify-macos.sh`でdebug build、core checks、Universal Binary app生成、ad-hoc codesign検証を一括実行できる。
- 2026-08-30時点の4Deck対応はcommit `28631d4de001331d8aceaa96bf57f778cd9c2ac6`、branch `codex/performance-4deck`へpush済み。
- ACK05 1台のProfile切り替えによるDeck 1〜3操作は、実際のDJ運用で成立済み。
- DJM-750 original + macOS Tahoe 26.6.2 + DJM-750 driver 4.0.1 + rekordbox PERFORMANCE / External Mixerで、4ch独立出力を実機確認済み。
- 標準物理リグは3Deckを基本とし、1DeckあたりACK05 + 小型Generic HID（4キー + endless encoder想定）を組み合わせる。ソフトウェア上は4Deck能力を維持する。
- Generic HIDの候補実機としてKoolertron系小型マクロパッドを検証するが、OverCUEのUI・データモデルを特定製品へ依存させない。
- CLI bridgeのlive session identityはIOHID接続インスタンス由来transport identifierを使い、Serial由来persistent identityと分離する。
- ACK05実機2台ではSerial Numberを取得できず、macOS `PhysicalDeviceUniqueID`をACK05限定のPairing Identityとして使用する。Pairing Identityは電源OFF/ONとMac再起動では維持され、Bluetooth再ペアリングで変化する。
- 同時接続deviceが同じpersistent identityを名乗る場合はbindingをambiguousとしてdefault Profileへ戻し、接続トポロジ変更を既存controllerへ即時通知する。
- Runtime Status / Controlはsession device ID、Logical Device ID、Profile名とdevice / global scopeを保持する。GUIはstatus受信だけで設定を書き戻さない。
- Group Preset切替・assignment変更・対象device接続時は既存device-scoped runtime controlで参照Presetを適用する。同じGroup Preset assignmentのままCycle Presetした状態は通常status/config更新では初期Presetへ巻き戻さない。
- default Profile用GUIのruntime targetはdefault Profileのdeviceだけで更新する。non-default Profileのstatusはdefault UIのcontrol targetを奪わない。
- CLIは通常のACK05キー／ダイヤル入力時にもdevice-scoped runtime statusをpublishし、default Profile UIのcontrol targetを実際に操作したdeviceへ追従させる。
- default Profile device切断時はGUI targetを解放し、再接続statusで新しいsession targetへ更新する。live default targetがない場合、GUIはglobal controlへフォールバックしない。
- GUI / CLIによる`config.json`更新は共通`OverCUEConfigurationFileStore`のlock付きread-modify-writeを使う。GUIは最後に読み込んだbaseline、GUIローカル変更、最新disk stateの3-way mergeを行い、CLI由来の無関係な変更を古いin-memory configで上書きしない。
- Group PresetとdevicePresetAssignmentsもstable ID / Logical Device ID単位で3-way mergeする。
- version 1〜8 migrationもlock取得後の最新dataを再判定し、別processが既にcurrentへ移行・更新したstateを古いmigration snapshotで上書きしない。
- CLIはGUI runtime controlを処理する直前に最新configをreloadし、stable Preset ID / Mode / Action mappingを最新値から再解決する。Deckのruntime stateは持たない。
- version 9 migrationのlegacy `location:`値は`lastKnownLocationID` hintだけへ移し、persistent match対象へ残さない。
- ACK05 Learn / Captureは最初のsource physical deviceへ固定し、別ACK05の入力を混在させない。source切断時はcaptureをキャンセルする。
- GUIはruntime/config変更時にdiskの最新baselineと未保存local差分をreconcileし、CLI保存済みModeをPreset往復で古い値へ戻さない。
- CLIはACK05入力前にconfig revisionを確認し、変更時はbinding、Profile、Preset mappingを再構築する。config内容とrevisionは同じlock内のsnapshotとして読む。
- `HIDDeviceRegistry`は接続中Physical Deviceをsession identityで管理し、persistent binding、ambiguous状態、Profile、Location hintを派生する。
- Identifyは最初の入力sourceへ固定する。Rebindは一意なpersistent identityだけを受理し、ForgetはLogical Device / Profileを残してPhysical Bindingだけを削除する。
- Generic HIDはUsage / Report / collection pathから入力を表現し、cookieはruntime診断専用とする。重複signatureは実機根拠なしに永続化しない。
- `ActionEvent`の正本source identityはadapter非依存の`ActionSourceID`。Generic HID relative入力は正負activationを分離し、delta量を`activationCount`へ保持する。
- Rebindは対象Physical Deviceのlive sessionが現在接続中であることを必須にし、stale descriptorを拒否する。
- Generic HID eventは既存Action Layerへ変換し、rekordbox commandId解決やkeyboard送信をGeneric層へ直接持ち込まない。
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
- Presetはデータ構造として可変個とし、当面の製品上限を24とする。24固定配列として設計しない。
- Group Presetは最低1個を維持する。

## 採用済みの決定

- 2026-08-30 Decision `20260830T200000-28631d`の「Groupへ対象Deckを持たせる」方針は、2026-09-01 Decision `20260901T201000-91c4e7`で置換した。
- Group / Presetに`targetDeck` / `rekordboxDeck`を持たせない。GUIの「対象Deck」selectorも削除する。
- 対象scopeは、ユーザーがrekordboxショートカット一覧から選択したaction/shortcut自身の属性として保持する。Deck scopeを別UI・別runtime stateで二重指定しない。
- Action LayerはCue hold / Jump repeat等のsemantic behaviorを維持しつつ、選択されたrekordbox actionのscopeを失わない表現へ移行する。Generic `rekordbox:<commandId>`は従来どおりユーザー指定値をそのまま扱う。
- 現在の4 Groupは、stable ID、必須name、order、`rekordboxMode`、`waveformPosition`、mappingsを持つPresetへ移行する。
- Presetは可変個、製品上限24。UIは番号ボタン列ではなくname付きドロップダウンで選択する。
- Cycle Presetは1〜24の番号を機械的に巡回せず、存在するPresetをorder順に巡回して末尾から先頭へwrapする。
- v9→v10 migrationでは既存Groupの意味を保持する。旧Group-level `rekordboxDeck`は、そのGroup内のDeck依存標準Actionをscope付きaction/shortcut referenceへ変換するためだけに使用し、migration後のruntime/configには残さない。Internal ActionとGeneric commandIdへ不要なDeck scopeを付けない。
- Shortcut画面は現在のACK05デバイスマップ領域の幅を維持し、Device管理用の第3カラムを追加しない。
- アプリの主要ナビゲーションは当面「ショートカット / デバイス / 設定」の3タブとする。Identify / Rebind / Forget / Generic HID追加・LearnはDevices側へ集約し、Learnを独立トップレベルタブにしない。
- commandIdの操作suffixをsemantic Actionへ使う場合は`RekordboxActionAdapter`をSingle Source of Truthとして維持し、scope情報との責務を混同しない。
- 波形ドラッグ座標はProfile共通ではなくPresetごとに保存・復元する。
- Freeプラン向けの主運用はマウス／キーボード出力とし、DDJ-SX互換MIDIは補助経路として残す。
- release appは`dist/OverCUE.app`へ生成し、`OverCUE`と`overcue-cli`の両方をarm64 + x86_64にする。
- ACK05はOfficial / First-class device、Generic HIDはAdvanced / Best-effortとして扱う。
- Physical DeviceとLogical Deviceを分離し、ProfileとGroup PresetはLogical Deviceを参照する。
- Group PresetはLogical Device→Preset stable IDの親設定とし、Physical Deviceやsession IDを保存しない。
- Group Preset適用後のCycle Presetは各Logical Deviceの一時runtime stateとし、同じ親assignmentの通常status/config変更では初期Presetへ戻さない。
- Preset削除・Logical DeviceのProfile変更時はGroup Presetにdangling Preset referenceを残さない。
- Generic HID入力は可能な限りIOHIDのdevice sourceを保持した状態で扱い、同じキーコードを送る同型デバイス同士を区別できるようにする。
- 未登録Generic HIDの検出は受動的に行い、勝手に登録・画面遷移しない。登録はDevicesからAdd Generic Device → Identify/Learnで明示的に行う。
- 物理デバイス識別は固有Serialを最優先し、ACK05では実機証拠に基づきPairing Identityを使う。USB topology / locationは補助ヒントに留める。曖昧な場合はユーザーに対象デバイスを操作してもらいIdentify / Rebindする。
- runtime statusは「現在の画面の編集対象」と「他Profileの演奏状態」を混同しない。default Profile UIはnon-default Profileのstatusでcontrol targetを書き換えない。
- `config.json`は単一ファイルを正本とし、複数processがそれぞれ古い全体snapshotを後勝ち保存しない。永続更新はlock付き最新read-modify-writeまたはbaseline差分のmergeとして扱う。
- Device Registryは接続sessionのruntime状態だけを管理し、永続bindingの正本はconfigのPhysical Binding / Logical Deviceとする。
- Identifyは最初に操作された候補sessionを返し、RebindはPhysical Bindingだけを交換する。LocationIDや曖昧なidentityを自動確定に使わない。
- Generic HID descriptorはUsage Page / Usage / Report ID / collection pathを候補とし、IOHIDElement cookieをpersistent identityにしない。同一signatureが複数なら永続化を保留する。
- Generic HIDは必ず既存Action Layerを通し、Generic層からrekordbox commandId解決やkeyboard outputを直接行わない。
- 標準物理構成は3Deckとし、4Deckはソフトウェア能力とオプション拡張として残す。

## 変更してよい範囲

- Presetのnamed/ordered可変構造、Group-level targetDeck廃止、scope付きrekordbox action/shortcut reference、およびv9→v10 migration。
- Group PresetのLogical Device→Preset参照、device-scoped runtime適用、参照整合性、3-way merge、Devices UI。
- 現行Action Layerのsemantic behaviorを保つための局所的な型変更・テスト・ドキュメント更新。
- 複数ACK05を物理個体ごとに分離する入力状態管理。
- config永続化の競合防止、process間runtime scope、Logical Device bindingの安全性改善。
- Generic HIDのdevice-aware入力、Logical Device binding、Identify / Rebind、Learn。
- Shortcut / Devices / Settingsの責務分離に沿ったUI変更。Shortcut画面の既存デバイスマップ表示を圧迫しない。
- ローカル検証の再現性、エラー表示、未割り当て時の診断改善。
- 既存挙動を保持するための可逆なCore checks追加。

## 変更してはいけない範囲

- PresetやProfileへ`targetDeck` / `rekordboxDeck`を再導入し、選択済みshortcutのscopeと二重管理しない。
- Shortcut編集UIへ別途Deck selectorを追加しない。対象scopeはショートカット選択自体から決まる。
- v9→v10 migrationで既存Group 1〜4の入力割当、Mode、waveformPosition、旧Deck意味を失わない。
- Generic `rekordbox:<commandId>`を標準Action扱いして勝手に変換しない。
- Group PresetへPhysical Device IDや接続session IDを保存しない。
- 同じGroup Preset assignmentの通常status/config更新で、Cycle Preset後の一時runtime stateを初期Presetへ巻き戻さない。
- Group Presetから除外したLogical Deviceのruntimeを暗黙に停止・変更しない。
- Generic HID対応をKoolertron固有モデルとして設計しない。
- 同型デバイスをVID/PIDだけで恒久的に個体識別したことにしない。
- Serialが存在するという理由だけで、同時接続中の同一Serial deviceを同一live sessionまたは同一Logical Deviceとして無条件に扱わない。
- USB topology / locationを永続的なLogical Device IDとして扱わない。
- legacy `location:`値をpersistent Physical Bindingとして復活させない。
- Runtime Status / Controlのsource deviceを失ったまま、別controllerや`defaultProfile`へ状態を伝播させない。
- non-default Profileのruntime statusでdefault Profile用GUIのcontrol targetを置き換えない。
- GUI / CLIが古い`OverCUEConfiguration`全体をそのまま後勝ち保存し、他processの変更を消さない。
- Learn / Captureで複数physical deviceの入力を1つのコードへ混在させない。
- Shortcut画面へDevice操作カラムを追加してACK05デバイスマップ領域を潰さない。
- 未登録HIDの接続を理由に設定画面へ自動遷移しない。
- 実データや実機で確認できていない項目を成功済みと記録しない。
- `.aal/logos/`を直接編集しない。
- 未追跡の`Windows/`、`_site/`をOverCUE macOS実装の一部として勝手に削除・追加しない。
- Ableton Live / Launchpad Xを使う演奏体系の検討を、明示なしにOverCUE製品機能へ取り込まない。現時点ではexplorationとして扱う。

## 未決事項

- scope付きrekordbox action/shortcut referenceは`rekordbox-action:<semantic-action-id>:<commandId>`、Preset IDは順序意味を持たないopaque stringとして実装済み。v9 migration IDは決定的に生成し、既定値は明示IDを持つ。
- Koolertron系Generic HIDのキー、encoder CW/CCW、encoder pushがmacOS IOHID上でどのUsage / Reportとして見えるか。
- 同型Generic HIDが固有Serialを持たない場合のbinding永続化と再接続UX。
- Group Preset / Devices UIの2台ACK05実機回帰と、Cycle Preset後の一時runtime state保持確認。
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
- `.ai/decisions/20260901T201000-91c4e7-targetdeckを廃止しpreset-groupとshortcut-scopeを分離する.md`
- `.ai/decisions/20260901T110700-c8f4b1.md`
- `.ai/decisions/20260901T110701-e31a76.md`
- `.ai/decisions/20260901T125000-8f0c2a.md`
- `.ai/decisions/20260902T003000-group-preset.md`
- `.ai/history/20260901T201000-91c4e7.md`

## 有効なモード

- implementation
- review
- reporting
- exploration
- conversation

## 次の行動

version 10 + Group Preset実装のmacOSローカル検証とACK05 2台実機回帰を行う。Generic HIDはKoolertron候補の実機probe結果なしにpersistent mapping schemaを確定しない。

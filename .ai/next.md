# Next

## 現在のフェーズ

Device Management CoreとGeneric HID観測・Learn・Action変換基盤まで実装済み。現行HEADは`c00d608`、config version 9。

2026-09-01のUI/ユースケース再検討で、次のschema変更を採用した。

- Group単位の`targetDeck` / `rekordboxDeck`を廃止する。
- GUIの「対象Deck」selectorも削除する。
- rekordboxショートカット一覧から選択した項目自体が対象scopeを持つ。Deck scopeを別途指定しない。
- 4つの番号Groupを、stable ID + name + orderを持つ可変Preset Groupへ移行する。
- Preset Groupは製品上限24、UIはname付きドロップダウンで選択する。
- Shortcut画面はACK05デバイスマップ領域を維持し、Device操作用の第3カラムを追加しない。
- 主要タブは「ショートカット / デバイス / 設定」。Identify / Rebind / Forget / LearnはDevices側に集約する。

詳細はDecision `20260901T201000-91c4e7`を参照。

## 先に完了する検証

GitHub connectorから直接追加した`14e3df2` / `c00d608`について、macOSローカル検証が未実施である。親commitの成功を流用しない。

- [ ] `aal context build --mode implementation`
- [ ] `swift build`
- [ ] `swift test`
- [ ] `swift run overcue-checks`
- [ ] `./Scripts/verify-macos.sh`
- [ ] `aal doctor`
- [ ] `git diff --check`

## 次の実装ゲート: Preset Group / Shortcut Scope v10

### 1. Group-level targetDeckを完全撤去

- [ ] `OverCUEGroupMapping.rekordboxDeck`をmigration後のcurrent schemaから削除する。
- [ ] GUIの「対象Deck」を削除する。
- [ ] Runtime Status / ControlからDeck stateを削除し、Group/Preset切替時にDeckを復元しない。
- [ ] Bridgeの`activeRekordboxDeck`のようなGroup-global Deck stateを廃止する。
- [ ] Deck依存Actionが一つのPreset内で異なるDeck/scopeを混在できることをchecksで固定する。

### 2. 選択shortcut/action自身にscopeを保持

- [ ] rekordbox一覧で選択された項目が持つ対象scopeをAction Binding側へ保持する。
- [ ] `Deck 1 / Cue`、`Deck 2 / Cue`、`Deck 3 / Cue`等を別の対象として選択でき、追加Deck selectorなしで正しいcommandIdへ到達する。
- [ ] All Decks / Browse / Sampler / Recordings / General / View等の非Deckカテゴリを、無理にDeck enumへ押し込まない。
- [ ] Cue hold / Jump repeat等のsemantic Action behaviorを失わない。
- [ ] Generic `rekordbox:<commandId>`は明示指定値をそのまま保持し、scope変換しない。
- [ ] scope付きreferenceの最終型名・永続表現は実装時に決めてよいが、別`targetDeck`を復活させない。

### 3. named Preset Group

- [ ] Profile内のGroupをstable ID + 必須name + orderを持つPreset Groupへ移行する。
- [ ] Preset Groupは可変個。製品上限24。24固定配列にはしない。
- [ ] 既存4 Groupはmigrationで4 Preset Groupとして保持する。
- [ ] migration時の初期nameは既存番号との対応が分かる値を生成する。
- [ ] UIのGroup 1〜4 segmented controlをname付きドロップダウンへ変更する。
- [ ] Cycle Preset Groupは存在するPresetをorder順に巡回してwrapする。欠番や未作成slotを巡回しない。
- [ ] `rekordboxMode`と`waveformPosition`はPreset Group属性として維持する。

### 4. v9 → v10 migration

- [ ] config version 10が必要なら一度だけ上げ、v9 backupを維持する。
- [ ] v9 Groupの`rekordboxDeck`を、そのGroup内のDeck依存標準Actionをscope付きreferenceへ変換するために使用する。
- [ ] migration後は旧`rekordboxDeck`をruntime/configへ残さない。
- [ ] Internal ActionへDeck scopeを付けない。
- [ ] Generic commandIdを変換しない。
- [ ] Group 1〜4のMode、waveformPosition、keyMap、chordMap、dialMap、dialChordMapの意味を維持する。
- [ ] migration concurrency / backup / unsupported version / round-tripを既存file-store checksへ追加する。

### 5. Shortcut / Devices UI責務

- [ ] Shortcut画面は現行の2カラム構成を基本維持し、ACK05実機図を細くしない。
- [ ] Device管理操作をShortcut画面の第3カラムとして追加しない。
- [ ] 「ショートカット / デバイス / 設定」の3タブを基本ナビゲーションとする。
- [ ] DevicesタブでPhysical Device一覧、Logical Device binding、Identify、Rebind、Forget、Generic HID Add/Learnを扱う。
- [ ] Learnを独立トップレベルタブにしない。

## 完了条件

- [ ] targetDeck / rekordboxDeckがcurrent schema・runtime・Shortcut GUIから消えている。
- [ ] 1つのPreset Group内でDeck 1 / Deck 2 / Deck 3向けshortcutを混在できる。
- [ ] Preset Groupをname付きドロップダウンで選択できる。
- [ ] 既存v9設定が意味を失わずmigrationする。
- [ ] `swift build`
- [ ] `swift test`
- [ ] `swift run overcue-checks`
- [ ] `./Scripts/verify-macos.sh`
- [ ] `aal doctor` 0 failures / 0 warnings
- [ ] `git diff --check`

## 実機確認は並行して進めてよい

- [ ] ACK05 ×2でdefault / non-default Profile、同時入力、切断・再接続、ambiguous bindingを確認する。
- [ ] `overcue-probe --all`でKoolertron候補機のキー、encoder CW/CCW、encoder pushのUsage / Report / relative deltaを採取する。
- [ ] 同型Generic HID複数台のSerial有無と再接続時descriptor安定性を確認する。
- [ ] 実機データを根拠にGeneric HID persistent mapping schemaを決める。

## 保留

- Generic HID mappingの永続schemaとruntime接続。実機identityの証拠待ち。
- Devices画面の細部レイアウト。責務とタブ分離のみ確定。
- Parent Preset / Scene。
- Deck 4=`33xx`規則の実データ確認。
- GitHub Actionsの復旧。
- Developer ID署名とnotarization。
- Ableton Live / Launchpad Xの統合検討。

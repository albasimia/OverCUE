# targetDeckを廃止しPreset GroupとShortcut Scopeを分離する

- Change ID: `20260901T201000-91c4e7`
- 状態: 採用
- Supersedes: `20260830T200000-28631d`

## 背景

4Deck対応では各Groupへ`rekordboxDeck`を持たせ、標準Actionを`ActionID + Deck`からcommandIdへ解決していた。この設計は「1 Group = 1 Deck」の運用には単純だったが、複数ACK05やGeneric HIDを機能別コントローラーとして使うユースケースを考えると制約になる。

例えば1台のACK05へ、K1=Deck 1 Loop、K2=Deck 2 Loop、K3=Deck 3 Loopのように複数Deckの同種機能をまとめたい場合、Group-global targetDeckでは表現できない。

さらに現行Shortcut GUIでは、rekordboxのショートカット一覧自体がBrowse / Deck 1 / Deck 2 / Deck 3 / All Decks / Sampler / Recordings / General / View等に分類されている。ユーザーが`Deck 2`カテゴリの操作を選んだ時点で対象scopeは既に確定しており、上部の「対象Deck」selectorは同じ情報をもう一度入力させる二重管理になっている。

同時に、Groupを24程度まで増やしたいユースケースが出ており、1〜4の番号ボタンよりname付きPresetとして扱う方が意味が明確になった。

## 決定

### targetDeck / rekordboxDeck

- Group / Preset Group単位の`targetDeck` / `rekordboxDeck`をcurrent modelから廃止する。
- Shortcut GUI上部の「対象Deck」selectorを削除する。
- Runtime Status / ControlでもDeckをGroup-global stateとして同期しない。
- Deck targetingという概念を別設定として持たない。対象scopeは選択されたrekordbox action/shortcut自身が持つ。

### Shortcut Scope

- ユーザーは既存のrekordboxショートカット一覧から対象項目を選ぶだけとする。Deck selectorを追加しない。
- `Deck 1 / Cue`と`Deck 2 / Cue`は、同じsemantic behaviorを共有していても別のscopeを持つ選択対象として扱う。
- Deck以外のBrowse / All Decks / Sampler / Recordings / General / View等を無理に`RekordboxDeck`へ変換しない。
- Action LayerはCue hold、Jump repeat等のsemantic behaviorを維持する。scopeを持たせるために全部を生commandId passthroughへ退化させない。
- Generic `rekordbox:<commandId>`は従来どおり明示指定値をそのまま使用する。
- 永続表現は`ActionTarget.rekordboxAction`を`rekordbox-action:<semantic-action-id>:<commandId>`としてencodeする。別の`targetDeck` fieldは追加しない。

### Preset Group

- 現在の番号Groupを、stable ID、必須name、orderを持つPreset Groupへ移行する。
- Preset Groupは`rekordboxMode`、`waveformPosition`、各input mappingを保持するがDeckは保持しない。
- データ構造は可変個。製品上の当面上限は24とし、24個固定配列にはしない。
- UIでは1〜4のsegmented controlをname付きドロップダウンへ変更する。
- Cycle Preset Groupは存在するPresetをorder順に巡回し、末尾から先頭へwrapする。未作成slotや欠番は概念として持たない。

### UI責務

- Shortcut画面の現在のACK05デバイスマップは主要操作面であり、Device管理カラム追加によって幅を潰さない。
- 主要ナビゲーションは当面「ショートカット / デバイス / 設定」の3タブ。
- Identify / Rebind / Forget / Add Generic HID / LearnはDevices側へ集約する。
- Learnを独立トップレベルタブにしない。

### Migration

- この変更はcurrent config schemaを変えるため、version 10とする。
- v9→v10では既存Group 1〜4をPreset Groupへ変換し、Mode、waveformPosition、key/chord/dial/dialChord mappingを保持する。
- 旧Groupの`rekordboxDeck`は、そのGroup内のDeck依存標準Actionをscope付きrekordbox action/shortcut referenceへ変換するためだけに使用する。
- migration後のcurrent config/runtimeから`rekordboxDeck`を削除する。
- Internal Actionへ不要なscopeを付けない。
- Generic commandIdは変換しない。
- migrationによって既存ユーザー設定の意味を変えない。

## 理由

- Shortcut一覧で対象scopeが既に選択されているため、targetDeckは情報として重複している。
- Group-global Deckを消すことで「1物理デバイス = 1Deck」という暗黙制約がなくなり、Deck別デバイスと機能別デバイスの両方を構成できる。
- scopeとsemantic behaviorを同じshortcut referenceで保持すれば、Cue holdやJump repeatを維持しながらDeck別commandIdを選べる。
- named Preset Groupは24程度へ拡張してもUIが破綻せず、Presetの用途を番号以外で説明できる。
- Device管理を別タブへ分離することで、演奏／ショートカット設定の主要画面を複雑化しない。

## 影響

- 旧Decision `20260830T200000-28631d`は置換済みとなる。
- `OverCUEGroupMapping.rekordboxDeck`、GUI `targetDeck`、BridgeのGroup-global active deckはcurrent model/runtimeから削除した。旧JSON fieldはmigration decode専用とする。
- `RekordboxActionAdapter`はsemantic Actionとrekordbox command familyのSSOTとして残しつつ、scope付きshortcut referenceとの責務境界を整理する必要がある。
- Preset Group stable ID導入により、将来のParent Preset / Rigから番号ではなく安定IDで参照できる。
- config v10 migration、GUI、Core checks、runtime/config concurrency mergeの更新が必要になる。

## 実装確定事項

- scope付きreferenceはSwift型`ActionTarget.rekordboxAction(ActionID, commandID:)`、JSON文字列表現`rekordbox-action:<semantic-action-id>:<commandId>`とする。
- Preset Group IDは順序意味を持たないopaque stringとする。v9 migrationでは旧Group番号から決定的IDを生成し、再migrationでも同じIDを得る。
- migration時の初期nameは既存対応が分かる`Group N`とし、orderには旧Group番号を保持する。
- Runtime Status / Controlは互換用order番号に加えてstable Preset IDを送る。current同士はstable IDを優先し、削除済みIDへのcontrolを無視する。

## 不採用

- Group-level default Deck + 各Binding override: scopeの出所が複数になり、「このDeckはどこから決まったか」が再び不明瞭になるため不採用。
- 各Shortcut編集画面へDeckドロップダウン追加: rekordbox一覧ですでにscopeを選んでおり、同じ情報の再入力になるため不採用。
- Deck別Action IDを大量追加: semantic behaviorが重複しSSOTを失うため不採用。
- 24個のPresetを固定配列として持つ: 未使用slotと番号意味をデータモデルへ持ち込むため不採用。

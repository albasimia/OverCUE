# Next

## 現在のフェーズ

PERFORMANCE 4Deckのソフトウェア構造は成立済み。ACK05 1台のProfile切り替えによる3Deck実地運用と、DJM-750 originalへの4ch独立出力も確認済み。複数ACK05向けcontrollerとconfig version 9 bindingモデル、およびcommit `3a81b4e`レビューの4修正ゲートはcommit `e822d54`でソフトウェア実装・Core checks・ローカルビルドまで完了した。その後の追加レビューでruntime targetとGUI / CLI config競合にP1を2件見つけ、直接修正を入れた。今回の追加修正はGitHub connector環境で実装したため、まずmacOSローカル検証を通してから複数実機確認へ進む。

## 次の目的

runtime controlの対象deviceと`config.json`の永続状態が複数process / 複数ACK05で競合しないことを確定し、その後ACK05 ×2でPhysical Device → Logical Device → Profile → OverCUE Actionの境界を実機確認する。

## 追加レビューゲート — commit `e822d54`

### P1 — non-default Profileのstatusでdefault UIのcontrol targetを奪わない

- [x] `ShortcutSettingsModel.applyRuntimeStatus()`は、source Profileが`defaultProfile`と一致する場合だけdefault UIの`runtimeDeviceID` / `runtimeLogicalDeviceID` / `runtimeProfileName`を更新する。
- [x] non-default Profileのstatusを受けてもdefault Profile用GUIのruntime targetを置き換えない。
- [x] CLIは通常のACK05キー入力とダイヤル入力でもdevice-scoped runtime statusをpublishし、default Profile UIのtargetを実際に操作したdefault Profile deviceへ追従させる。
- [ ] ACK05 ×2でdefault / non-default Profileを割り当て、non-default device操作後もdefault UIからdefault deviceへGroup / Mode controlを送れることを実機確認する。

### P1 — GUI / CLIの古いconfig全体書き戻しを禁止する

- [x] Coreに`OverCUEConfigurationFileStore`を追加し、`config.json.lock`の排他lock下で最新configをread-modify-writeする共通永続化経路を用意する。
- [x] GUIは最後に読み込んだbaseline、GUIのlocal state、最新disk stateを`OverCUEConfigurationMerger`で3-way mergeし、GUIが変更していないfieldは最新disk stateを保持する。
- [x] CLIのMode / waveform保存は最新disk stateを読み、対象fieldだけ変更して保存する。
- [x] GUI runtime controlを受信したCLIは処理直前に最新configをreloadし、Group / Mode / Deck / Action mappingを再構築してからcontrolを適用する。
- [x] 同一GroupへのGUI controlでもreload後のAction mappingを使用する。
- [ ] GUIでDeckを変更した直後にCLIがModeを保存してもDeckが旧値へ戻らないことをローカル／実機で確認する。
- [ ] CLIでModeまたは波形位置を変更した後にGUIで別設定を保存してもCLIの変更が消えないことを確認する。

### 追加ゲート完了条件

- [ ] `aal context build --mode implementation`が成功する。
- [ ] `swift build`が成功する。
- [ ] `swift run overcue-checks`が既存273件を含め全件成功する。
- [ ] `./Scripts/verify-macos.sh`が成功する。
- [ ] `aal doctor`が0 failures / 0 warningsになる。
- [ ] `git diff --check`が成功する。
- [ ] 上記2件の競合再現シナリオをローカルまたはACK05 ×2実機で確認する。

この追加ゲートが閉じるまでは、Generic HID Learn / Devices UIの新規実装を先行させない。

## 既存レビューゲート — commit `3a81b4e`

### P1 — live session identityをpersistent identityから分離する

- [x] `PerDeviceACK05ReportRouter` / runtime controllerのキーに、Serial由来のpersistent identityを使わない。
- [x] live sessionのcontroller stateは、同一プロセス内の接続インスタンスを必ず区別できるsession identityで分離する。Serialの有無や重複でcontrollerが共有されないこと。
- [x] SerialはPhysical Bindingの永続候補としてのみ扱い、runtime state identityとは分離する。
- [x] 同時接続中に同じVID / PID / Serialを名乗る複数deviceが存在する場合、同じLogical Deviceへ無条件に自動bindingしたことにしない。曖昧としてIdentify / Rebindへ送れる構造にする。
- [x] 同じSerialを持つ2つのdescriptorでも、InputActionResolver stateが独立するCore checkを追加する。Cue hold、Jump repeat、Group / Deck、ダイヤル、波形ドラッグはcontroller分離で保持し、実機確認を残す。

### P1 — Runtime Status / Controlをdevice scopeへ分離する

- [x] `OverCUERuntimeStatusNotification` / `OverCUERuntimeControlNotification`へsession device ID、Logical Device ID、Profile名とscopeを追加する。
- [x] あるACK05のGroup / Mode変更をdevice-scoped controlで対象controllerだけへ届ける。
- [x] GUIがCLI由来runtime statusを受け取っただけで`defaultProfile`へ保存しない。
- [x] GUIからのcontrolをdevice / global scopeで明示する。
- [x] single ACK05時は最初のstatus以降device scopeを使い、接続前だけglobal controlで従来UXを維持する。

### P1 — legacy `location:` migrationを永続binding扱いしない

- [x] legacy `location:XXXXXXXX`は`lastKnownLocationID`だけへ移行し、persistent match対象にしない。
- [x] `LocationID`をIdentify / Rebind候補のhintに限定する。
- [x] 同じUSB portの別個体が旧Logical Deviceへ自動bindingされないCore checkを追加する。
- [x] 非location旧識別値だけを後方互換の`legacyDeviceIdentifier`として残す。

### P2 — ACK05 captureを1 physical deviceへロックする

- [x] `ACK05InputMonitor`のkey / dial / connection callbackはsource device IDを上位へ渡す。
- [x] Learn / Capture開始後、最初に入力したACK05をcapture sourceとして固定する。
- [x] 別ACK05のキー状態を同じコードへ混在させないCore lockとGUI filteringを追加する。
- [x] capture source切断時は編集をキャンセルし、別deviceへ暗黙継続しない。

commit `e822d54`時点では上記既存ゲートの273 Core checksと`verify-macos.sh`が成功済み。今回の追加修正についてはその成功記録を流用せず、新たにローカル検証する。

## その後の次の行動

- [x] ACK05入力状態を物理IOHID deviceごとのcontrollerへ分離し、同一Serialでもstateを共有しない構造にする。Core checks済み、2台実機は未検証。
- [ ] Generic HIDをglobal keyboard eventへ潰す前のdevice-awareなIOHID入力として観測する基盤を追加する。
- [x] Physical DeviceとLogical Deviceを分離したconfig version 9 bindingモデルを定義し、Serial ambiguity / Location hintを補強する。
- [ ] Devices → Add Generic Device → Identify/Learnの明示登録フローを用意し、未登録HID接続時に自動登録・自動画面遷移しない。
- [ ] Generic HIDのキー入力、encoder CW/CCW、encoder pushを既存OverCUE ActionへLearnできる経路を作る。
- [x] Logical DeviceへProfileを保持し、Physical Bindingと独立して保存・復元できることをCore checksで確認する。Devices UIからのRebind操作は未実装。
- [ ] ACK05 ×2、Koolertron系Generic HID ×複数、UH700を使い、同型デバイス間の独立入力と再接続を実機確認する。
- [ ] 実機確認結果をcore checks、`specs/current-spec.md`、AAL decision / historyへ反映する。

## ブロッカー / 実機依存

- 今回のruntime target / config persistence追加修正はGitHub connector経由で作成したため、macOS build / checks / AAL doctorは未実行。
- 追加ACK05とKoolertron系Generic HIDの到着後でないと、同型複数台のSerial有無、IOHID identity、encoder Report形式を直接確認できない。
- 同型Generic HIDに固有Serialがない場合、再接続時はIdentify / Rebindが必要になる可能性がある。
- 複数ACK05のsoftware state分離は進んでいるが、2台以上の実機による同時入力・切断・再接続は未検証。
- 複数controllerが同時に波形マウスドラッグを要求した場合の操作競合は実機運用で確認が必要。

## 最終完了条件

- 2台以上のACK05を同時接続し、それぞれ異なるLogical Device / Deckへ割り当てても入力状態が混線しない。
- GUI / CLIが同時にconfigを更新しても、互いの無関係な変更を古いsnapshotで消さない。
- 複数の同型Generic HIDを接続し、同じショートカットを送る設定でもdevice sourceによって独立して識別できる、または曖昧時にIdentify / Rebindで安全に解決できる。
- Generic HIDのキーとencoder方向／pushを既存Action Layerへ割り当てられる。
- Physical Deviceを交換またはRebindしてもLogical Device側のProfileが維持される。
- `./Scripts/verify-macos.sh`が成功し、実機確認済み／未確認の境界が仕様とAALへ反映される。

## 保留

- Parent Preset / Sceneによる複数Logical Deviceの一括Profile切り替え。
- 標準3Deckリグの完全独立物理構成（ACK05 ×3 + Generic HID ×3）の完成。
- Deck 4=`33xx`規則の実データ確認。
- GitHub Actionsの復旧。
- Developer ID署名とnotarization。
- Ableton Live / Launchpad Xを使うModern DJ演奏体系の統合検討。これは現時点ではOverCUE製品機能ではなくexploration。

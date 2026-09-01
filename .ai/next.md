# Next

## 現在のフェーズ

PERFORMANCE 4Deckのソフトウェア構造は成立済み。ACK05 1台のProfile切り替えによる3Deck実地運用と、DJM-750 originalへの4ch独立出力も確認済み。複数ACK05向けcontrollerとconfig version 9 bindingモデル、およびcommit `3a81b4e`レビューの4修正ゲートはソフトウェア実装・Core checks・ローカルビルドまで完了した。次は複数実機で境界を確認する。

## 次の目的

ACK05 ×2でdevice identity、runtime scope、ambiguous binding、capture source切断を実機確認し、Physical Device → Logical Device → Profile → OverCUE Actionの前提を確定する。

## 最優先レビューゲート

対象: commit `3a81b4e163541ee052ef8ca0a2fbf206ee380de4` (`feat: isolate physical HID device state`)

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
- [x] GUIからのcontrolをdevice / global scopeで明示し、接続後は最後に操作したsource deviceへ送る。
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

### ゲート完了条件

- [x] 上記P1 3件とP2 1件をすべて実装する。
- [x] 修正を再現するCore checksを追加し、273件すべて成功する。
- [x] `specs/current-spec.md`とAALへ修正後のidentity / runtime scope / migration / capture仕様を反映する。
- [x] `./Scripts/verify-macos.sh`が成功する。
- [x] 実機未確認事項をテスト成功だけで実機確認済みと記録しない。

上記レビューゲートはソフトウェア上で解消済み。複数ACK05の実機境界を確認してからGeneric HID LearnやDevices UIへ進む。

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

- 追加ACK05とKoolertron系Generic HIDの到着後でないと、同型複数台のSerial有無、IOHID identity、encoder Report形式を直接確認できない。
- 同型Generic HIDに固有Serialがない場合、再接続時はIdentify / Rebindが必要になる可能性がある。
- 複数ACK05のsoftware state分離は進んでいるが、2台以上の実機による同時入力・切断・再接続は未検証。
- 複数controllerが同時に波形マウスドラッグを要求した場合の操作競合は実機運用で確認が必要。

## 最終完了条件

- 2台以上のACK05を同時接続し、それぞれ異なるLogical Device / Deckへ割り当てても入力状態が混線しない。
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

# Next

## 現在のフェーズ

PERFORMANCE 4Deckのソフトウェア構造は成立済み。ACK05 1台のProfile切り替えによる3Deck実地運用と、DJM-750 originalへの4ch独立出力も確認済み。複数ACK05向けの物理device別controllerとconfig version 9 bindingモデルは導入済みだが、commit `3a81b4e` のレビューで複数device設計に4件の修正ゲートが見つかった。Generic HID / Devices UIへ進む前に、まずこのゲートを閉じる。

## 次の目的

複数ACK05基盤のdevice identity、runtime state scope、legacy migration、GUI capture sourceを安全に分離し、Physical Device → Logical Device → Profile → OverCUE Actionの前提を確定する。

## 最優先レビューゲート

対象: commit `3a81b4e163541ee052ef8ca0a2fbf206ee380de4` (`feat: isolate physical HID device state`)

### P1 — live session identityをpersistent identityから分離する

- [ ] `PerDeviceACK05ReportRouter` / runtime controllerのキーに、Serial由来のpersistent identityを使わない。
- [ ] live sessionのcontroller stateは、同一プロセス内の接続インスタンスを必ず区別できるsession identityで分離する。Serialの有無や重複でcontrollerが共有されないこと。
- [ ] SerialはPhysical Bindingの永続候補としてのみ扱い、runtime state identityとは分離する。
- [ ] 同時接続中に同じVID / PID / Serialを名乗る複数deviceが存在する場合、同じLogical Deviceへ無条件に自動bindingしたことにしない。曖昧としてIdentify / Rebindへ送れる構造にする。
- [ ] 同じSerialを持つ2つのdescriptorでも、InputActionResolver、Cue hold、Jump repeat、Group / Deck、ダイヤル、波形ドラッグ状態が独立するCore checkを追加する。

### P1 — Runtime Status / Controlをdevice scopeへ分離する

- [ ] `OverCUERuntimeStatusNotification` / `OverCUERuntimeControlNotification`へdevice scopeを持たせる。少なくともsession device IDまたはLogical Device IDを識別できること。必要ならprofile名も通知する。
- [ ] あるACK05のGroup / Mode変更が、別ACK05のcontroller stateへ意図せず伝播しない。
- [ ] GUIがCLI由来runtime statusを受け取っただけで`defaultProfile`へ無条件保存しない。statusのsourceと保存対象Profile / Logical Deviceを一致させる。
- [ ] GUIからのcontrolが特定device向けかglobal操作かを曖昧にしない。global操作を残す場合は明示的なscopeとして扱う。
- [ ] single ACK05時の従来UXは維持する。

### P1 — legacy `location:` migrationを永続binding扱いしない

- [ ] version 8以前の`deviceProfiles`でlegacy IDが`location:XXXXXXXX`の場合、`lastKnownLocationID`へ移行しても`legacyDeviceIdentifier`のpersistent match対象にはしない。
- [ ] `LocationID`は既存decisionどおりIdentify / Rebind候補のhintに限定する。
- [ ] 同じUSB portへ別個体を接続しただけで、旧Logical Deviceへ自動bindingされないCore checkを追加する。
- [ ] `PhysicalDeviceUniqueID` / `DeviceAddress`等の旧識別値を後方互換で残す場合は、`location:`と明確に分岐する。

### P2 — ACK05 captureを1 physical deviceへロックする

- [ ] `ACK05InputMonitor`のkey / dial callbackはsource device IDを上位へ渡す。
- [ ] Learn / Capture開始後、最初に入力したACK05をcapture sourceとして固定し、完了・キャンセルまで他deviceの入力を混ぜない。
- [ ] ACK05 AのK7とACK05 BのK1を`K7+K1`の1コードとして誤認しない。
- [ ] device切断時のcapture解除 / 待機状態を定義し、別deviceへ暗黙継続しない。

### ゲート完了条件

- [ ] 上記P1 3件とP2 1件をすべて実装する。
- [ ] 修正を再現するCore checksを追加し、既存checksも全件成功する。
- [ ] `specs/current-spec.md`とAAL historyへ修正後のidentity / runtime scope / migration / capture仕様を反映する。
- [ ] `./Scripts/verify-macos.sh`が成功する。
- [ ] 実機未確認事項をテスト成功だけで実機確認済みと記録しない。

上記レビューゲートを閉じるまでは、Generic HID LearnやDevices UIの新規機能実装を先行させない。

## その後の次の行動

- [x] ACK05入力状態を物理IOHID deviceごとのcontrollerへ分離し、キー／コード／Cue hold／Jump repeat／ダイヤル／波形状態を共有しない構造にする。Core checks済み、2台実機は未検証。ただし上記session identity gateの補強が必要。
- [ ] Generic HIDをglobal keyboard eventへ潰す前のdevice-awareなIOHID入力として観測する基盤を追加する。
- [x] Physical DeviceとLogical Deviceを分離したconfig version 9 bindingモデルを定義する。Serial / Locationの扱いは上記migration / ambiguity gateで補強する。
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

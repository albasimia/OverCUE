# Next

## 現在のフェーズ

PERFORMANCE 4Deckのソフトウェア構造は成立済み。ACK05 1台のProfile切り替えによる3Deck実地運用と、DJM-750 originalへの4ch独立出力も確認済み。次は複数物理デバイスを同時に扱うOverCUE vNextの入力基盤へ進む。

## 次の目的

複数ACK05とGeneric HIDを物理個体ごとに分離して同時利用し、Physical Device → Logical Device → Profile → OverCUE Actionという経路を成立させる。

## 次の行動

- [ ] ACK05入力状態を物理IOHID deviceごとに分離し、同型ACK05を2台以上接続してもキー／コード／ダイヤル状態が衝突しない構造にする。
- [ ] Generic HIDをglobal keyboard eventへ潰す前のdevice-awareなIOHID入力として観測する基盤を追加する。
- [ ] Physical DeviceとLogical Deviceを分離したbindingモデルを定義する。固有SerialがあればVID + PID + Serialを優先し、USB topology / locationは補助ヒントに留める。
- [ ] Devices → Add Generic Device → Identify/Learnの明示登録フローを用意し、未登録HID接続時に自動登録・自動画面遷移しない。
- [ ] Generic HIDのキー入力、encoder CW/CCW、encoder pushを既存OverCUE ActionへLearnできる経路を作る。
- [ ] Logical DeviceへProfileを割り当て、物理デバイスをRebindしてもProfile設定が失われないことを確認する。
- [ ] ACK05 ×2、Koolertron系Generic HID ×複数、UH700を使い、同型デバイス間の独立入力と再接続を実機確認する。
- [ ] 実機確認結果をcore checks、`specs/current-spec.md`、AAL decision / historyへ反映する。

## ブロッカー / 実機依存

- 追加ACK05とKoolertron系Generic HIDの到着後でないと、同型複数台のSerial有無、IOHID identity、encoder Report形式を直接確認できない。
- 同型Generic HIDに固有Serialがない場合、再接続時はIdentify / Rebindが必要になる可能性がある。

## 完了条件

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

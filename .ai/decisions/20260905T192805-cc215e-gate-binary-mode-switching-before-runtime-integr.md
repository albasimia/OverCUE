# Gate binary mode switching before runtime integration

- Change ID: `20260905T192805-cc215e`
- 状態: 採用


## 背景

mode 2（呼吸）は全キーをglobal色で呼吸させ、per-key RGBと黒指定を尊重しないことが
実機で判明した。一方、mode 5のper-key表示とmode 0の全消灯は、Serial
`592B14678182`で期待どおり切り替わることを確認した。ただしmode切替commandの
不揮発性や書込寿命は分かっていない。

## 決定

9/6向けPlay/Pause表示の候補は、PLAYをmode 5（SW4をDeck色、他キーは黒）、
PAUSEをmode 0（全消灯）とする。これは実機試験で成立したbinary表示方針であり、
現時点ではproduction runtimeへ常時接続しない。

runtimeへ導入する前にmode切替の永続性・書込耐性を確認する。導入時は入力hot pathから
分離して直列化し、状態が変わった場合だけ送信する。点滅を反復writeで作らない。

## 理由

mode 2は速度こそ実用的だが、全キー・global色となりDeck色のSW4だけを示せない。
mode 5 / 0は追加RGB writeなしの往復で、SW4だけ赤と全消灯を目視・readbackの双方で
確認できた。未確認のwrite特性があるため、検証成立とruntime採用を分離する。

## 影響

- probeには対象Serialを固定した有限回試験コマンドを保持する。
- rekordbox runtime、Preset ownership、Generic HID mapping、native suppressionは変更しない。
- 将来のruntime driverは重複state writeを抑止し、非同期・device-scopedに実装する必要がある。
- mode 0では全キーが消灯するため、Pause時に他キーの状態表示はできない。

## 代替案

- mode 2呼吸: per-key RGBを無視して全キーが多色呼吸するため不採用。
- `06 14`の反復writeによる点滅: 不揮発writeの可能性と入力遅延リスクがあり不採用。
- mode 5 / 0の即時runtime統合: mode切替のwrite特性が未確認のため保留。

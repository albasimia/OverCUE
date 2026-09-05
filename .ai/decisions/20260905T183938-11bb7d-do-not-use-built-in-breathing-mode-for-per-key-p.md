# Do not use built-in breathing mode for per-key Play Pause indication

- Change ID: `20260905T183938-11bb7d`
- 状態: 採用


## 背景

9/6向け最小案として、SIDE-KEYBOARD本体のLighting mode 2を使い、SW4だけをDeck色で呼吸させられる可能性を検証した。Serial `592B14678182`ではCustom mode5のkey3赤・他黒がprotocol readbackとユーザー目視で成立した。

## 決定

本体Lighting mode 2を「Deck色を保持したSW4だけのPlay/Pause表示」には採用しない。
速度が利用可能でも、per-key/黒/RGB色の3要件を満たさないためである。
この判断は当該firmware・取得configでの目視証拠に基づき、未知の別firmwareや別modeの一般的能力までは否定しない。

## 理由

mode2へ公式`06 16`→response-derived `06 0B`で切り替えた結果、SW4だけでなく全SWが呼吸し、黒指定のSW1〜3も点灯し、SW4を含む全体が多色変化した。目的の「PLAY=Deck色常時、PAUSE=同じDeck色でSW4だけ呼吸」と視覚的に両立しない。

## 影響

OverCUE runtimeへmode2切替を接続しない。今回追加したものは隔離branchの固定実験probeと証拠だけで、Action mapping/config/UIは不変。試験deviceはmode1・元RGBへrollback済みで、取得したpre/post範囲はbyte一致。

将来別方式を検討する場合も、不揮発の可能性がある`06 14`を状態点滅に連打せず、書込の揮発性・安全cadence・LED状態取得方法を先に確定する。

## 代替案

- mode2採用：全key・多色になるため不採用。
- `06 14`反復でソフトウェア点滅：不揮発書込の可能性とwrite cadence未確定のため今回は試験も実装もしない。
- 別Lighting modeや未知payload探索：9/6最小構成の今回scope外。推測送信を避けて保留。

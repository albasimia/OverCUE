# Do not drive Play Pause with persistent lighting mode writes

- Change ID: `20260905T195944-6b3dfa`
- 状態: 採用
- Supersedes: `20260905T192805-cc215e`

## 背景

mode 5のper-key表示、mode 0の全消灯、mode 2の全key単色呼吸はいずれも実機で成立した。
しかしPlay/Pauseごとのmode切替には`06 0B`系setterを頻繁に送る必要があり、当該setterの
storage/write特性がruntime採用gateとして残っていた。

Serial `592B14678182`をmode 2・単色赤にした後、約10秒USB電源を断って再接続したところ、
設定clientを動かさなくても同じ発光が即座に再開し、`06 0A` configと`06 13` RGB chunkも
電源断前後でbyte一致した。

## 決定

既知の`06 0B` mode/global color setter、および不揮発保持が確認済みのRGB setterを、
rekordbox Play/Pause状態ごとのruntime LED更新には使用しない。

PLAY=mode 5、PAUSE=mode 2単色Deck色という視覚表現自体は成立済み候補として残すが、
実装にはRAM-only LED command/transportの実機証拠を要求する。証拠が得られない場合は、
起動時など低頻度の明示設定以外へ広げない。

## 理由

USB電源断を越えた完全保持は、device側の不揮発保存を強く示す。媒体と耐久回数が不明なまま、
DJ中に繰り返されるPlay/Pauseへ結び付けるとflash/EEPROM消耗のリスクを評価できない。
少数回の反復耐久試験は寿命を証明せず、試験自体が消耗になり得る。

## 影響

- OverCUE runtimeへ現在のmode setterを接続しない。
- probeの有限実験commandとevidenceは保持する。
- 次のprotocol探索は公式client/firmware内のRAM-only preview/live-output経路を優先する。
- Action Layer、Preset、Generic HID入力、native suppressionの仕様は変更しない。
- Decision `20260905T192805-cc215e`の「write特性確定までgate」を、本Decisionの不採用判断で置換する。

## 代替案

- 状態変更時だけ`06 0B`を送る: 重複抑止をしてもPlay/Pause回数分の不揮発writeが残る。
- 反復実機試験で耐久を推定する: 安全な寿命根拠にならずdeviceを消耗させ得る。
- mode 0/2/5の表示候補自体を破棄する: RAM-only経路が見つかれば再利用できるため、視覚仕様は保留候補として残す。

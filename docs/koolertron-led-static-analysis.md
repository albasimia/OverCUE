# Koolertron候補 0816:246E — LED protocol静的解析

調査日: 2026-09-04 / branch: `codex/koolertron-led-probe`

## Result / confidence

- **Confirmed**: SDTech Option 1.0.3の配布アプリに、VID `0x0816` / PID `0x246E` / Usage Page `0xFF00` / Usage `2`の明示的なフィルタがある。単一キーRGB、全体照明HSV/明るさ/モードの64-byte Output payload生成経路を追跡できた。
- **Strong inference**: この送信経路は前回観測したSIDE-KEYBOARDのinterface C向けであり、LED設定に利用できる可能性が高い。
- **Unknown**: 接続中の各個体のfirmwareが実際に受理するか、物理LEDとの対応、RAM限定か自動flash保存か。今回、実機にはアクセスしていない。

本資料のConfirmedは「取得した配布コードがそのように構築・解釈する」という意味。実機での動作確認を意味しない。

## Package / provenance

主解析対象:

- Software: **SDTech Option 1.0.3**（サイトのWindowsリンクではSDTech Options表記）。`Contents/Info.plist`の`CFBundleShortVersionString` / `CFBundleVersion`と`app.asar/package.json`で確認。
- Platform: macOS arm64。Mach-O launcher + Electron / Next.js / React + WebHID。
- 配布ページ: <https://www.sdcx-tech.com/>
- Download: <https://github.com/EchoXY9/Web_Driver/releases/download/1.0.3/SDTech.Option-darwin-arm64-1.0.3.zip>
- ファイル名: `SDTech.Option-darwin-arm64-1.0.3.zip`
- ZIP SHA-256: `8878f58c1fef829da6f98ec2e49ba7f5deecc5c6c0ada8059ee49227f04534b6`
- `Contents/Resources/app.asar` SHA-256: `db4011e750e6ea0c06197200bbefb82abab29a772d956846f106409264750982`
- メーカー/OEM設定サイト候補が直接掲載する配布リンク。Koolertron本体サイトからこのURLへの公式リンクまでは確認できていない。Koolertron製品レビューが同梱説明書のWeb設定先として同サイトを案内しており、配布物内のVID/PID完全一致で対象との関連を補強した。レビューは発見の手掛かりであり、protocolの根拠は配布コード。
- 発見の手掛かり: <https://mainoriti.com/archives/36357>
- 同設定サイト掲載の他platform（未取得）: [Windows RAR](https://github.com/EchoXY9/Web_Driver/releases/download/1.0.3/SDTech.Options.Setup.1.0.3.rar)、[macOS Intel ZIP](https://github.com/daddasdsa/sd_tools/releases/download/v1.0.3-release/SDTech.Options-mac-Intel-1.0.3.zip)。このため当該Windows版PE内部については未確認。

Web版もHTTPでファイルとして取得し、実行せず照合:

- URL: <https://www.sdcx-tech.com/_next/static/chunks/app/page-bb948a9e8b9c0440.js>
- SHA-256: `9f1e8f55f65235f06d653474f2c34cd0018f98773bac2758189fff44294c4f08`
- 独立したWeb版バージョン番号は未確認。取得時のchunk名とhashで固定する。
- Web版と配布アプリ版で、対象VID/PIDフィルタ、65→64-byte変換、単一キーRGBと全体照明のbuilderが一致する。

先に取得したKoolertron公式掲載の別候補:

| File | Source / platform | SHA-256 | 扱い |
|---|---|---|---|
| MYKB.zip | `https://product_manual.s3.us-east-1.amazonaws.com/MYKB.zip` / Windows | `f51f9dd59a6d5e34a3dfd9324ca4f44738542a8aa7f3b365299bb4da49faa0ff` | ZIP内のMYKB.exeはPE32 / NSIS installer。外側のstrings/importsのみ調査。製品版番号・0816:246E対応は未確定 |
| MYKB_For_MacOS.zip | `https://product_manual.s3.us-east-1.amazonaws.com/MYKB_For_MacOS.zip` / macOS | `cdf23b96324401ab392131e22eabeb88939629539b35bf2525ef1669fbb30240` | 言語別DMG。ENU DMGをZIPから抽出。read-only mountは環境エラーで失敗、内部未解析 |

MYKBの公式掲載元は <https://www.koolertron.com/user-manual-software-download>。2026〜のAMAG/CMKB向けとしてWindows/macOSリンクを掲載するが、SIDE-KEYBOARD向けと断定しない。対象完全一致のSDTech配布物が得られたため、MYKBの追加展開は行わなかった。NSISのversionやZIP内日時を製品版番号とは扱わない。

## Extraction / evidence references

作業場所は `/private/tmp/koolertron-analysis`。ZIPを`unzip`で展開し、ASARはheader JSONと各fileのoffset/sizeをPythonで読み、格納データをコピーした。アプリやそのJavaScript、package scriptsを実行していない。

SDTechにはASARルートと`src/`に異なる世代のWeb bundleが同梱される。`package.json`のmainは`src/index.js`、そこから`src/index.html`を読み込むため、**以下は実際のentryに対応するsrc側**を根拠とする。

基準ファイル（以下P）:

`app.asar/src/_next/static/chunks/app/page-58ff86c8ca1ede81.js`

SHA-256: `cf0bbdb35a701c77e6e2191564811126f4a75463e45fb5f159fa29cc8797e965`

オフセットは整形前Pの**UTF-8 byte offset、0始まり**。最小化変数名はこのhashにのみ対応する。

| 根拠 | Pのoffset |
|---|---|
| `vendorId:2070,productId:9326` | `0x27FA` |
| `N.write` (`async write(e)`) | `0x4EA4` |
| `I.setKeyRGBBytes` | `0x5792` |
| `I.sendDeviceData` | `0x58C0` |
| `I.webhid_write_command` | `0x5E92` |
| `S.getKeyboardConfig` | `0x6265` |
| `S.getKeyInfos`（RGB readを含む） | `0x6682` |
| `S.setKeyColorsInfos`（bulk RGB） | `0x6D14` |
| `S.setKeyColorInfo`（単一RGB） | `0x6EE0` |
| `S.getLightConfig` | `0x715B` |
| `S.setLightEffectConfig` | `0x7265` |
| `S.setLightConfig` | `0x73BF` |
| `key_index:e.index`（layoutから内部index生成） | `0x13341` |
| contextの`updateKeyInfoColor` | `0x13772` |
| `SIDE-KEYBOARD`文字列 | `0x55E11` |

対象layoutはmodule 52166 / chunk 2166:

`app.asar/src/_next/static/chunks/2166.7386f653e56f5890.js`

SHA-256: `e25436e7c2543ed161598c65aacfd96820502a429716c3481be9bbd77191a038`

`getKeyboardLayout()`が実VID/PIDを16進4桁で`0816_246e.json`に組み立て、そのmoduleへ到達する。

## Device match

**Confirmed**:

- requestDevice filter: `{vendorId:2070, productId:9326, usagePage:65280, usage:2}`。
- Electron mainのHID permission/selection処理にもvendor `0x0816`を含む。
- `SIDE-KEYBOARD`は接続説明UIの文字列として存在。product stringによる厳密matchの証拠ではない。
- `SDINNOVATION` / `Koolertron`は主解析P内には見つからなかった。
- `getFilteredDevices`は既許可deviceのcollectionsを検査する。`FF00:0002`以外に他製品用条件も許容するため、このメーカーコード自体を将来の安全なtarget選択実装として転用しない。
- wrapperの`interface:1`は固定metadata。USBのbInterfaceNumber=1の証拠ではない。今回の対応根拠はUsage Page / Usage。
- 対象layoutは`keyboard4n1.png`、通常key index `0,1,2,3`、ノブ操作index `16,17,18`、`key_index_max:19`、`mcu_type:"951"`。これは配布resourceの記述であり、現物のキー数・発光部との一致は別途確認が必要。

**Strong inference**: 前回実機で確認したinterface Cに、このソフトの独自照明protocolが対応する。

## HID implementation / output call path

使用実装: Electron / Chromium WebHID。appのpackage.jsonにnode-hid/hidapi依存はない。`file`でlauncherがMach-O arm64、`otool -L`でElectron Framework依存を確認。Frameworkの`nm -u`には`IOHIDDeviceSetReport` / `IOHIDDeviceGetReport`等がある。ただしnative symbol単体では下記JS call siteからの完全な機械語call graphを証明しない。

単一キー色:

`Lighting画面 / custom modeでキーclick`
→ `au`のclick handler
→ `updateKeyInfoColor(color, layout.index)`
→ `S.setKeyColorInfo(keyInfo)`
→ `I.setKeyRGBBytes(array63)`
→ `I.sendDeviceData(6, array63)`
→ queue / `I.webhid_write_command`
→ `N.write(array65)`
→ `HIDDevice.sendReport(0, Uint8Array(array65.slice(1)))`

全体色・明るさ:

`ap`の色picker / brightness slider / speed slider
→ `S.setLightConfig(config)`
→ `I.sendDeviceData(6, [11,11,0,0,...config11])`
→ 同じqueue / writer / WebHID。

mode選択は`S.setLightEffectConfig(mode)`を呼び、`06 16 ...`で応答を取得してから`06 0B ...`を送る**2要求**。mode変更を単一の安全な実験とはみなさない。

`sendDeviceData`は名前に反してwrite後にreadも待つ。`getDeviceData`もOutput要求を送る。どちらも今回実行していない。

## 64-byte protocol

以下のoffsetは**WebHIDへ渡す64-byte payload内**。Report ID用の先頭byteは含まない。

共通builderは65個のゼロ配列に`[0, command, ...args]`をコピーする。writerが先頭の0を除去し、Report ID `0`をAPIの別引数に渡す。したがってwire payload先頭は`06`であり、`00 06`ではない。

### 単一キーRGB — `S.setKeyColorInfo`

| Offset | Length | Meaning | Confidence |
|---|---|---|---|
| 0 | 1 | command `0x06` | Confirmed |
| 1 | 1 | subcommand `0x14` (20) | Confirmed |
| 2 | 1 | builderの値 `0x03`、RGBデータ長と一致 | Confirmed（汎用length規則は未確定） |
| 3–4 | 2 | `3 * key_index`、little endian | Confirmed |
| 5–7 | 3 | builderがゼロを設定。意味未解明 | Confirmed値 / Unknown意味 |
| 8 | 1 | R、`(#RRGGBB >> 16) & 255` | Confirmed |
| 9 | 1 | G、`(#RRGGBB >> 8) & 255` | Confirmed |
| 10 | 1 | B、`#RRGGBB & 255` | Confirmed |
| 11–63 | 53 | zero padding | Confirmed |

RGB送信にlayer/profileを明示的に格納するコードはない。色が全layer共有か、現在profileへ暗黙適用かはUnknown。キーindexとLEDの物理番号が1対1かも未確定。

### 全体照明 — `S.setLightConfig`

| Offset | Length | Meaning | Confidence |
|---|---|---|---|
| 0 | 1 | `0x06` | Confirmed |
| 1 | 1 | `0x0B` (11) | Confirmed |
| 2 | 1 | config length `0x0B` (11) | Confirmed |
| 3–4 | 2 | zero | Confirmed値 / Unknown意味 |
| 5 | 1 | `type`、照明UIでは1 | Confirmed |
| 6 | 1 | zero | Confirmed値 / Unknown意味 |
| 7 | 1 | mode、下表 | Confirmed |
| 8 | 1 | brightness、UI range 0–4 | Confirmed |
| 9 | 1 | speed、UI range 0–4 | Confirmed |
| 10 | 1 | direction、UIが0/1へ変換 | Confirmed生成 / 対象の機能対応は未確認 |
| 11 | 1 | color checkboxの0/1。mode 0時には0を強制 | Confirmed生成 / 正確なfirmware意味は未確認 |
| 12 | 1 | zero（read側ではsingleColorIndexの位置） | Confirmed |
| 13 | 1 | H、floor(hue / 360 * 255) | Confirmed |
| 14 | 1 | S、floor(saturation / 100 * 255) | Confirmed |
| 15 | 1 | V、floor(value / 100 * 255) | Confirmed |
| 16–63 | 48 | zero padding | Confirmed |

brightness変更handlerはVも`floor(value / 100 * 255 / 4 * brightness)`へ変更する（brightness 0ではV=0）。明るさslider操作はoffset 8だけの変更ではない。

上記builder→writer経路にpayload checksum計算はない。末尾にchecksumを付ける処理もない。これはUSB transport自体のCRC等とは別の話。

## LED commands

| command / subcommand | コード上の用途 | 詳細 / confidence |
|---|---|---|
| `06 0A` | `getLightConfig` | 残り62 bytesゼロ。Input応答offset 5–15を11-byte configとして解釈。Confirmed |
| `06 0B` | `setLightConfig` | 上記全体照明。Confirmed |
| `06 14` | `setKeyColorInfo` | 上記単一キーRGB。Confirmed |
| `06 12` | `setKeyColorsInfos` | RGB列を56-byteずつ送るbulk builder。offset 3–4はchunkのbyte offset、dataはoffset 8から。length欄は通常59、最終partialでは余り+3。定義はConfirmed、UIの実使用箇所は未確認 |
| `06 13` | `getKeyInfos`内のRGB read | length欄58、offset 3–4にchunk offset。Input応答のoffset 8から最大56 bytesをRGB列へ展開。Confirmed |
| `06 16` | `setLightEffectConfig`の前段 | argsは`[22,0,0,0,1,0,mode]`。応答configを受け、modeを設定して`06 0B`。生成順序はConfirmed、前段が完全に無副作用かはUnknown |

対象layout moduleのモード:

| Mode | Resourceのname | 解釈 |
|---|---|---|
| 0 | 关闭 | 消灯 |
| 1 | 常亮 | 常時点灯 |
| 2 | 呼吸 | 呼吸 |
| 3 | 按亮 | 押下時点灯 |
| 4 | 潮汐 | 潮汐エフェクト（実際のアニメーションは未確認） |
| 5 | custom | 個別キー色 |

番号と名称はConfirmed。各実機での発光動作は未検証。

Inputには`AA FA`を先頭に持つlighting通知を判別するコードもある。これは通知用であり、すべてのcommand responseが同じheaderだとは断定しない。generic writerはreadした配列を返すだけで、今回追った経路ではopcode/status/checksumの厳密検証をしていない。

## Persistence

- **Confirmed**: 色picker/sliderは上記setterへ直接到達する。追跡した照明経路に独立したcommit/save commandはない。
- **Unknown**: setter自体がflash保存する可能性、遅延保存、保存寿命、電源断で保持される範囲。独立commitがないことはRAM-onlyの証拠にならない。
- `restoreFactorySettings`、bootloader/IAP/update経路も同梱される。静的に存在を確認しただけで、送信していない。
- 更新用`.bin`も配布物に含まれるが、接続個体のfirmwareと同一とは確認できず、今回そのflash実装の解析までは行っていない。firmware更新は行わない。

したがって現時点でrekordbox状態に連動して高頻度にRGBを送る設計には進めない。

## Remaining unknowns

1. 3個体の実firmware版と、この配布clientのcommand互換性。
2. key_indexから物理LEDへの対応。layoutは4キー+ノブとして記述されているため現物確認が必要。
3. RAM/flash保存、profile/layerごとの色保持、モード5が個別色の表示に必須か。
4. 応答header/status/error、timeout、再送、非同期通知との識別。
5. reserved位置の意味、bulkのlength規則、適切な送信間隔。
6. SDTech配布者とKoolertronの公式契約/OEM関係。VID/PID対応は直接確認できるがブランド関係を証明するものではない。

## Recommended first live experiment — 今回は実行しない

最初は**LED書き換えではなく照明config取得要求を1回**。

- 帰宅後、対象Serialを1台に固定し、VID/PID、Usage Page `FF00` / Usage `2`を照合する。メーカーアプリや他の設定clientは起動しない。
- Report ID `0`、64-byte payload **`06 0A` + 62個の`00`**を1回だけ送る。
- 自動再送・初期化・profile変更・mode変更・commit・resetを追加しない。
- Input応答をrawで保存し、コードが参照するoffset 5–15と照合。見た目や設定が変わらないか目視確認する。
- client上で`getLightConfig`として使われるため、色setterより副作用の可能性が低いと推定する。ただし未解析の実firmware上での無副作用は保証できない。

この要求もtransport上はOutput Report送信であり、今回のread-only作業では実行していない。応答と永続化の扱いを確認するまで、単一RGB試験も次の段階に留める。

## Verification / safety

- AGENTS.md / .ai/project.md / .ai/next.mdを読了。`aal context build --mode exploration`成功、生成context読了。
- 開始時branchは指定どおり、working treeはclean。
- 使用: Web検索、HTTPダウンロード、`unzip`、PythonによるASAR/JSON/文字列解析、`file`、`strings`、`objdump -p`、`otool -L`、`nm -u`、`shasum -a 256`。
- MYKB ENU DMGの`hdiutil attach -readonly -nobrowse -noautoopen`は「装置が構成されていません」で失敗。mount/インストール/起動はしていない。
- 今回はソースコード変更なし、build/test未実施。記録用の本Markdownのみ追加、commitなし。
- **デバイスへの書き込みは一切行っていない。メーカーアプリを実行していない。メーカーアプリをインストールしていない。**
- Web設定アプリも実行せず、配布JSをファイルとして取得・解析した。HID probeの再実行もしていない。
- OverCUEApp / OverCUEBridge / GenericHIDRuntimeCoordinator / ActionLayer / config schemaに変更なし。


## 2026-09-04追記: Custom移行・単一キー・復元sequence

この追記は保存済みSDTech Option 1.0.3 / Web chunkの静的解析のみ。前節の初回query提案は実行済みで、再実行しない。実機query結果は `koolertron-light-query-result.md` を参照。今回の追加送信は0回。

### 結論

clientの処理順序は確定できたが、**元状態へ戻せる全packetを事前確定したlive testにはまだ進めない**。理由は (1) `06 16` の未知の応答に次のpacketが依存、(2) 対象キーの元RGBが未取得、(3) mode切替だけでは個別RGBを書き戻さない、(4) firmwareの保存・副作用が未確認であるため。

さらにclientの200 ms timeoutはエラーではなく空配列でresolveする。mode setterはこれを検証せず後続writeへ進む。公式clientを忠実に再現するだけでは「失敗時に追加送信しない」を満たさない。

### Confirmed command sequence

正常応答時のCustom移行:

1. UI `ap`のmode選択 → `await S.setLightEffectConfig(5)`。
2. `await api.sendDeviceData(6,[22,0,0,0,1,0,5])` → Output `06 16`。
3. read結果 `response.slice(5,16)` を `a` とする。header/status/length判定なし。
4. `a[2]=5`。`await api.sendDeviceData(6,[11,a.length,0,0,...a])` → Output `06 0B`。正常な11-byte sliceならpayload offset7が05。
5. そのread完了後にconfigをreturnし、React stateを更新。UI effectはbrightness/speed/color/palette/current modeのlocal stateを更新する。追加HID setterは呼ばない。
6. この経路で `06 12` / `06 14` は送らない。

単一キー変更:

- 実際のUIは「色を選んでからキーclick」。custom中のpickerはlocal paint colorだけを更新する。一般mode用の `R` handlerはcustomなら `setLightConfig` を呼ばない。
- Lightingタブかつ `currentLightEffect.name=="custom"` のclick → `updateKeyInfoColor(paintColor,layout.index)` → local keyInfo更新 → `setKeyColorInfo` → `setKeyRGBBytes` → `sendDeviceData` → queue → `webhid_write_command` → `N.write` → `sendReport(0,payload64)`。
- 1 clickにつき `06 14` が1回。他キーRGB、全体照明、saveの追加送信なし。右clickはキー色をpickerへ取り込むだけ。
- `setKeyColorInfo` はasync宣言だが内部の `setKeyRGBBytes` をawait/returnしていない。UI更新・このメソッドの完了はHID応答確認を意味しない。queue内部はwrite/readを順番に待つ。
- `06 12` は56-byte分割のbulk setter。src内全JSで `setKeyColorsInfos` は定義1件だけ、呼び出しは見つからない。Web主chunkでも定義だけ。今回のUI経路では使わない。

mode4へ戻す公式UI sequence:

1. `setLightEffectConfig(4)` → `06 16 ... 04`。
2. 応答offset5..15を取り、配列index2を04へ変更。
3. 応答由来のconfigで `06 0B` → read待ち → UI state更新。

これは「mode4を選び直す」処理であり、以前取得した照明snapshotを保存して復元する処理ではない。元の個別RGBを復元するcallもない。

### Response requirements / Timing

| 項目 | コードから確認した挙動 |
|---|---|
| `06 16` | write完了後にread。結果のoffset5..15だけ利用。応答先頭・subcommand・status・長さ・Report IDの検証なし |
| `06 0B` | write/readをawaitするが、read結果は捨てる |
| `06 14` / `06 12` | queueはwrite/read待ち。上位setterはawaitを伝播しない |
| expected header | clientは要求しない。`AA 16` / `AA 0B` / `AA 14` は既知の `AA 0A` からの仮説に留まり、未確定 |
| Input選別 | device別bufferから次のInputを渡す。旧bufferはwrite時刻より古いものを除去するがopcodeの相関なし。別途 `AA FA` 通知listenerがあり、通知もgeneric readへ届き得る |
| timeout | readPのPromise.raceで **200 ms** 後 `[]` をresolve。SetReport自体の200 ms制限ではない。timerはread開始から |
| timeout後 | `a=[]; a[2]=mode` で長さ3になり、`06 0B 03 00 00 00 00 mode` + zerosが生成され得る。これは実験用packetとして採用しない |
| 固定delay | 対象照明経路にsleepなし。応答直後に次へ進む。queueのtimeout(ms) helperは定義されるが主chunkに呼び出しなし |
| retry | 対象経路に自動retryなし。ただしqueueはreject時にも既にqueuedされた次commandを処理する。全停止ではない |
| debounce | 単一キーclick・mode選択になし。brightness/speedはsliderのonChangeEndで送る。保存のdebounceは見つからない |

正常系のmode setterは2回のwrite/readをawaitするが、2件を不可分に予約するわけではない。他操作でqueueが積まれれば間に挟まり得る。200 ms内に応答しただけで成功statusを確認したとは扱えない。

### Exact packets

すべてReport ID **0**、以下の数字だけのdumpは各64 bytes。先頭にReport ID用00を足さない。**資料上の値であり、一切送信していない。**

Custom前段、mode5 (`06 16`):
```text
06 16 00 00 00 01 00 05 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

元mode4への前段 (`06 16`):
```text
06 16 00 00 00 01 00 04 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

続く `06 0B` の**正確な生成規則**（正常な応答長を前提）:

| Payload offset | 内容 |
|---|---|
| 0..4 | `06 0B 0B 00 00` |
| 5..6 | 直前の06 16応答のoffset5..6をそのままコピー |
| 7 | 目的mode: Customは05、復帰は04 |
| 8..15 | 直前の06 16応答のoffset8..15をそのままコピー |
| 16..63 | 00 |

**06 16の応答が未取得なので、この2つの06 0Bを完全な数値hexとして提示することはできない。** mode4の06 0A応答をmode5の06 16応答として代用してはいけない。正常時はsingleColorIndex / HSVもraw byteとして保持される。

単一キー候補: **key_index=0**（UIの最初の通常キー、物理位置未確認）をmagenta `#FF00FF`:
```text
06 14 03 00 00 00 00 00 FF 00 FF 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

キー復元は同じ06 14でoffset8..10だけを保存した元R/G/Bへ戻す。元RGBは未取得なので、完全なrollback hexはまだ作れない。全体HSV `FF FF FF` をキーRGBの白と見なして代用しない。

元の全体照明snapshotをraw replayする**候補**:
```text
06 0B 0B 00 00 01 00 04 04 02 00 00 07 FF FF FF
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

上記は取得済み11-byte configを保つ数値上のrollback候補であり、公式mode切替が必ずこの値を送るという証拠ではない。`06 0B` 単独で戻せるか、06 16前段がfirmware上必須かはUnknown。公式UIはmode変更の両方向で06 16を使う。

一般の `setLightConfig` に同じ設定を渡すとoffset12は**00固定**になり、snapshotの07を失う。HSVもUIのhex/HSV往復で再量子化され得るので、UIを経由した復元をbyte完全一致の復元としない。

先に元キーRGBを取得する将来の候補: 公式 `getKeyInfos` の最初のRGB chunk要求（最大56 bytes分、応答offset8から読む）。今回未実行:
```text
06 13 3A 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

この06 13もtransport上はOutput送信。対象layoutのkey_index_max=19なら公式clientは57 bytesを読むため2 chunk要求するが、key0の3 bytesだけなら最初のchunkに含まれる設計。応答header/長さの実機確認はまだ必要。

### 復元・Persistenceの分類

**Confirmed（clientコード）**

- modeの往復は同一setter、06 16 → 応答由来06 0B。key RGBのrestore、profile変更、layer変更、独立Save/Apply/Sync/Commitはこの経路にない。
- singleColorIndexを保持するmode setterと、zero固定の一般setterが別にある。戻す値が元snapshotと一致する保証はclientにない。
- 接続処理は `getKeyboardConfig` (06 05) → layout読込、`getLightConfig` (06 0A)、`getKeyInfos` (mapping読込に続いて06 13)、macro読込を呼ぶ。照明はデバイスから再取得し、localStorageの照明設定を再適用する経路はない。
- 主chunkのlocalStorage書き込み2件はmacro_arr / macro_action_list。Saveはmacro.jsonファイルexport。別画面にfactory reset / firmware更新はあるが照明setterから呼ばない。
- `setCurrentProfile` (06 FB) は別UI操作。今回のpacketにprofile/layer番号はない。

**Strong inference**

- Customを抜けても変更したキーRGBはclientから戻されないため、次にCustomへ入った際に変更が残る可能性がある。通常modeへの切替によって個別RGBの表示を隠すだけでは完全rollbackにならない。
- mode4選択は潮汐effectの再開を意図した処理。ただし元の明るさ・速度・位相・内部状態まで戻るという証明ではない。
- UIは独立saveボタンなしで設定を反映する設計。これは即時のデバイス処理を意図する証拠であり、RAM-onlyの証拠ではない。

**Unknown**

- 06 16が返すのはmode別保存値かdefaultか、06 16自体に変更副作用があるか。
- 実機setterの成功/失敗headerとstatus、mode4への復帰条件、元07とHSVが必須か。
- flash/EEPROMへの即時保存・firmware内部debounce・電源断保持。clientに独立commitがないことから判定不可。
- profile/layer間共有、他modeの保存領域への影響、キーRGB変更以外のfirmware内部副作用。
- 再接続時のreadは確認できるが、電源断後も同じ値が読めるかは未検証。firmware更新用binaryの存在をこの個体の保存実装の証拠にはしない。

### Recommended live test — 今回未実行

現段階の最小リスクの次段階は、Serial `592B14678182` のみで **06 13を1回読み、key_index0の元RGBを確保すること**。これは別途許可された将来の実験であり、今回送らない。空/短い/対応不明な応答なら停止する。

変更実験の条件付き設計は以下。ただし現時点ではrollback全文と応答条件が揃っておらず、実行可能確定版ではない。

1. VID/PID/Product/Serial/FF00:2/Report ID0/64Bを一意に照合。最新の照明・元RGBを保存し、rollback全payloadを数値で事前提示する。
2. 06 16(mode5)を1回。十分な長さ・対応が確認できた応答だけで06 0B(mode5)を構築し1回。各応答が失敗・不明なら追加送信なしで停止。公式のempty-response続行は模倣しない。
3. key_index0にmagentaを06 14で1回。ほかのキーRGBには触れない。ただしglobal mode変更は他キーの見え方も変えるため、「全体の外見も1キー以外不変」は保証できない。
4. 正常応答後3秒目視（3秒は試験提案で、公式delayではない）。まず同じ06 14で元RGBを戻す。その後公式mode4 sequence（06 16 → 応答由来06 0B）。
5. mode4の応答由来configが元snapshotと一致しない場合、公式選択sequenceだけで完全復元できるとは判断しない。上記raw snapshot replayの追加使用は未検証であり、この設計へ暗黙に追加しない。

「失敗時は一切追加送信しない」と「変更後のどんな失敗でも数秒後に自動復元」は両立しない。前者に従う場合、変更後のtimeoutではrollbackも送れず変更状態が残り得る。現時点で条件を満たす保証付きの変更実験を提案したとは扱わない。

### 追跡可能な根拠 / 検証

前掲hashで固定したP（UTF-8 byte offset、0始まり）:

| Offset | 根拠 |
|---|---|
| 0x1E21 | readP用Promise.race / 200 ms / resolve([]) |
| 0x5B9F | flushQueue: response待ち、reject後もqueue継続 |
| 0x7265 | async setLightEffectConfig: 06 16 → slice → mode override → 06 0B |
| 0x12F1C | connectKeyboard: device設定の再読込 |
| 0x13772 | updateKeyInfoColor: local state更新から単一setterへ |
| 0x1918D | onChangeColor: React stateのみ |
| 0x1CE1F | custom判定・キーclick / 右click経路 |
| 0x1E1C2 | Lighting UI: mode await、pickerのcustom guard、slider onChangeEnd |

App / WebのsetLightEffectConfigとsetKeyColorInfoのmethod文字列一致を確認。双方に同じ200 ms timeoutを確認。src内全JSでbulk setter名は定義1件だけ。保存済みファイルをPythonの文字列として読んだだけで、メーカーJavaScriptを実行していない。

AGENTS.md / AAL exploration context読了、context build成功。git status / branch確認、git pull --ff-onlyはAlready up to date。開始時の既存変更は保持し、今回の編集は本資料への追記のみ。コード変更・commit・build・HID probe実行なし。

**今回、Output / Feature Reportを一切送信していない。メーカーアプリ・Web設定アプリを起動していない。メーカーアプリをインストールしていない。RGB / mode / firmware操作なし。**

## 2026-09-04: USB reconnect retention — user observation

The user reports that the LED colors did not change after unplugging and reconnecting USB at home.

- Confirmed (user observation): color retention across USB unplug/reconnect. No HID requests or manufacturer apps were run by the assistant in this reporting turn.
- Strong inference: the preceding mode/bulk RGB setup persisted in device-side nonvolatile storage. Do not assume these settings are RAM-only.
- Unknown: storage medium (flash/EEPROM), immediate versus delayed commit, endurance, and which command triggers persistence. This observation after a sequence containing 06 12/06 0B/06 16 does not isolate persistence of 06 14 alone.
- The report does not specify unplug duration, per-Serial test coverage, or raw post-reconnect values. Do not promote it to verified 57-byte equality or independently verified power-cycle tests on each of the three units.

This observation does not establish suitability for high-frequency LED writes.

## 2026-09-05: official mode field validation

Static call-site review plus a one-device live test established that the target layout's modes 1...4 use a global palette/single-HSV selector, not the Custom per-key RGB table. The official UI checkbox maps to config offset 11 (`0` palette, `1` HSV at offsets 13...15). Mode 3 lights the pressed key but uses the global color source; mode 2 can breathe all keys in a fixed HSV color. No effect target-key or key-mask field was found. Offset 12 is not a direct target mask: the official setter transmits zero and the device read back `FF` after selecting red.

Full response comparison and user visual observations are recorded in `docs/evidence/koolertron-official-mode-fields-20260905.md`. The device was returned to mode 5. No runtime integration decision is made by this evidence update.

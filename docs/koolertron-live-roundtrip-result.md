# Koolertron key0 live RGB round trip — 2026-09-04

## Result

Serial 592B14678182のみ、14:11:47〜14:11:52 JSTに実施。
SDINNOVATION / SIDE-KEYBOARD / VID 0816 / PID 246E / Usage FF00:0002 / Report ID0 / 64-byte Outputを照合し、matching interfaceが1つであることを確認。

**通信上PASS**。pre/postの照明・RGB getter応答は、それぞれ64 bytes全体が完全一致。最終mode4 / key0 #00FF00。全10回のSetReportは0x00000000。各段階1回、retryなし。全InputもReport ID0 / 64 bytes / IOReturn 0。

magenta要求のSetReport開始から5秒保持しgreenへ復元。物理的な発光開始時刻や見え方は観測していない。現地目視結果待ち。

## Baseline / post-check

照明config: type1 / mode4 / brightness4 / speed2 / direction0 / colorSwitch0 / singleColorIndex7 / HSV FF FF FF。
キー0〜3: getter response[8+3*k...10+3*k]は全て00 FF 00。
RGB取得は最初の56-byte chunkだけ。19-indexの57 bytes全体を取得したものではない。

## Requests / responses

以下は実際のログから転記した全payload。すべて64 bytes、Report ID0。latencyはSetReport開始からInput callback処理まで。

### pre-light

Request:

```text
06 0A 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Response (2.017 ms):

```text
AA 0A 0B 00 00 01 00 04 04 02 00 00 07 FF FF FF
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

### pre-rgb

Request:

```text
06 13 3A 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Response (1.795 ms):

```text
AA 13 3A 00 00 00 00 00 00 FF 00 00 FF 00 00 FF
00 00 FF 00 00 FF 00 00 FF 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

### custom-prepare

Request:

```text
06 16 00 00 00 01 00 05 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Response (1.823 ms):

```text
AA 16 0B 00 00 01 00 05 04 02 00 00 07 FF FF FF
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

### custom-set

Request:

```text
06 0B 0B 00 00 01 00 05 04 02 00 00 07 FF FF FF
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Response (7.882 ms):

```text
AA 0B 01 00 00 01 00 05 04 02 00 00 07 FF FF FF
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

### magenta

Request:

```text
06 14 03 00 00 00 00 00 FF 00 FF 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Response (6.625 ms):

```text
AA 14 01 00 00 00 00 00 FF 00 FF 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

### green-rollback

Request:

```text
06 14 03 00 00 00 00 00 00 FF 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Response (7.133 ms):

```text
AA 14 01 00 00 00 00 00 00 FF 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

### tidal-prepare

Request:

```text
06 16 00 00 00 01 00 04 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Response (1.867 ms):

```text
AA 16 0B 00 00 01 00 04 04 02 00 00 07 FF FF FF
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

### tidal-set

Request:

```text
06 0B 0B 00 00 01 00 04 04 02 00 00 07 FF FF FF
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Response (8.045 ms):

```text
AA 0B 01 00 00 01 00 04 04 02 00 00 07 FF FF FF
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

### post-light

Request:

```text
06 0A 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Response (2.110 ms):

```text
AA 0A 0B 00 00 01 00 04 04 02 00 00 07 FF FF FF
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

### post-rgb

Request:

```text
06 13 3A 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Response (2.063 ms):

```text
AA 13 3A 00 00 00 00 00 00 FF 00 00 FF 00 00 FF
00 00 FF 00 00 FF 00 00 FF 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

## Byte diff / response interpretation

- pre-light vs post-light: 差分なし、64/64 bytes一致。
- pre-rgb vs post-rgb: 差分なし、64/64 bytes一致。
- 06 16(mode5)応答は AA 16 0B、configは元configのmodeだけ05。そのoffset5..15をコピーして06 0Bを生成した。
- 06 16(mode4)応答は AA 16 0B、configは元snapshotと同じ。response由来06 0Bで元のsingleColorIndex07 / HSV / brightness / speed / directionを保持した。
- 06 0B応答は AA 0B 01、06 14応答は AA 14 01。offset2の01を正式なsuccess statusと断定しない。今回post-check復元成功と併せた観測である。
- 06 14応答offset8..10は要求RGBと一致。これは発光自体の目視確認の代わりにならない。

## Classification

Confirmed:

- 対象1個体のVendor interfaceに10個の許可済みOutputのみ送信し全て通信成功。
- baseline完全一致後にmutation開始。06 16→応答由来06 0Bを両方向で実施。
- magenta要求から5秒後green要求。mode4復帰後、照明/RGBの取得chunkはpre/post全byte一致。
- brightness / speed / directionは送信したconfigでも保持。06 12、別key/RGB/Serial、Feature、firmware送信なし。

Visual confirmation pending:

- 対象の物理key0がmagentaになったか、greenへ戻ったか、潮汐表示へ戻ったか。
- 他キーの見え方。Customへのglobal mode切替自体は全体の発光に影響し得る。

Unknown:

- RAM/flash、電源断保持、EEPROM寿命、profile/layer共有、アニメーション位相。
- setter responseの01の厳密なstatus定義、エラー時の応答体系。
- 今回の成功を高頻度runtime同期の安全性へ一般化しない。

## Implementation / safety

変更はLED専用probe内。LiveRGBTest.swiftに固定sequenceを追加、main.swiftに厳密な--live-rgb-roundtrip --serial 592B14678182 entryを追加。
任意payload/mode/key/color引数なし。identityを送信ごとに再検査。各stepは1回だけ、response待ちは最大1秒、64-byte/Report ID0/AA/subcommand対応をgateにする。06 16はconfig length0Bとbrightness/speed/direction保持も確認。

Custom 06 0B試行後はrollbackを優先。Custom応答なしならmagentaをskipしてgreen→mode4復帰を試みる。mode4用06 16の有効応答がない場合は推測06 0Bを送らない。今回これらのfailure分岐は実機では発生せず、HIDなし模擬transportで確認した。

メーカーアプリ/Web設定アプリ起動なし、インストールなし。試験を再実行しない。

Raw log: [evidence](evidence/koolertron-live-roundtrip-20260904-592B14678182.log)

SHA-256: `753befc2d8ccd0a85387e8c89455dc50fa34fb75cdc2bd7c55aba27e1157f18a`

## Verification

- AGENTS.md / project / next / exploration context読了、context build成功。
- branch: codex/koolertron-led-probe。git pull --ff-only: Already up to date。
- swift build成功（追加時のSet indexビルドエラーをprobe内で修正後）。
- HIDなし模擬transportで10項目の順序・rollback・禁止値gate検証成功。
- swift test: 35 tests / 0 failures。swift run overcue-checks: 405 passed。
- ./Scripts/verify-macos.sh: exit0、macOS universal build / codesign検証成功。
- aal doctor: 0 failures / 0 warnings。git diff --check成功、git status --short確認済み。
- 本体App / Bridge / Runtime / ActionLayer / config schemaのソース変更なし。commitなし。

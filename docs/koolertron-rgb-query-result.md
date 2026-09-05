# Koolertron RGB query — 2026-09-04

## Send / response

Serial `592B14678182` / SDINNOVATION / SIDE-KEYBOARD / VID 0816 / PID 246E / FF00:0002 / Output Report ID 0 / 64 bytesを送信直前に確認。

`swift run overcue-led-probe --get-rgb --serial 592B14678182` を1回実行。
固定要求は `06 13 3A` + 61 zero bytes（RGB byte offset 0の最初のchunkのみ）。
IOHIDDeviceSetReport `0x00000000`、成功。Input Report ID 0 / 64 bytes。
SetReport開始からcallback処理まで **2.709 ms**。

```text
AA 13 3A 00 00 00 00 00 00 FF 00 00 FF 00 00 FF
00 00 FF 00 00 FF 00 00 FF 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

## Parser / Current RGB

SDTech Option 1.0.3のsrc主chunk `getKeyInfos(e,a)` を再確認した。
要求args[0]=19 / args[1]=58 / args[2..3]=chunk*56 little endian。
応答offset8から最大56 bytesをRGB配列へコピーし、key kのRGBを配列[3*k..3*k+2]から読む。
したがって最初のchunkではresponse[8+3*k..10+3*k]に対応。

| key_index | Response offsets | R | G | B | Hex |
|---|---|---|---|---|---|
| 0 | 8–10 | 0 | 255 | 0 | #00FF00 |
| 1 | 11–13 | 0 | 255 | 0 | #00FF00 |
| 2 | 14–16 | 0 | 255 | 0 | #00FF00 |
| 3 | 17–19 | 0 | 255 | 0 | #00FF00 |

Confirmed: raw値、長さ64、header `AA 13 3A 00 00 00 00 00`、request/responseのsubcommand13とlength欄3Aの一致、静的parserによる上表の値。
Strong inference: この応答が要求したRGB配列chunk0で、key0の元色は00 FF 00。実際に各LEDが緑に光っているという意味ではない（現在mode4）。
Unknown: AAの正式意味、独立status欄、reserved bytes、firmware保存先と物理LED indexの対応。

| Offset | 構造 |
|---|---|
| 0 | AA、既知getter応答と共通のprefix |
| 1 | 13、要求subcommandと一致 |
| 2 | 3A、要求length欄と一致。clientはこの値で成功を判定しない |
| 3–4 | 00 00、chunk offset0と整合（実機では今回0のみ確認） |
| 5–7 | 00 00 00、意味未確定 |
| 8–63 | getterがRGB配列として扱う56 bytes |

19-index layout全体は57 bytesであり、今回は最初の56 bytesだけ。最後の1 byteを得る第2chunkは送信していない。key0〜3の12 bytesはすべて含まれる。

## key_index=0 rollback packet — 未送信

Report ID 0 / 64 bytes。単一キーsetter formatに取得した00 FF 00を入れたもの。実機setterの受理は未検証。

```text
06 14 03 00 00 00 00 00 00 FF 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

## Future live-test readiness

| 項目 | 状態 |
|---|---|
| 元Lighting config | 前回06 0Aで取得済み: 01 00 04 04 02 00 00 07 FF FF FF。今回再取得していない |
| Custom前段 | 06 16 00 00 00 01 00 05 + zero padding、静的確定・未送信 |
| Custom後続06 0B | 06 16応答依存。数値payload未確定 |
| key0 magenta | 06 14 03 00 00 00 00 00 FF 00 FF + zeros、静的確定・未送信 |
| key0元RGB rollback | 本資料の64 bytesとして完成。未送信 |
| mode4復帰 | 06 16(mode4)→応答由来06 0B、静的順序は確定。元snapshotと同じ値になるか未確認 |
| 各段階の期待response | getter0A/13のみ実機確認。16/0B/14のheader・status・成功条件は未確認 |

**変更試験の準備がすべて揃ったとは判定しない。** キーrollbackの値は揃ったが、mode移行・復帰の応答依存packet、各setter成功条件、永続化・副作用が未確定。失敗時の追加送信禁止と自動rollbackの競合も残る。

## Repository / safety

既存CLIにはRGB getterがなかったため、Sources/OverCUELightingProbe/main.swiftだけに固定--get-rgbを追加した。06 0Aと06 13は排他的、RGB getterのSerialは592B14678182限定。固定payloadのoffline検証、不正Serialの送信前拒否を確認。任意payload、chunk指定、setterは追加していない。

今回Output送信は06 13 getterの1回だけ。retry・第2chunk・別Serial・06 0A再送・06 0B/12/14/16・Feature送信なし。RGB/mode/brightness/firmware変更操作なし。メーカーアプリ・Web設定アプリの起動なし。rollback packetは文書作成のみ。

Raw evidence: [query log](evidence/koolertron-rgb-query-20260904-592B14678182.log)

SHA-256: `dc8e6d72d6c9ad73057e5dcf9a9884f5bec352a9508287a387ab547b45e7475f`

## Build / verification

- `aal context build --mode exploration`: 成功。生成contextは前回読了済みcontextとbyte一致を確認。
- `git status` / `git branch --show-current`: 指定branch。既存変更を保持。
- `git pull --ff-only`: Already up to date.
- `swift build`: 変更前・変更後とも成功。
- `swift test`: 成功。
- `swift run overcue-checks`: 405 checks成功。
- `./Scripts/verify-macos.sh`: macOS build / Universal Binary / codesign検証成功。
- `aal doctor`: 0 failures / 0 warnings。
- `git diff --check`: 成功。`git status --short`確認済み。commitなし。

# OverCUE

[日本語](#日本語) | [English](#english)

## 日本語

OverCUEは、XPPen ACK05のダイヤルとキー入力をDJソフト向けの操作へ変換するmacOS用CLIアプリケーションです。現在はrekordboxのCUE仕込みを主用途とし、Freeプランで利用できるマウス・キーボード方式を実機確認済みです。

### 必要環境

- macOS 13以降
- Swift 6以降
- XPPen ACK05（VID `0x28BD` / PID `0x0202`）
- rekordbox 7
- ターミナルへの「入力監視」と「アクセシビリティ」権限

XPPenPenTabletがACK05入力を消費または変換する場合は停止してください。権限を変更した後はターミナルを再起動します。

### 起動

Freeプランで推奨するマウス方式:

```sh
swift run overcue --output mouse
```

ビルド済みバイナリから起動する場合:

```sh
.build/debug/overcue --output mouse
```

初回はポインタをrekordboxの拡大波形上へ置き、K8を押しながらK1を押して波形位置を保存します。その後、ダイヤルを回すと波形をドラッグします。操作終了後、ポインタは元の位置へ戻ります。

- 低速時: 1px/detent
- 高速時: 最大20px/detent
- 4次加速カーブ
- 150ms入力がなければドラッグを解放

調整例:

```sh
swift run overcue --output mouse --drag-pixels 0.5
swift run overcue --output mouse --max-drag-pixels 6
swift run overcue --output mouse --no-acceleration
swift run overcue --output mouse --invert-dial
swift run overcue --output mouse --idle-ms 180
```

rekordboxのモード指定:

```sh
swift run overcue --output mouse --rekordbox-mode export
swift run overcue --output mouse --rekordbox-mode performance
```

Exportが初期値です。OverCUEは起動時にrekordboxのKeyMappings XMLを読み、現在のショートカットをcommandIdから解決します。未割り当ての操作について代替キーは推測しません。

### デフォルトキーマップ

ACK05は縦向きで使用します。

| キー | 操作 |
| --- | --- |
| K1 | Hot Cue C |
| K2 | Delete Memory Cue |
| K3 | Jump Forward（長押しリピート・加速） |
| K4 | Hot Cue B |
| K5 | Set Memory Cue |
| K6 | Jump Backward（長押しリピート・加速） |
| K7 | Quantize ON/OFF（コード修飾キー） |
| K8 | Hot Cue A（コード修飾キー） |
| K9 | Cue（押下中のみ再生、解放時にCUE位置へ戻る） |
| K10 | Play/Pause |
| K8+K1 | 波形位置を保存 |
| K7+K8 | Hot Cue Aを削除 |
| K7+K4 | Hot Cue Bを削除 |
| K7+K1 | Hot Cue Cを削除 |
| K7+K3 | 次のMemory Cueへ移動 |
| K7+K6 | 前のMemory Cueへ移動 |

K1〜K10の任意の異なる2キーをコードとして設定できます。`K5+K1`ではK5が修飾キー、K1がトリガーです。修飾キーを先に保持してからトリガーを押します。

### 外部設定

初回起動時に次のファイルを生成します。

```text
~/Library/Application Support/OverCUE/config.json
```

設定version 3では、表示名ではなく安定したAction IDを保存します。各プロファイルは波形位置、キーマップ、コードマップを持ち、`deviceProfiles`でACK05の`PhysicalDeviceUniqueID`と対応付けます。

```json
{
  "version": 3,
  "defaultProfile": "default",
  "deviceProfiles": {
    "DEVICE-PHYSICAL-UUID": "default"
  },
  "profiles": {
    "default": {
      "waveformPosition": { "x": 640.5, "y": 212.25 },
      "keyMap": {
        "K1": "hot_cue_3",
        "K2": "delete_memory_cue",
        "K3": "jump_forward",
        "K4": "hot_cue_2",
        "K5": "set_memory_cue",
        "K6": "jump_backward",
        "K7": "quantize",
        "K8": "hot_cue_1",
        "K9": "cue",
        "K10": "play_pause"
      },
      "chordMap": {
        "K8+K1": "capture_waveform_position",
        "K7+K8": "delete_hot_cue_1",
        "K7+K4": "delete_hot_cue_2",
        "K7+K1": "delete_hot_cue_3",
        "K7+K3": "call_next_memory_cue",
        "K7+K6": "call_previous_memory_cue"
      }
    }
  }
}
```

version 1または2の設定は、`config.vN.backup.json`へバックアップした後、version 3へ自動移行します。未知の旧操作名は該当項目だけ無効化し、その他の設定は保持します。JSON編集後はOverCUEを再起動してください。

別の設定ファイルを使う場合:

```sh
swift run overcue --output mouse --config ~/Desktop/overcue-test.json
```

### Action Layer

OverCUEは、物理入力、論理Action、対象ソフト固有Adapter、出力処理を分離しています。

```text
ACK05 HID Input
  → InputActionResolver
  → ActionEvent
  → Internal Handler / Rekordbox Adapter
  → Keyboard / Mouse / MIDI Output
```

Cue保持やJump長押しはActionの特性として処理されるため、キーマップを変更しても操作へ追従します。rekordbox固有のcommandIdは`RekordboxActionAdapter`だけが保持します。

### MIDIモード

実験的なMIDI方式では、DDJ-SX形式のJogTouch/JogScratchをCoreMIDI仮想ソースへ出力します。

```sh
swift run overcue
```

Deck 1の出力:

```text
最初の回転       90 36 7F  JogTouch ON
時計回り         B0 22 41  JogScratch +1
反時計回り       B0 22 3F  JogScratch -1
150ms入力なし    90 36 00  JogTouch OFF
```

rekordbox Freeプランでは接続機器制限があるため、通常運用にはマウス方式を推奨します。

### 診断とテスト

```sh
swift run overcue-probe
swift run overcue-probe --seize
swift run overcue-checks
```

`--seize`はACK05を排他的に開きます。`--shared`や通常のprobeではACK05の工場出荷時ショートカットがmacOSへ届く場合があります。`--all`は全HID機器を表示しますが、安全のため`--seize`とは併用できません。

詳しい現行仕様は[docs/current-spec.md](docs/current-spec.md)、設計経緯を含む仕様は[docs/spec.md](docs/spec.md)を参照してください。

---

## English

OverCUE is a macOS CLI application that converts XPPen ACK05 dial and key input into controls for DJ software. Its primary use case is cue preparation in rekordbox. The Free-plan mouse and keyboard workflow has been verified with real hardware.

### Requirements

- macOS 13 or later
- Swift 6 or later
- XPPen ACK05 (VID `0x28BD` / PID `0x0202`)
- rekordbox 7
- Input Monitoring and Accessibility permissions for the terminal

Stop XPPenPenTablet if it consumes or rewrites ACK05 input. Restart the terminal after changing privacy permissions.

### Running OverCUE

Recommended Free-plan mouse mode:

```sh
swift run overcue --output mouse
```

Using the built executable:

```sh
.build/debug/overcue --output mouse
```

On first use, place the pointer over the enlarged rekordbox waveform, hold K8, and press K1 to save the drag position. Turning the dial then drags the waveform. The pointer returns to its original position after each operation.

- Slow movement: 1 px/detent
- Fast movement: up to 20 px/detent
- Fourth-power acceleration curve
- Drag release after 150 ms of inactivity

Tuning examples:

```sh
swift run overcue --output mouse --drag-pixels 0.5
swift run overcue --output mouse --max-drag-pixels 6
swift run overcue --output mouse --no-acceleration
swift run overcue --output mouse --invert-dial
swift run overcue --output mouse --idle-ms 180
```

Select the rekordbox shortcut mode explicitly when needed:

```sh
swift run overcue --output mouse --rekordbox-mode export
swift run overcue --output mouse --rekordbox-mode performance
```

Export is the default. At startup, OverCUE reads rekordbox's KeyMappings XML and resolves the current shortcut for each commandId. It never guesses a fallback for an unassigned action.

### Default key map

The ACK05 is used vertically.

| Key | Action |
| --- | --- |
| K1 | Hot Cue C |
| K2 | Delete Memory Cue |
| K3 | Jump Forward (hold to repeat and accelerate) |
| K4 | Hot Cue B |
| K5 | Set Memory Cue |
| K6 | Jump Backward (hold to repeat and accelerate) |
| K7 | Quantize ON/OFF (chord modifier) |
| K8 | Hot Cue A (chord modifier) |
| K9 | Cue (play while held, return to the cue position on release) |
| K10 | Play/Pause |
| K8+K1 | Save waveform position |
| K7+K8 | Delete Hot Cue A |
| K7+K4 | Delete Hot Cue B |
| K7+K1 | Delete Hot Cue C |
| K7+K3 | Call Next Memory Cue |
| K7+K6 | Call Previous Memory Cue |

Any two different keys from K1 through K10 can form a chord. In `K5+K1`, K5 is the modifier and K1 is the trigger. Hold the modifier before pressing the trigger.

### External configuration

OverCUE creates this file on first launch:

```text
~/Library/Application Support/OverCUE/config.json
```

Configuration version 3 stores stable Action IDs instead of display labels. Each profile owns its waveform position, key map, and chord map. `deviceProfiles` associates an ACK05 `PhysicalDeviceUniqueID` with a profile. See the Japanese example above for the complete JSON structure.

Version 1 and 2 files are backed up as `config.vN.backup.json` and migrated automatically. Unknown legacy action labels disable only the affected entry; all other settings are preserved. Restart OverCUE after editing JSON.

Use an alternate file with:

```sh
swift run overcue --output mouse --config ~/Desktop/overcue-test.json
```

### Action Layer

OverCUE separates physical input, logical actions, target-specific adapters, and output execution.

```text
ACK05 HID Input
  → InputActionResolver
  → ActionEvent
  → Internal Handler / Rekordbox Adapter
  → Keyboard / Mouse / MIDI Output
```

Cue hold and accelerating Jump repeat are Action behaviors, so they follow mapping changes. Only `RekordboxActionAdapter` knows rekordbox-specific commandIds.

### MIDI mode

The experimental MIDI mode publishes DDJ-SX-style JogTouch/JogScratch messages through a CoreMIDI virtual source.

```sh
swift run overcue
```

Deck 1 output:

```text
First rotation:     90 36 7F  JogTouch ON
Clockwise detent:   B0 22 41  JogScratch +1
Counterclockwise:   B0 22 3F  JogScratch -1
After 150 ms idle:  90 36 00  JogTouch OFF
```

Because rekordbox Free restricts connected-device control, mouse mode is recommended for normal operation.

### Diagnostics and tests

```sh
swift run overcue-probe
swift run overcue-probe --seize
swift run overcue-checks
```

`--seize` opens the ACK05 exclusively. In shared mode or the normal probe, factory shortcuts may still reach macOS. `--all` displays every HID device and cannot be combined with `--seize` for safety.

See [docs/current-spec.md](docs/current-spec.md) for the current detailed specification and [docs/spec.md](docs/spec.md) for the broader design history.

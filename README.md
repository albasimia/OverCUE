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

SwiftUI設定画面:

```sh
swift run OverCUE
```

配布用アプリを作成して起動する場合:

```sh
./Scripts/build-app.sh
open dist/OverCUE.app
```

`build-app.sh`はGUI本体と同梱CLIを`arm64 + x86_64`のUniversal Binaryとして生成します。Apple Silicon MacとIntel Macの両方で同じ`OverCUE.app`を利用でき、最低対応OSはmacOS 13です。ビルド時に両アーキテクチャが含まれていることを自動検証します。

Apple Development証明書がある場合は、`CODESIGN_IDENTITY="Apple Development: ..." ./Scripts/build-app.sh`のように指定すると、アプリ更新後もmacOSの権限を維持しやすくなります。証明書を指定しない開発ビルドはアドホック署名のため、再ビルドしたアプリへ差し替えた直後だけ再許可が必要になる場合があります。

`OverCUE.app`は入力用の`overcue-cli`を内包しています。起動中はメニューバーに白抜きのOverCUEアイコンが表示され、メニューからACK05入力の有効・無効、設定画面の再表示、アプリ終了を操作できます。ウィンドウを閉じても、ACK05入力が有効ならバックグラウンドで動作を継続します。

Xcodeでは`Package.swift`を開き、スキーム`OverCUE`を選んで実行します。設定画面は選択中のrekordboxキーマップを読み込み、カテゴリ別の3カラム一覧、検索、ACK05筐体との選択連動、複合キーの同時ハイライト、4グループ表示、90度単位の筐体回転を提供します。右カラムの編集ボタンからACK05を直接入力して、デフォルトプロファイルの割り当てを保存できます。

OverCUE起動中は`overcue-cli`相当の入力ブリッジも自動起動します。割り当て編集時だけ一時停止し、保存またはキャンセル後に再開します。キーおよびダイヤルの出力はrekordboxが最前面にある間だけ有効です。アクセシビリティ権限の要求はBundle IDを持つOverCUE本体だけが初回に行い、内蔵CLIの再起動では要求しません。

CLIブリッジ:

Freeプランで推奨するマウス方式:

```sh
swift run overcue-cli --output mouse
```

ビルド済みバイナリから起動する場合:

```sh
.build/debug/overcue-cli --output mouse
```

初回はポインタをrekordboxの拡大波形上へ置き、K8を押しながらK1を押して波形位置を保存します。その後、ダイヤルを回すと波形をドラッグします。操作終了後、ポインタは元の位置へ戻ります。

- 低速時: 1px/detent
- 高速時: 最大20px/detent
- 4次加速カーブ
- 150ms入力がなければドラッグを解放

調整例:

```sh
swift run overcue-cli --output mouse --drag-pixels 0.5
swift run overcue-cli --output mouse --max-drag-pixels 6
swift run overcue-cli --output mouse --no-acceleration
swift run overcue-cli --output mouse --invert-dial
swift run overcue-cli --output mouse --idle-ms 180
```

rekordboxのモード指定:

```sh
swift run overcue-cli --output mouse --rekordbox-mode export
swift run overcue-cli --output mouse --rekordbox-mode performance
```

Exportが初期値です。OverCUEは起動時にrekordboxの設定とKeyMappings XMLを検索し、選択中のマッピングと現在のショートカットをcommandIdから解決します。F1〜F20や標準プリセットの記号キーにも対応し、未知のキー表現はその割り当てだけをスキップします。未割り当ての操作について代替キーは推測しません。

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
| K7+K2 | グループを昇順に切り替え（1→2→3→4→1） |
| K7+K5 | グループを降順に切り替え（1→4→3→2→1） |
| K7+ダイヤル左 | rekordboxのピッチベンド − |
| K7+ダイヤル右 | rekordboxのピッチベンド ＋ |

K1〜K10の任意数（2〜10個）の異なるキーをコードとして設定できます。`K7+K8+K1`ではK7とK8が修飾キー、K1がトリガーです。修飾キーを先に保持してからトリガーを押します。ダイヤルの左右も独立した入力としてActionへ割り当てられ、初期設定はJog Search左／右です。

ボタンを1つ以上保持してダイヤルを回す操作も、左右それぞれ独立してActionへ割り当てられます。割り当て時に同じボタン／コード／ダイヤル操作が既存機能で使用されている場合は、ダイアログで上書きを確認します。コードや保持＋ダイヤルの修飾ボタンがCueやJumpなどの長押し機能と競合する場合は保存せず、赤いトーストで理由を表示します。更新成功は緑、入力待ちや状態変更はグレーのトーストで画面右下に表示します。

デバイスマップのキーをクリックした場合は、同時押しより単体キーの割り当てを優先してショートカット一覧を選択します。OverCUE表示中にACK05実機を押すと、押下中のキーだけを緑でハイライトし、解放時に元の表示へ戻します。

### 外部設定

初回起動時に次のファイルを生成します。

```text
~/Library/Application Support/OverCUE/config.json
```

設定version 6では、表示名ではなく安定したAction IDまたはrekordbox command IDを保存します。各プロファイルは波形位置と、グループ1〜4ごとのキー・コード・ダイヤルマップを持ち、`deviceProfiles`でACK05の`PhysicalDeviceUniqueID`と対応付けます。初期状態はグループ1がPERFORMANCE / Deck 1、グループ2がPERFORMANCE / Deck 2、グループ3がEXPORT / Deck 1です。デフォルトマップの原本は`Sources/OverCUECore/Resources/DefaultKeyMapping.json`に分離されています。

```json
{
  "version": 6,
  "defaultProfile": "default",
  "deviceProfiles": {
    "DEVICE-PHYSICAL-UUID": "default"
  },
  "profiles": {
    "default": {
      "waveformPosition": { "x": 640.5, "y": 212.25 },
      "groupMappings": {
        "1": {
          "rekordboxMode": "performance",
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
            "K7+K2": "cycle_group",
            "K7+K5": "cycle_group_backward"
          },
          "dialMap": {
            "counterclockwise": "jog_search_left",
            "clockwise": "jog_search_right"
          },
          "dialChordMap": {
            "K7+DIAL_LEFT": "rekordbox:3050",
            "K7+DIAL_RIGHT": "rekordbox:304f"
          }
        },
        "2": {
          "rekordboxMode": "performance",
          "keyMap": {
            "K10": "rekordbox:3106"
          },
          "chordMap": {},
          "dialMap": {
            "counterclockwise": "jog_search_left",
            "clockwise": "jog_search_right"
          },
          "dialChordMap": {
            "K7+DIAL_LEFT": "rekordbox:3150",
            "K7+DIAL_RIGHT": "rekordbox:314f"
          }
        },
        "3": {
          "rekordboxMode": "export",
          "keyMap": { "K10": "play_pause" },
          "chordMap": {}, "dialMap": {}, "dialChordMap": {}
        }
      }
    }
  }
}
```

version 1〜5の設定は、`config.vN.backup.json`へバックアップした後、version 6へ自動移行します。従来の割り当ては保持し、旧デフォルト構成の未使用グループには新しいDeck別マップ、Pitch Bend、昇順／降順グループ切り替えを追加します。未知の旧操作名は該当項目だけ無効化し、その他の設定は保持します。JSON編集後はOverCUEを再起動してください。

### 表示言語

macOSのOverCUEメニューから「設定」を開き、日本語、English、简体中文を切り替えられます。言語設定は保存され、画面、メニュー、OverCUE独自機能名、トーストへ即時反映されます。翻訳辞書は`Sources/OverCUEApp/Resources/Localization`にあります。rekordbox由来の機能名は、rekordboxのキーマッピングファイルに記録された言語で表示します。

`rekordboxMode`はグループごとに`export`または`performance`を保存します。GUIとCLIのグループは双方向に同期し、グループ変更時はそのグループに保存されたモードへ自動的に切り替わります。ACK05からモードを変更した場合も現在グループへ保存され、GUIのPickerとメニューバーへ反映されます。

別の設定ファイルを使う場合:

```sh
swift run overcue-cli --output mouse --config ~/Desktop/overcue-test.json
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
swift run overcue-cli
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

SwiftUI settings window:

```sh
swift run OverCUE
```

Build and launch the distributable application:

```sh
./Scripts/build-app.sh
open dist/OverCUE.app
```

`OverCUE.app` bundles its `overcue-cli` input helper. A white template OverCUE icon appears in the menu bar while the app is running. Its menu can enable or disable ACK05 input, reopen the settings window, or quit the app. Closing the window leaves enabled ACK05 input running in the background.

In Xcode, open `Package.swift`, select the `OverCUE` scheme, and run it. The settings window reads the selected rekordbox mapping and provides a searchable, categorized three-column list, OverCUE-specific actions at the top, selection synchronization with the ACK05 device map, arbitrary multi-key chord highlighting, dial mappings, four group tabs, conflict-aware assignment, toast notifications, and 90-degree device rotation. Use the edit button in the right column and press an ACK05 key/chord or turn the dial to save the default-profile assignment.

OverCUE automatically starts the `overcue-cli` input bridge. It pauses only while capturing a new ACK05 assignment and resumes after saving or canceling. Key and dial output is active only while rekordbox is frontmost. Only the bundled OverCUE application requests Accessibility permission on first launch; restarting its CLI helper does not prompt again.

CLI bridge:

Recommended Free-plan mouse mode:

```sh
swift run overcue-cli --output mouse
```

Using the built executable:

```sh
.build/debug/overcue-cli --output mouse
```

On first use, place the pointer over the enlarged rekordbox waveform, hold K8, and press K1 to save the drag position. Turning the dial then drags the waveform. The pointer returns to its original position after each operation.

- Slow movement: 1 px/detent
- Fast movement: up to 20 px/detent
- Fourth-power acceleration curve
- Drag release after 150 ms of inactivity

Tuning examples:

```sh
swift run overcue-cli --output mouse --drag-pixels 0.5
swift run overcue-cli --output mouse --max-drag-pixels 6
swift run overcue-cli --output mouse --no-acceleration
swift run overcue-cli --output mouse --invert-dial
swift run overcue-cli --output mouse --idle-ms 180
```

Select the rekordbox shortcut mode explicitly when needed:

```sh
swift run overcue-cli --output mouse --rekordbox-mode export
swift run overcue-cli --output mouse --rekordbox-mode performance
```

Export is the default. At startup, OverCUE discovers rekordbox's settings and KeyMappings XML, then resolves the selected mapping and current shortcut for each commandId. F1–F20 and symbol keys used by the standard presets are supported; an unknown key representation skips only that binding. It never guesses a fallback for an unassigned action.

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

Configuration version 6 stores stable Action IDs or rekordbox command IDs instead of display labels. Each profile owns its waveform position and key, chord, and dial maps for groups 1–4. Versions 1–5 migrate automatically with a backup. `deviceProfiles` associates an ACK05 `PhysicalDeviceUniqueID` with a profile. See the Japanese example above for the complete JSON structure.

Version 1 and 2 files are backed up as `config.vN.backup.json` and migrated automatically. Unknown legacy action labels disable only the affected entry; all other settings are preserved. Restart OverCUE after editing JSON.

Use an alternate file with:

```sh
swift run overcue-cli --output mouse --config ~/Desktop/overcue-test.json
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
swift run overcue-cli
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

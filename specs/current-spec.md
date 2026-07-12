# OverCUE 現行仕様

更新日: 2026-07-11
対象: macOS版 OverCUE / XPPen ACK05 / rekordbox 7

## 1. 概要

OverCUEは、XPPen ACK05のダイヤルと10個のキーをrekordboxのCUE仕込み操作へ変換する常駐CLIアプリケーションである。

主運用はrekordbox Freeプランで利用できるマウス・キーボード操作方式とする。ACK05をIOHIDから直接読み取り、工場出荷時のショートカット入力を抑止したうえで、以下を出力する。

- ダイヤル: 拡大波形上のマウスドラッグ
- K1〜K10: rekordboxの現在のキーボードショートカット
- 2〜10キーコード: Hot Cue削除、波形位置登録などの任意操作

DDJ-SX互換の仮想MIDI出力も残しているが、rekordbox Freeプランでは接続機器としての制御が制限されるため、通常運用にはマウス方式を使用する。

## 2. 動作環境

- macOS 13以降
- Swift 6以降
- XPPen ACK05
- rekordbox 7
- ACK05のVendor ID: `0x28BD`
- ACK05のProduct ID: `0x0202`
- 主な接続方式: Bluetooth Low Energy

実行するターミナルには、macOSの「プライバシーとセキュリティ」で以下の権限が必要となる。

- 入力監視: ACK05のHID入力取得
- アクセシビリティ: マウス・キーボードイベント送信

XPPenPenTabletがACK05入力を消費または変換する場合は停止する。

## 3. 起動

推奨のFreeプラン用起動:

```sh
.build/debug/overcue-cli --output mouse
```

Swift Package Managerから起動する場合:

```sh
swift run overcue-cli --output mouse
```

終了は`Control-C`。

### 3.1 起動オプション

| オプション | 内容 | 初期値 |
| --- | --- | --- |
| `--output mouse\|midi` | 出力方式 | `midi` |
| `--rekordbox-mode export\|performance` | 読み込むrekordboxキーマップ | `export` |
| `--deck 1-4` | MIDIモードの対象Deck | `1` |
| `--touch-off-ms <ms>` | MIDI JogTouchまたはマウスドラッグの解放待ち | `150` |
| `--idle-ms <ms>` | `--touch-off-ms`のマウス向け別名 | `150` |
| `--source-name <name>` | 仮想MIDIソース名 | `OverCUE` |
| `--drag-pixels <px>` | ダイヤル低速時の移動量 | `1` |
| `--max-drag-pixels <px>` | ダイヤル高速時の最大移動量 | `20` |
| `--no-acceleration` | ダイヤル加速を無効化 | 無効 |
| `--invert-dial` | ダイヤル方向を反転 | 無効 |
| `--config <path>` | 外部設定ファイル | 後述 |
| `--shared` | ACK05の元のキー入力を抑止しない | 無効 |

通常はACK05を排他的に開く。`--shared`は入力調査用であり、K8の`Control-Z`などがターミナルへ到達する可能性がある。

## 4. ダイヤルによる波形操作

### 4.1 波形位置登録

初期コード`K8+K1`で、現在のポインタ位置を波形ドラッグ位置として登録する。登録座標は現在のプロファイルへ即時保存され、次回起動時に復元される。

### 4.2 ドラッグ動作

1. 最初のダイヤル入力で保存位置へポインタを移動する。
2. 左ボタンを押下する。
3. ダイヤル入力ごとに水平方向へドラッグする。
4. 150ms入力がなければ左ボタンを解放する。
5. 操作前のポインタ位置へ戻す。

方向転換または新しい回転シーケンスでは、必ず低速の細かい移動量から開始する。

### 4.3 加速カーブ

- 低速移動量: 1px/detent
- 最大移動量: 20px/detent
- 低速判定: 入力間隔200ms以上
- 最大速判定: 入力間隔35ms以下
- 補間: 4次カーブ
- 入力間隔平滑化: 前回65%、今回35%

これにより、ゆっくり回した場合は1px単位で位置合わせし、速く回した場合のみ大きく移動する。

## 5. デフォルトキーマップ

ACK05は縦向きで使用する。

| キー | 操作 | 特殊動作 |
| --- | --- | --- |
| K1 | Hot Cue C | なし |
| K2 | Delete Memory Cue | なし |
| K3 | Jump Forward | 長押しリピート・加速 |
| K4 | Hot Cue B | なし |
| K5 | Set Memory Cue | なし |
| K6 | Jump Backward | 長押しリピート・加速 |
| K7 | Quantize | コード修飾キー、単体は解放時送信 |
| K8 | Hot Cue A | コード修飾キー、単体は解放時送信 |
| K9 | Cue | 押下中のみ再生、解放時にCUE位置へ戻る |
| K10 | Play/Pause | なし |

### 5.1 Jump長押し

Jump ForwardまたはJump Backwardが割り当てられた通常キーは、押下時に1回ジャンプする。400ms保持すると連続送信を開始する。

- 開始間隔: 180ms
- 最短間隔: 35ms
- 最大加速までの時間: 約2秒
- カーブ: 開始と終了が滑らかなS字カーブ

キーを解放すると直ちに停止する。動作はK3/K6という物理位置ではなく、割り当てたJump操作へ追従する。

### 5.2 Cue保持

Cueが割り当てられた通常キーは、押下時にrekordboxのCueショートカットをkeydownし、解放時にkeyupする。これによりCue Point Samplerと同じ「押している間だけ再生し、離すとCUE位置へ戻る」動作を行う。

## 6. コード操作

`chordMap`では、K1〜K10から異なる2キーを任意に組み合わせられる。

```json
"K5+K1": "delete_hot_cue_3"
```

先頭のK5が修飾キー、後続のK1がトリガーとなる。修飾キーを先に保持してからトリガーを押す。

コード成立時:

- コードへ割り当てた操作を1回実行する。
- 修飾キーとトリガーの単体操作を抑止する。
- 修飾キーを保持したまま、複数のトリガーを続けて使用できる。

コード不成立時:

- 修飾キーの単体操作を解放時に1回送信する。

修飾キーにCueまたはJumpを割り当てた場合はコード判定が優先される。そのキーの単体操作は解放時の1回送信となり、Cue保持とJump長押し加速は無効になる。

ACK05のキーによってはHIDレポートが修飾キーだけで構成されたり、別の組み合わせと同じ値になったりする。OverCUEは直前の押下状態と全キーのHIDシグネチャを使って物理キーの組み合わせを復元する。

### 6.1 デフォルトコード

| コード | 操作 |
| --- | --- |
| K8+K1 | Capture Waveform Position |
| K7+K8 | Delete Hot Cue A |
| K7+K4 | Delete Hot Cue B |
| K7+K1 | Delete Hot Cue C |
| K7+K3 | Call Next Memory Cue |
| K7+K6 | Call Previous Memory Cue |

## 7. Action Layerと利用可能な操作

物理入力は`InputActionResolver`で論理的な`ActionEvent`へ変換される。ActionEventのphaseは`triggered`、`pressed`、`released`、`repeated`のいずれかであり、Cue保持とJump長押しは物理キーではなくActionの動作特性として処理する。

rekordbox固有のcommandIdは`RekordboxActionAdapter`だけが保持する。`capture_waveform_position`はInternal Action Handlerで処理し、rekordboxへは送信しない。

設定ファイルの`keyMap`と`chordMap`では、以下の安定Action IDを使用する。

| Action ID | 表示名 | rekordbox commandId |
| --- | --- | --- |
| `hot_cue_1` | Hot Cue A | `301e` |
| `hot_cue_2` | Hot Cue B | `301f` |
| `hot_cue_3` | Hot Cue C | `3020` |
| `delete_hot_cue_1` | Delete Hot Cue A | `3021` |
| `delete_hot_cue_2` | Delete Hot Cue B | `3022` |
| `delete_hot_cue_3` | Delete Hot Cue C | `3023` |
| `set_memory_cue` | Set Memory Cue | `3024` |
| `delete_memory_cue` | Delete Memory Cue | `303b` |
| `call_next_memory_cue` | Call Next Memory Cue | `3039` |
| `call_previous_memory_cue` | Call Previous Memory Cue | `303a` |
| `jump_forward` | Jump Forward | `3008` |
| `jump_backward` | Jump Backward | `3009` |
| `quantize` | Quantize | `301c` |
| `cue` | Cue | `3007` |
| `play_pause` | Play/Pause | `3006` |

`chordMap`のみ、内部操作`capture_waveform_position`を指定できる。

## 8. rekordboxショートカット連携

OverCUEは固定キーやマッピングファイルIDを直接決め打ちせず、起動時にrekordboxの設定とKeyMappings XMLを読み、commandIdから現在のショートカットを解決する。

- Export: 設定に選択IDがあればその値を使用し、現行設定のように値がなければKeyMappings内のマッピング名からExport用を検索
- Performance: rekordbox設定の`performaceKeyMapping`（表記差異も許容）で選択されたマッピング
- 基準ディレクトリ: `~/Library/Application Support/Pioneer/`以下からKeyMappingsを持つrekordboxディレクトリを検索

`command + F10`を含むF1〜F20、修飾キーの順序・区切り空白の差異、および標準プリセットで使われる記号キーを解釈する。未知のキー表現が残っていても、その割り当てだけを警告してスキップし、CLI全体は停止しない。

対象操作がrekordbox側で未割り当ての場合、代替キーは推測せず、ログへ`unassigned`を表示して何も送信しない。標準Performance 1ではQuantizeが未割り当てである。

キーボード操作はrekordbox（bundle ID `com.pioneerdj.rekordboxdj`）が最前面の場合だけ送信する。

## 9. 外部設定ファイル

デフォルト保存先:

```text
~/Library/Application Support/OverCUE/config.json
```

設定形式はversion 6。初回起動時に自動生成する。version 1〜5設定を検出した場合は原本を`config.vN.backup.json`へ保存してversion 6へ自動移行する。旧デフォルト構成ではグループ1をPERFORMANCE / Deck 1、グループ2をPERFORMANCE / Deck 2、グループ3をEXPORT / Deck 1とし、K7＋ダイヤル左右へrekordbox既存のPitch Bend − / ＋、K7+K2へ昇順グループ切り替え、K7+K5へ降順グループ切り替えを追加する。ユーザーが変更した割り当ては保持する。デフォルトマップは`Sources/OverCUECore/Resources/DefaultKeyMapping.json`から読み込む。

```json
{
  "version": 6,
  "defaultProfile": "default",
  "deviceProfiles": {
    "DEVICE-PHYSICAL-UUID": "default"
  },
  "profiles": {
    "default": {
      "waveformPosition": {
        "x": 640.5,
        "y": 212.25
      },
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
        }
      }
    }
  }
}
```

### 9.1 プロファイル

各プロファイルは以下を独立して保持する。

- `waveformPosition`: 波形ドラッグ座標
- `groupMappings`: グループ1〜4の入力マップ
- `rekordboxMode`: グループで使用する`export`または`performance`
- `keyMap`: K1〜K10の単体操作
- `chordMap`: 2〜10キーの任意数コード操作。末尾のキーをトリガーとして扱う
- `dialMap`: `clockwise`と`counterclockwise`のダイヤル操作
- `dialChordMap`: 1つ以上のキー保持とダイヤル左右を組み合わせた操作。例: `K7+DIAL_RIGHT`

グループ切り替えActionはグループ1で設定するプロファイル共通割り当てで、昇順は1→2→3→4→1、降順は1→4→3→2→1と循環する。旧`cycle_group` Actionは昇順として扱う。EXPORT / PERFORMANCE切り替えActionは、CLIが参照するrekordboxショートカットセットを切り替える。設定編集後はOverCUEを再起動する。

GUIのグループPickerとCLIの実行グループは双方向に同期する。GUIからグループを変更した場合はCLIとメニューバーも更新し、ACK05から変更した場合はGUIのPickerも更新する。モードは各グループの`rekordboxMode`へ保存し、グループ変更時に保存値を復元する。ACK05またはGUIからモードを変更した場合は現在グループへ直ちに保存する。

表示言語はOverCUEメニューの設定画面から日本語、英語、簡体字中国語を切り替える。翻訳辞書は`Sources/OverCUEApp/Resources/Localization`のJSONファイルとして管理し、選択はUserDefaultsへ保存する。rekordbox由来の機能名はrekordboxマッピングの記述を優先する。

割り当て保存前に物理入力の競合を検査する。同じ単体キー、同じコード、同じダイヤル操作が別Actionへ割り当て済みの場合は、ダイアログで上書きを確認する。コードまたはキー保持＋ダイヤルの修飾キーにCue保持やJumpリピートなどの長押しActionが存在する場合、および長押しActionを既存の修飾キーへ設定する場合は保存しない。競合は赤、保存・更新成功は緑、入力待ちや状態変更はグレーのトーストで画面右下に表示する。OverCUE設定セクションは他カテゴリと同様に折りたためる。

デバイスマップのキー選択は単体キー割り当てを同時押しより優先する。CLIはACK05の押下状態をDistributed NotificationでGUIへ通知し、GUIは押下中の物理キーだけを緑でハイライトする。キー解放またはデバイス切断時はハイライトを解除する。

メニューバーはゴーストアイコン、現在のモード頭文字（E/P）、現在の実行グループの順に表示する。CLI内のグループ／モードActionによる変更はプロセス間通知でGUIへ同期する。

### 9.2 デバイスとプロファイルの対応

`deviceProfiles`のキーにデバイスID、値にプロファイル名を指定する。未登録のACK05は`defaultProfile`を使用し、初回入力時に対応を設定ファイルへ自動保存する。

デバイスIDは次の優先順で取得する。

1. `PhysicalDeviceUniqueID`
2. `DeviceAddress`
3. `LocationID`

接続中の検証機ではシリアル番号は公開されず、`PhysicalDeviceUniqueID`とBLEの`DeviceAddress`が取得できた。

## 10. MIDIモード

MIDIモードはCoreMIDI仮想ソース`OverCUE`を生成し、DDJ-SX形式のJogTouch/JogScratchを送信する。

Deck 1の出力:

```text
最初の回転       90 36 7F  JogTouch ON
時計回り         B0 22 41  JogScratch +1
反時計回り       B0 22 3F  JogScratch -1
150ms入力なし    90 36 00  JogTouch OFF
```

Freeプランでは接続機器制限があるため、実運用はマウスモードを推奨する。

## 11. 診断とテスト

HID入力確認:

```sh
.build/debug/overcue-probe
```

排他入力で確認:

```sh
.build/debug/overcue-probe --seize
```

コアチェック:

```sh
.build/debug/overcue-checks
```

現時点のコアチェック数は150件。

## 12. SwiftUI設定画面

`OverCUE`ターゲットは、rekordboxのキーマッピング実ファイルを読み取り、設定内容をmacOSネイティブ画面で確認・編集する。

```sh
swift run OverCUE
```

実装済み:

- 選択中のPERFORMANCEマッピングおよびEXPORTマッピングの読み込み
- `MAPPING`要素の順序、commandId、説明、キーを保持（同一commandIdへの複数キーを含む）
- Browse、Deck 1、Deck 2、All Decks、Sampler、Recordings、General、View、Playlistへの分類
- カテゴリ折りたたみと機能・rekordboxショートカット・ACK05キーマップの3カラム表示
- 機能名、キー、commandId、ACK05キーによる検索
- `config.json`のデフォルトプロファイルとACK05筐体表示の対応
- ショートカット行と筐体ボタンの双方向選択
- 設定済み行のアイコンおよび背景色表示
- 複合キー選択時の複数ボタン同時ハイライト
- 編集ボタンからACK05実機の単一キーまたは2キー入力を取得し、`config.json`へ保存
- 編集ボタン右側から対象操作のACK05割り当てを削除
- GUI起動時に`overcue-cli`入力ブリッジを自動起動し、編集時のみ一時停止
- メニューバーへ白抜きロゴを表示し、ACK05入力の有効・無効、画面再表示、終了を提供
- メニューバーアイコンは白塗りのゴースト本体と、透明抜きのヘッドホン・目・口で描画
- アクセシビリティ許可要求はOverCUE本体へ集約し、内蔵CLI再起動時はダイアログを抑止
- ウィンドウを閉じても入力ブリッジを継続
- `Scripts/build-app.sh`でarm64 / x86_64 Universal Binaryの署名済み`dist/OverCUE.app`を生成し、同じくUniversal BinaryのCLIヘルパーを内包
- Apple Silicon Mac / Intel Macの両方を対象とし、最低対応OSはmacOS 13
- 4グループ表示
- 時計回り90度の縦向きを初期値とする筐体表示、90度単位の回転、回転時にも正立するキーラベル

## 13. 現在の制約

- rekordboxの画面レイアウトが変わった場合は波形位置の再登録が必要となる。
- 波形位置は絶対座標のため、ウィンドウ移動、解像度変更、表示倍率変更の影響を受ける。
- キーマップは起動時に読み込むため、JSON編集後は再起動が必要となる。
- rekordboxの対象操作が未割り当てなら、そのキーは動作しない。
- ACK05からのキー・ダイヤル出力はrekordboxが最前面にある場合だけ行う。
- 同じ物理キーをコード修飾キーにすると、単体操作は解放時実行になる。
- 複数ACK05用のデバイス・プロファイル対応は保持できるが、複数台の完全な同時操作は正式対応外。入力状態をデバイスごとに完全分離する拡張余地がある。
- `PhysicalDeviceUniqueID`が再ペアリング後も維持されるか、2台の実機間で必ず異なるかは未検証。

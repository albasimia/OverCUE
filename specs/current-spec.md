# OverCUE 現行仕様

更新日: 2026-09-01
対象: macOS版 OverCUE / XPPen ACK05 / rekordbox 7

## 1. 概要

OverCUEは、物理入力インターフェースをrekordboxのCUE仕込み操作へ変換するソフトウェアアダプターである。XPPen ACK05をOfficial / First-class deviceとして扱い、Generic HIDはAdvanced / Best-effortの拡張対象とする。

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

rekordbox固有のcommandId規則は`RekordboxActionAdapter`だけが保持する。Deck依存操作は、意味上のAction IDとユーザーが選択したrekordbox shortcutのcommandIdを`rekordbox-action:<action-id>:<commandId>`として一体で保存する。これにより同じPreset Group内でDeck 1 / 2 / 3 / 4やAll Decks等を混在でき、Cue holdやJump repeatのAction behaviorも維持する。Group単位の対象Deckは持たない。`capture_waveform_position`はInternal Action Handlerで処理し、rekordboxへは送信しない。

次表のAction IDとDeck 1 commandIdはsemantic対応のSingle Source of Truthであり、v9以前のmigrationと既知shortcutの分類に使用する。v10のDeck依存割り当てはscope付きreferenceとして保存する。

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
| `pitch_bend_increase` | Pitch Bend + | `304f` |
| `pitch_bend_decrease` | Pitch Bend - | `3050` |

内部操作は従来どおり安定Action IDをそのまま保存する。

表のcommandIdはDeck 1。PERFORMANCEの既知command familyは同じAction suffixに対してDeck 1=`30xx`、Deck 2=`31xx`、Deck 3=`32xx`、Deck 4=`33xx`である。例えばPlay/Pauseのscope付きreferenceは`rekordbox-action:play_pause:3006` / `...:3106` / `...:3206` / `...:3306`となる。ユーザー指定のGeneric `rekordbox:<commandId>`はその値をそのまま使用し、semantic Actionへの変換やDeck変換をしない。EXPORT / PERFORMANCEの別はPreset Groupのmodeが選ぶKeyMappings XMLであり、commandId自体は選択shortcutが保持する。

## 8. rekordboxショートカット連携

OverCUEは固定キーやマッピングファイルIDを直接決め打ちせず、起動時にrekordboxの設定とKeyMappings XMLを読み、commandIdから現在のショートカットを解決する。

- Export: 設定に選択IDがあればその値を使用し、現行設定のように値がなければKeyMappings内のマッピング名からExport用を検索
- Performance: rekordbox設定の`performaceKeyMapping`（表記差異も許容）で選択されたマッピング
- 基準ディレクトリ: `~/Library/Application Support/Pioneer/`以下からKeyMappingsを持つrekordboxディレクトリを検索

`command + F10`を含むF1〜F20、修飾キーの順序・区切り空白の差異、および標準プリセットで使われる記号キーを解釈する。未知のキー表現が残っていても、その割り当てだけを警告してスキップし、CLI全体は停止しない。

対象操作がrekordbox側で未割り当ての場合、代替キーは推測せず、ログへ`unassigned`を表示して何も送信しない。標準Performance 1ではQuantizeが未割り当てである。

キーボード操作はrekordbox（bundle ID `com.pioneerdj.rekordboxdj`）が最前面の場合だけ送信する。

2026-08-30にこのMacの選択中`Performance 1 (Preset)`を既存ローダーと同じ経路で読み、Deck 1 / 2 / 3がそれぞれ`30xx` / `31xx` / `32xx`で同一suffixを使うことを確認した。選択プリセットにはDeck 4の割り当て行自体が含まれないため、Deck 4は同じrekordboxの4Deck command familyである`33xx`として扱い、Core checksで全Deckの解決とカテゴリ分類を固定する。

## 9. 外部設定ファイル

デフォルト保存先:

```text
~/Library/Application Support/OverCUE/config.json
```

設定形式はversion 10。初回起動時に自動生成する。version 1〜9設定を検出した場合は原本を`config.vN.backup.json`へ保存して段階的に自動移行する。v9→v10では番号付きGroupをstable ID、必須name、orderを持つPreset Groupへ変換する。旧`rekordboxDeck`は、そのGroup内のDeck依存標準Actionをscope付きreferenceへ変換するためだけに使用し、v10の保存結果には残さない。Internal ActionとGeneric `rekordbox:<commandId>`は変更せず、Group 3のEXPORT用途、Mode、waveformPosition、各mappingを維持する。デフォルトマップは`Sources/OverCUECore/Resources/DefaultKeyMapping.json`から読み込む。

GUIとCLIは同じ`config.json`を正本として共有する。永続更新は`OverCUEConfigurationFileStore`を通し、atomic writeの置換対象とは別の安定した`config.json.lock`を`flock`で排他取得したうえで最新ファイルをread-modify-writeする。CLIのMode変更とwaveform位置保存は最新configの対象fieldだけを更新する。GUIは最後に読み込んだbaseline、GUIローカル変更、lock取得後に読み直した最新disk stateを3-way mergeし、GUIが変更していないProfile / Preset Group / mapping / Logical Device等のfieldは最新disk stateを保持する。同一fieldを双方が変更した場合はGUI localを採用する。migrationもlock内で最新versionを再判定し、既に別processがcurrentへ移行・更新した場合はその最新stateを採用する。

CLIがModeやwaveform位置を保存した場合はprocess間変更通知を送り、GUIはdisk stateを新しいpersisted baselineとして取り込み、baselineからのGUI未保存差分だけを再適用する。Preset切替時にも同じreconcileを行うため、CLIがModeを変更した後にGUIがPresetを往復しても古い値を送り返さない。runtime status受信だけを理由にconfig全体を保存することはない。選択中Presetはstable IDで保持し、remote側の並べ替え後も同じPresetを参照する。削除されたIDへのruntime controlは無視する。

CLIはACK05 report処理前にもconfig file revisionを確認する。変更時はPhysical Binding → Logical Device → Profileを再評価し、全Profile / Preset GroupのAction mapping、Mode、波形位置を再構築してから入力を処理する。config内容とrevisionは同じ`config.json.lock`保持中にsnapshotとして取得し、古い内容に新しいrevisionを対応させて更新を見逃さない。

```json
{
  "version": 10,
  "defaultProfile": "default",
  "logicalDevices": {
    "deck-1-main": {
      "name": "Deck 1 Main",
      "profileName": "default"
    }
  },
  "physicalDeviceBindings": [
    {
      "logicalDeviceID": "deck-1-main",
      "kind": "ack05",
      "vendorID": 10429,
      "productID": 514,
      "serialNumber": "ACK05-SERIAL"
    }
  ],
  "deviceProfiles": {
  },
  "profiles": {
    "default": {
      "presetGroups": [
        {
          "id": "pg-default-main",
          "name": "Group 1",
          "order": 10,
          "mapping": {
          "waveformPosition": {
            "x": 640.5,
            "y": 212.25
          },
          "rekordboxMode": "performance",
          "keyMap": {
            "K1": "rekordbox-action:hot_cue_3:3020",
            "K2": "rekordbox-action:delete_memory_cue:303b",
            "K3": "rekordbox-action:jump_forward:3008",
            "K4": "rekordbox-action:hot_cue_2:301f",
            "K5": "rekordbox-action:set_memory_cue:3024",
            "K6": "rekordbox-action:jump_backward:3009",
            "K7": "rekordbox-action:quantize:301c",
            "K8": "rekordbox-action:hot_cue_1:301e",
            "K9": "rekordbox-action:cue:3007",
            "K10": "rekordbox-action:play_pause:3006"
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
            "K7+DIAL_LEFT": "rekordbox-action:pitch_bend_decrease:3050",
            "K7+DIAL_RIGHT": "rekordbox-action:pitch_bend_increase:304f"
          }
        }
        }
      ]
    }
  }
}
```

### 9.1 プロファイル

各Profileは1〜24個の`presetGroups`を持つ。Preset Groupはopaqueなstable `id`、必須`name`、並び順`order`、`mapping`から成る。固定24要素の配列ではなく、存在するPresetだけを保持する。各mappingは以下を独立して保持する。

- `waveformPosition`: Preset固有の波形ドラッグ座標
- `rekordboxMode`: Presetで使用する`export`または`performance`
- `keyMap`: K1〜K10の単体操作
- `chordMap`: 2〜10キーの任意数コード操作。末尾のキーをトリガーとして扱う
- `dialMap`: `clockwise`と`counterclockwise`のダイヤル操作
- `dialChordMap`: 1つ以上のキー保持とダイヤル左右を組み合わせた操作。例: `K7+DIAL_RIGHT`

Preset切り替えActionは先頭Presetで設定するProfile共通割り当てで、存在するPresetを`order`順に循環し末尾と先頭でwrapする。旧`cycle_group` Actionは次Presetとして扱う。EXPORT / PERFORMANCE切り替えActionは、CLIが参照するrekordboxショートカットセットを切り替える。

GUIは番号segmentではなくPreset名のmenuで編集対象を選択する。このShortcuts Presetはeditor専用stateであり、Logical Deviceごとの実行Presetとは同期しない。Runtime Statusはdevice-scopedな実行Preset / Modeの表示情報だけを更新し、editorの選択Preset、Mode、mappingを変更しない。ShortcutsのPreset / Mode操作もdevice runtime controlを送らない。Modeと波形ドラッグ座標はPresetごとに独立して保存・復元する。Deckや対象scopeは割り当てたshortcut自身が保持するため、追加のDeck selectorは表示しない。

GUIからPreset / Modeのruntime controlを送る場合、CLIは適用直前に最新version 10 stateをreloadし、Physical Binding / Logical Device / Profileとstable Preset IDを再評価してmappingを再構築する。同一Presetへのcontrolでもhold、key repeat、波形dragを終了してから最新mapping、Mode、waveform位置へ更新する。

表示言語はOverCUEメニューの設定画面から日本語、英語、簡体字中国語を切り替える。翻訳辞書は`Sources/OverCUEApp/Resources/Localization`のJSONファイルとして管理し、選択はUserDefaultsへ保存する。rekordbox由来の機能名はrekordboxマッピングの記述を優先する。

割り当て保存前に物理入力の競合を検査する。同じ単体キー、同じコード、同じダイヤル操作が別Actionへ割り当て済みの場合は、ダイアログで上書きを確認する。コードまたはキー保持＋ダイヤルの修飾キーにCue保持やJumpリピートなどの長押しActionが存在する場合、および長押しActionを既存の修飾キーへ設定する場合は保存しない。競合は赤、保存・更新成功は緑、入力待ちや状態変更はグレーのトーストで画面右下に表示する。OverCUE設定セクションは他カテゴリと同様に折りたためる。

デバイスマップのキー選択は単体キー割り当てを同時押しより優先する。CLIはACK05の押下状態をDistributed NotificationでGUIへ通知し、GUIは押下中の物理キーだけを緑でハイライトする。キー解放またはデバイス切断時はハイライトを解除する。

メニューバーはゴーストアイコン、現在のモード頭文字（E/P）、現在の実行グループの順に表示する。CLIはGroup / Mode変更時だけでなく通常のACK05キー／ダイヤル入力時にも、session device ID、Logical Device ID、Profile名を含むdevice-scoped runtime statusをpublishする。default Profile用GUIはsource Profileが`defaultProfile`と一致するstatusだけをruntime control targetとして採用し、non-default Profileのstatusとinput highlightを無視する。GUIからのcontrolは、default Profileを操作するACK05のうち実際に最後に入力したlive session deviceへProfile名付きdevice scopeで送信する。target device切断時はtargetとinput highlightを解放し、再接続statusで新しいsession IDへ更新する。live default targetがない場合は送信せず、global scopeでnon-default controllerへフォールバックしない。CLIはcontrol前のconfig reloadでdeviceが別Profileへrebindされていた場合もcontrolを拒否する。GUIはruntime status受信だけではconfigへ書き戻さない。

ACK05割り当ての入力取得は、最初にキーまたはダイヤルを入力したphysical deviceへ完了・キャンセルまで固定する。他ACK05のキー状態は同じコードへ混在させない。capture sourceが切断された場合は編集をキャンセルし、別deviceへ暗黙に引き継がない。

### 9.2 デバイスとプロファイルの対応

`logicalDevices`は演奏上のLogical Device名とProfile割り当てを保持し、`physicalDeviceBindings`がIOHID上のPhysical DeviceをLogical Deviceへ結び付ける。未登録ACK05は`defaultProfile`で動作するが、自動登録・自動保存しない。これにより機器交換時はPhysical Bindingだけを差し替え、Logical Device側のProfileを維持できる。

Physical BindingはVendor ID + Product ID + Serialを最優先する。Serialがない機器のUSB `LocationID`はIdentify / Rebind候補のヒントにのみ使用し、永続IDとして自動一致させない。version 8以前から移行する`location:XXXXXXXX`も`lastKnownLocationID`だけへ保存し、`legacyDeviceIdentifier`の一致対象にはしない。`PhysicalDeviceUniqueID`や`DeviceAddress`等の非location旧識別値だけを後方互換の`legacyDeviceIdentifier`として保持する。

CLI bridgeは接続ACK05ごとに独立したcontrollerを生成する。live session IDはIOHID接続インスタンス由来のtransport identifierを使用し、Serial由来のpersistent identityとは分離する。`InputActionResolver`、押下キー、Cue hold、Jump repeat、コード、ダイヤル加速、波形ドラッグ、Preset／Mode／Profile状態は物理device間で共有しない。切断時は対象deviceの状態とkeydownだけを解放する。

同時接続中の複数deviceが同じVID / PID / Serialを報告した場合、そのpersistent bindingはambiguousとして扱い、どちらも同じLogical Deviceへ自動bindingしない。接続トポロジ変更は既存controllerへ即時通知し、既に押下中のholdを含む状態をdefault Profileへ安全に再評価する。

複数ACK05の状態分離とruntime target / config persistenceはCore checksとmacOSローカルbuildで確認するが、2台以上を使う同時操作、切断、再接続は実機未検証である。

### 9.3 Device Management Core

`HIDDeviceRegistry`は接続中Physical HID Deviceをsession identifierで管理し、VID / PID / Serial / Product / Manufacturer / transport / LocationIDと、現在のbinding resolution、ambiguous状態、Logical DeviceのProfileを提供する。Registryはruntime接続状態だけを担当し、永続状態の正本はversion 10 configの`physicalDeviceBindings`と`logicalDevices`である。LocationIDは候補hintとしてのみ公開する。

`HIDIdentifySession`は候補deviceの入力を待ち、最初に操作されたsessionを返して終了する。候補外入力は無視し、選択sourceまたは全候補が切断された場合はcancelする。

RebindはLogical Deviceを残したままPhysical Bindingだけを置換する。現時点で自動永続化できるのは、接続中に一意と確認できるVID / PID / Serialの組み合わせだけである。Serialなし、同じpersistent identityを持つdeviceが複数接続中、または別Logical Deviceへbinding済みの場合は拒否する。ForgetはPhysical Bindingだけを削除し、Logical DeviceとProfileを削除しない。永続更新は共通lock付きfile storeを使用し、bridgeは変更後に古いProfileで入力を継続しないようmappingとbindingを再評価する。

### 9.4 Generic HID Core

Generic HIDはAdvanced / Best-effort機能として扱う。Coreはkeyboard usage、consumer control、button、relative value、absolute valueをdevice session別のeventへ正規化する。press / releaseとrelative deltaを保持し、Koolertron encoderが特定UsageやReportを出すとは仮定しない。

永続候補の入力descriptorはUsage Page、Usage、Report ID、親collection pathで構成する。IOHIDElement cookieは再接続時の安定性を仮定せず、runtime診断にだけ使用する。同一device内に同じdescriptorのelementが複数ある場合は、実機根拠なしに永続bindingへ確定しない。

Generic HID Learnは最初のactivationを送ったPhysical Deviceへsource lockし、別device入力を混在させない。source切断時はcancelする。Unified Learn全体は単一session state machineが所有し、ACK05 captureとGeneric HID captureを独立backendとして開始する。一方の開始失敗は他方を終了させず、最初に入力をclaimしたbackendだけが保存とterminal cleanupを行う。進行中sessionは別の編集要求で置換しない。synthetic Generic HID eventは既存`ActionTarget` / `ActionEvent`へ変換でき、hold、accelerating repeat、relative triggerを既存Action Layerへ渡す。Generic HID層はrekordbox commandIdを保持せず、keyboard shortcutを直接送信しない。

Serialを持つGeneric HIDはDevicesでPhysical Bindingへ登録できる。Action Mappingの編集面はShortcutsへ統一し、ACK05と登録済みGeneric HIDのどちらか先に入力されたPhysical Inputを選択Actionへ割り当てる。Generic HIDの保存scopeは入力元Logical Device ID + Learn開始時に選択されていたeditor Preset stable IDで固定する。Group Preset assignmentやLearn途中のRuntime Statusは保存先に使わない。表示・削除もShortcutsで現在選択しているeditor Presetと対象Logical Deviceの同じscopeを使う。adapter固有の割り当てはversion 1の`generic-hid.json`へLogical Device ID / Preset stable ID / input descriptor単位で保存する。main configはversion 10を維持する。

通常runtimeは登録済みGeneric HIDだけをshared IOHIDで監視する。keyboard-class interfaceがmanager open後にmatchすると、exclusive manager open自体は成功しても後続claimだけ失敗しinput callbackが届かない場合があるため、Action runtimeは`SeizeDevice`を使わない。同じ登録deviceから得たraw IOHID usageとdownstream CGEventを短時間相関し、相関したkeyboard / Consumer Control eventだけを`.cghidEventTap / .headInsertEventTap / .defaultTap`でdropする。相関できない通常キーボード入力はfail-openとする。「入力を有効にする」がOFFの場合はACK05 / Generic HID runtimeとSuppressorを意図的に停止し、native入力を抑止しない。

ACK05 CLIとGeneric HID runtimeは独立input backendである。一方の起動失敗・終了時も他方は継続し、部分稼働はdegraded statusとして表示する。アプリが起動した`overcue-cli`はparent PIDを監視し、親GUIが消失した場合に終了してexclusive ACK05 claimを残さない。Devices Identify / Rebind中はruntimeだけを一時停止し、controller inputの永続ON/OFF設定は変更しない。

2026-09-03にSIDE-KEYBOARD実機で、Keypad 1〜4がmacOS keyCode 83〜86、Volume Up / Down / Muteが`systemDefined` subtype 8のNX key type 0 / 1 / 7として届くことを確認した。raw IOHID callbackからCGEvent callbackまでの差は約0.3〜5msで、press / releaseはいずれもactive tapからnilを返してdropできた。Input MonitoringとAccessibilityは双方許可済みだった。`OVERCUE_HID_SUPPRESSION_DIAGNOSTICS=1`で起動すると、Suppressor lifecycle、権限、match interface数、raw usage、CGEvent、相関結果をstderrへ記録できる。

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

全IOHID deviceをGeneric HID候補として観測:

```sh
.build/debug/overcue-probe --all
```

`--all`は接続sessionごとにVID / PID / Serial / Product / Manufacturer / transport / Usage Page / Usageを表示する。value eventではReport ID、runtime cookie、relative属性、同一descriptorの重複数、永続化可否、press / release / relative delta / absolute valueを表示する。複数の同型deviceもsession identifierで区別する。

コアチェック:

```sh
.build/debug/overcue-checks
```

macOSでdebug build、Core checks、release Universal Binary app生成、codesign検証を一括実行:

```sh
./Scripts/verify-macos.sh
```

最終検証のCore checks件数とUniversal Binary / codesign結果は、当該commitのAAL historyに記録する。

## 12. SwiftUI設定画面

`OverCUE`ターゲットは、rekordboxのキーマッピング実ファイルを読み取り、設定内容をmacOSネイティブ画面で確認・編集する。

```sh
swift run OverCUE
```

実装済み:

- 選択中のPERFORMANCEマッピングおよびEXPORTマッピングの読み込み
- `MAPPING`要素の順序、commandId、説明、キーを保持（同一commandIdへの複数キーを含む）
- Browse、Deck 1〜4、All Decks、Sampler、Recordings、General、View、Playlistへの分類
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
- 1〜24個のnamed Preset Groupをmenuで選択し、PresetごとのEXPORT / PERFORMANCEモードを表示・編集
- rekordbox shortcutの選択自体からDeck 1〜4、All Decks等のscopeを保持し、同一Preset内で混在
- 時計回り90度の縦向きを初期値とする筐体表示、90度単位の回転、回転時にも正立するキーラベル

## 13. 現在の制約

- rekordboxの画面レイアウトが変わった場合は波形位置の再登録が必要となる。
- 波形位置は絶対座標のため、ウィンドウ移動、解像度変更、表示倍率変更の影響を受ける。
- rekordbox KeyMappingsは起動時またはReload時に読み込む。
- rekordboxの対象操作が未割り当てなら、そのキーは動作しない。
- ACK05からのキー・ダイヤル出力はrekordboxが最前面にある場合だけ行う。
- 同じ物理キーをコード修飾キーにすると、単体操作は解放時実行になる。
- 複数ACK05の入力状態は物理deviceごとに分離したが、2台以上での同時操作、再接続、異なるLogical Device / Profileへの割り当ては実機未検証。
- Devices UIとIdentify / Rebind / Forget / Learn UIは未実装。対応する非UI Core/APIは実装済み。
- Generic HID runtime、Shortcuts統合Learn、adapter sidecar永続化は実装済み。SIDE-KEYBOARDのnative Keypad / Volume / Mute抑止も実機eventで確認済み。
- SIDE-KEYBOARD 1台は固有Serialを公開したが、同型2台のSerialが個体ごとに異なるかは実機未検証。同一identityが同時接続された場合はambiguityへ倒す。

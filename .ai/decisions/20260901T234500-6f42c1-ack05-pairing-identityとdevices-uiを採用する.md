# ACK05 Pairing IdentityとDevices UIを採用する

- Change ID: `20260901T234500-6f42c1`
- 状態: 採用

## 背景

2026-09-01にACK05実機2台でIOHIDの複数台検証を行った。2台はいずれも`VID=0x28BD / PID=0x0202`、製品名`Shortcut Remote`、Bluetooth Low Energy接続で、`serialNumber`は取得できなかった。

一方、macOSが返す`PhysicalDeviceUniqueID`は2台で異なり、ACK05の電源OFF/ONとMac再起動を跨いでも同じ値を維持した。Bluetooth設定から削除して再ペアリングすると、`PhysicalDeviceUniqueID`、`locationID`、`DeviceAddress`はいずれも新しい値へ変化した。

実機値の一例:

- ACK05 A: `F95D9BC1-E56B-2D4A-15DB-9AF900934FB3`
- ACK05 B: `31100918-88D2-1452-8C2E-563FF9B1C453`
- Aを再ペアリング後: `E8A00866-5AC3-4BDE-BE4D-FC42ED747BE0`

また、2台同時接続時にIOHID report / normalized VALUEのsource sessionが明確に分離し、片方の切断・再接続後は新しいsessionへ入力sourceが切り替わることを確認した。

## 決定

### ACK05 identity

- ACK05のruntime identityは従来どおり接続session identifierとする。
- ACK05は実機でSerialを持たないため、Serial必須をACK05のpersistent binding条件にはしない。
- ACK05ではmacOS `PhysicalDeviceUniqueID`を**Pairing Identity**として使用する。
- Pairing Identityは物理個体の永久Serialとは扱わない。Bluetooth再ペアリングで失効する識別子である。
- 同時接続中に同一Pairing Identityが複数sessionへ解決される場合はambiguousとして自動bindingしない。
- `DeviceAddress`と`locationID`は補助情報／hintとし、Pairing Identityの代替キーとして自動推測に使用しない。
- Generic HIDへこのルールを一般化しない。Generic HIDは引き続き実機descriptor証拠待ちとする。

### Re-pairing

Bluetooth再ペアリング後は、新しいPhysical Device Bindingとして扱う。

Logical Device、名前、Profileは保持し、ユーザーがDevices画面でIdentify / Rebindを行う。Serialがない以上、再ペアリング前後を同一物理個体だと自動推測しない。

### Devices UI

トップレベル画面を次の3つにする。

- Shortcuts
- Devices
- Settings

Shortcutsは既存のACK05マップ＋ショートカット一覧の2カラムを維持し、第3カラムを追加しない。

Devicesは別画面として、登録済みLogical Device一覧と選択デバイス詳細の2カラムにする。ACK05について以下を提供する。

- Add ACK05
- Identify
- Rebind
- Forget Physical Binding
- Logical Device rename
- 既存Profileへのassignment
- connected / disconnected表示
- Pairing ID表示

Identify中は通常のOverCUE ACK05 runtimeを一時停止し、対象ACK05のボタンまたはダイヤル入力でPhysical Deviceを決定する。完了／キャンセル後、開始前にruntimeが有効だった場合だけ復帰する。

Generic HID追加導線はDevices内に置くが、永続identityの実機証拠が揃うまでは登録処理を有効化しない。

### Preset Group管理

Shortcuts画面の既存Preset Group selectorに管理操作を追加する。

- Add
- Rename
- Delete
- 最大24個
- 新規Presetはopaque stable IDを生成する
- 新規Presetは現在のrekordbox modeを初期値とし、mappingは空で開始する

現行`OverCUEProfile.mapping(for:)`は最初のPresetが持つCycle Preset操作を他Presetへoverlayする構造のため、その責務をglobal mappingへ分離するまでは最初のPresetを削除不可とする。最後の1個も削除不可。

## 実装方針

config version 10の既存schemaは変更しない。ACK05 Pairing Identityは既存bindingの`legacyDeviceIdentifier`に`PhysicalDeviceUniqueID`を保存し、ACK05に限ってcurrent binding identityとして解釈する。これはschema bumpを避けるための互換利用であり、将来schemaを整理する場合は明示的なpairing identity fieldへ移行してよい。

## 不採用

- SerialがないACK05を永続binding不可のままにする。
- `locationID`だけでACK05を自動bindingする。
- 再ペアリング前後をDeviceAddressや外観上の同型情報から自動的に同一個体と推測する。
- Devices操作をShortcutsの第3カラムへ押し込む。
- Preset Groupを固定24 slot配列へ戻す。

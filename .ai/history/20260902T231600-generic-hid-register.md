# Generic HID実機検証を反映してDevices登録を有効化

- Date: 2026-09-02
- AAL-Change-Id: 20260902T231600-generic-hid-register

## 目的

Generic HIDの実機descriptor検証待ちで無効化していたDevices > Add Generic HIDを有効化し、Serial Numberを持つGeneric HIDをLogical Deviceへ登録できるようにする。

## 実機証拠

`SDINNOVATION / SIDE-KEYBOARD`（VID `0x0816`, PID `0x246E`）を`overcue-probe --all`で確認した。

- Serial Number: `3F8701678182`
- 1台が3 IOHID interfaceとして列挙される。
- 3 interfaceは同一VID / PID / Serial / locationIDを共有する。
- Key 1〜4はKeyboard page `0x0007`, usage `0x0059`〜`0x005C`としてpress/releaseを取得し、各descriptorはpersistable。
- Knob RightはConsumer page `0x000C`, usage `0x00E9`, report 3。
- Knob LeftはConsumer page `0x000C`, usage `0x00EA`, report 3。
- Knob PushはConsumer page `0x000C`, usage `0x00E2`, report 3。
- ノブ3入力もduplicates=1 / persistable=trueでpress/releaseを取得した。

## 実施内容

- Generic HID Identify monitorを追加した。
- Identify monitorは全HIDをshared modeで観測し、ACK05を除外、Serial Numberを持つGeneric HIDだけを登録候補にする。
- 同一persistent identity + locationIDの複数IOHID interfaceを1 live Physical Device候補へ束ねる。
- locationID無しの場合はSerialだけでinterfaceを束ねず、誤bindingを避ける。
- Add Generic HIDボタンを実動化した。
- Generic HID登録時は既存`HIDDeviceBindingManager`でVID / PID / Serial bindingを保存する。
- Generic HIDの既存bindingはGeneric HID IdentifyでRebindできるようにした。
- Binding解除後はLogical Deviceがhardware kindを保持しないため、ACK05 / Generic HIDを明示選択してIdentifyできるUIへ変更した。
- DevicesのIdentity表示をACK05限定表現からPhysical Device共通表現へ更新した。
- Generic HIDのSerial binding、duplicate Serial ambiguity、実機で確認した4キー + knob 3入力のpersistabilityをCore testへ追加した。
- 日本語 / 英語 / 簡体字のDevices文言をGeneric HID対応へ更新した。

## 検証

GitHub connector経由で実装しているため、この環境ではmacOSローカルの`swift build` / `swift test` / `overcue-checks` / app buildを実行できていない。

実機descriptor自体はユーザー環境の`overcue-probe --all`で確認済み。

## 残課題

- ローカルで`swift test`を実行する。
- `./Scripts/build-app.sh`で最新appを生成する。
- Devices > Add Generic HIDからSIDE-KEYBOARDを操作し、Logical Device登録とSerial表示を確認する。
- 同じ実機を抜き差しし、Serial維持と同じLogical DeviceへのRebind条件を確認する。
- 同型2台がある場合は同時接続してSerialの一意性を確認する。
- Generic HID Learn UI / runtime wiringを実装し、今回確認したKey 1〜4 / Knob Right / Left / PushをActionへ割り当てる。

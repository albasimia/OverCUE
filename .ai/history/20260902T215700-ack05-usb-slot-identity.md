# ACK05 USB Slot Identity対応

- Date: 2026-09-02
- AAL-Change-Id: 20260902T215700-ack05-usb-slot-identity

## 目的

USB接続したACK05をDevices > Add ACK05で登録できず、`has no verified persistent identity`になる問題を解消する。あわせてUSB接続時に1台のACK05が複数IOHID interfaceへ分かれることをruntime上で1 Physical Deviceとして扱う。

## 実機証拠

- USB ACK05はSerial Numberが空白。
- USB ACK05では`PhysicalDeviceUniqueID` / `DeviceAddress`を取得できない。
- 1台のACK05が3 IOHID interfaceとして列挙される。
- 3 interfaceは同じ`locationID`を共有する。
- 同じUSBハブの同じportへ抜き差し後も`locationID=0x01140000`を維持した。
- 同じUSBハブの別portでは`0x01130000`→`0x01140000`へ変化した。
- IORegistry pathの`Shortcut Remote@01140000`と`locationID=0x01140000`が一致した。

## 実施内容

- ACK05 USBの非zero `locationID`から`usb-slot:%08X`形式のSlot Identityを生成するようにした。
- ACK05のpersistent identityを、Serial → BLE Pairing Identity → USB Slot Identityの順で解決するようにした。
- ACK05 USBのruntime session identifierもSlot Identityを使い、同一slotの複数IOHID interfaceを同じsessionへ束ねるようにした。
- ACK05 binding managerはBLE Pairing IdentityまたはUSB Slot Identityを既存`legacyDeviceIdentifier`へ保存するようにした。
- grouped USB sessionではIOHID interfaceごとのdescriptor equalityではなく、live sessionの存在でRebind可否を確認するようにした。
- Generic HIDのidentity規則は変更していない。
- Core testへUSB slot identity、3 interface session統合、別port非一致、Generic HID非影響を追加した。

## 検証

GitHub connector経由で実装したため、この環境ではmacOSローカルの`swift build` / `swift test` / `overcue-checks` / `verify-macos.sh`を実行できていない。

実機identityの前提データはユーザー環境で`overcue-probe --all`と`ioreg -p IOUSB`により取得済み。

## 残課題

- ローカルで`swift build`、`swift test`、`swift run overcue-checks`、`./Scripts/verify-macos.sh`を実行する。
- Devices > Add ACK05でUSB ACK05登録を実機確認する。
- 同じhub portへの再接続で同じLogical Deviceへ復帰することを確認する。
- hub自体をMacの別portへ移した場合とMac再起動後のUSB slot identityは未確認。

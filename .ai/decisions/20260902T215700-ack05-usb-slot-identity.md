# ACK05 USBではlocationIDをUSB Slot Identityとして扱う

- Date: 2026-09-02
- Status: accepted
- AAL-Change-Id: 20260902T215700-ack05-usb-slot-identity

## Context

ACK05をUSB接続すると、実機ではSerial Numberが空白で、`PhysicalDeviceUniqueID`と`DeviceAddress`も取得できなかった。一方、同じ1台のACK05が次の3 IOHID interfaceとして列挙された。

- `usagePage=0x0001 / usage=0x0002`
- `usagePage=0x000D / usage=0x0002`
- `usagePage=0xFF0A / usage=0x0001`

3 interfaceは同一接続中に同じ`locationID`を共有した。

同じUSBハブをMac側の同じポートに接続したままACK05だけをhubの別ポートへ移すと、`locationID`は`0x01130000`から`0x01140000`へ変化した。同じhub portへ抜き差しした場合は`0x01140000`を維持した。IORegistryでも`Shortcut Remote@01140000`と`locationID=0x01140000`が一致した。

この証拠から、ACK05 USBの`locationID`は物理個体のIdentityではなくUSB topology上のslotを表す値として扱える。

## Decision

- BLE ACK05は従来どおり`PhysicalDeviceUniqueID`をPairing Identityとして使う。
- USB ACK05は非zeroの`locationID`を**USB Slot Identity**として使う。
- USB Slot Identityは物理ACK05個体を識別しない。同じslotへ別のACK05を挿した場合も同じLogical Deviceへ解決してよい。
- USB ACK05のruntime sessionは`locationID`由来のslot identityを使い、同じslotに属する複数IOHID interfaceを1 Physical Device sessionへ束ねる。
- USB ACK05を別hub portへ移した場合は別slotとして扱い、自動的に旧bindingへ一致させない。
- `USB Address`、IORegistry `sessionID`、IOHID object addressはpersistent bindingへ使わない。
- config version 10は維持する。USB Slot Identityは既存`legacyDeviceIdentifier`へ`usb-slot:%08X`形式で保存する。
- Generic HIDへこの規則を一般化しない。

## Supersedes

Decision `20260901T234500-6f42c1`のうち、`locationID`をACK05で常にhintだけとして扱う方針をUSB接続に限って置換する。BLEで`PhysicalDeviceUniqueID`をPairing Identityとして使う判断は維持する。

## 未確認

- USB hub自体をMacの別ポートへ移した場合のslot identity変化。
- Mac再起動を跨いだUSB slot identityの維持。

これらはUSB Slot Identityがtopology依存であることと矛盾しない。必要なら実機ゲートで追加確認する。

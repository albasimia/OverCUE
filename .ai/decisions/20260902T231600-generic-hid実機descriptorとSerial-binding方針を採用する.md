# Generic HID実機descriptorとSerial binding方針を採用する

- Date: 2026-09-02
- Status: accepted
- AAL-Change-Id: 20260902T231600-generic-hid-register

## Context

標準3DeckリグでACK05と組み合わせる小型Generic HID候補の実機が到着し、`overcue-probe --all`でdescriptorと入力を確認した。

実機:

- Manufacturer: `SDINNOVATION`
- Product: `SIDE-KEYBOARD`
- VID / PID: `0x0816 / 0x246E`
- Transport: USB
- Serial Number: `3F8701678182`
- PhysicalDeviceUniqueID: unavailable
- DeviceAddress: unavailable
- 観測locationID: `17903616`

1台の実機は3 IOHID interfaceとして列挙されたが、3 interfaceすべてでVID / PID / Serial / locationIDが一致した。

入力descriptorは次の通り。

- Key 1: page `0x0007`, usage `0x0059`, report 0, persistable
- Key 2: page `0x0007`, usage `0x005A`, report 0, persistable
- Key 3: page `0x0007`, usage `0x005B`, report 0, persistable
- Key 4: page `0x0007`, usage `0x005C`, report 0, persistable
- Knob Right: page `0x000C`, usage `0x00E9`, report 3, persistable
- Knob Left: page `0x000C`, usage `0x00EA`, report 3, persistable
- Knob Push: page `0x000C`, usage `0x00E2`, report 3, persistable

ノブはrelative encoder elementではなく、方向ごとに別Consumer Controlのpress/releaseとして見える。Generic HID Coreの既存press input表現で永続化でき、raw report専用例外は不要である。

## Decision

- Serial Numberを持つGeneric HIDは、既存どおりVID + PID + Serialをpersistent Physical Device identityとして扱う。
- `locationID`はGeneric HIDのpersistent identityへ昇格させない。
- 1 physical deviceが複数IOHID interfaceを持つ場合、Identify中のlive attachmentはpersistent identity + locationIDで束ねる。
- live attachmentのsession tokenは接続中interface由来とし、Serial由来persistent identityとは分離する。
- 同じpersistent identityを名乗る別locationのlive attachmentが同時存在する場合は束ねず、既存ambiguity判定でfail closedする。
- locationIDを取得できない複数interfaceはSerialだけで安易に束ねず、interfaceごとに分離してambiguityへ倒す。
- Generic HID IdentifyではIOHIDManagerをshared modeで開き、システムのキーボード／マウスを一括seizeしない。
- Identify対象は現時点では有効なSerial Numberを持つGeneric HIDに限定する。Serial無しGeneric HIDのfallback identityは実機根拠が得られるまで追加しない。
- 上記実機の4キー、Knob Right / Left / Pushはすべて既存`GenericHIDInputDescriptor` + press activationで表現する。
- 製品固有VID / PID / Usageをproduction codeへ固定しない。実機はGeneric HID設計の検証対象であり、UI・runtimeはdescriptor駆動を維持する。

## Consequences

- Devices > Add Generic HIDの実機descriptorゲートを解除できる。
- Generic HIDのPhysical BindingはSerialで再接続に追従できる。
- 同一実機の3 interfaceをIdentify UI上では1 Physical Device候補として扱える。
- Generic HID Learn Coreが今回の全入力を永続化できることが確認できた。Learn UI / runtime wiringは別実装として残る。

## 未確認

- 同型2台を同時接続した場合、それぞれ異なるSerial Numberが付与されるか。
- 抜き差し、Mac再起動後もSerial Numberが維持されるか。

ただし、同一Serialのlive attachmentが複数現れた場合はambiguityで拒否するため、未確認事項を理由に誤bindingへ進まない。

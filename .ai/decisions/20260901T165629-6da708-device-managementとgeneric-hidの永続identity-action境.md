# Device ManagementとGeneric HIDの永続identity・Action境界を固定する

- Change ID: `20260901T165629-6da708`
- 状態: 採用


## 背景

複数ACK05とGeneric HIDへ拡張するには、接続中Physical Deviceのsession状態、Logical Deviceへの永続binding、Identify / Rebind、入力Learnを分離する必要がある。IOHIDElement cookieやLocationIDをそのまま永続identityにすると再接続やUSB topology変更で設定が壊れる。一方、実機Reportがない段階でGeneric HID mapping schemaを確定すると、Koolertron固有形式を一般仕様として固定する危険がある。

## 決定

- Device Registryは接続中Physical Deviceをsession identifierで管理するruntime層とし、永続状態の正本はconfig version 9のPhysical Binding / Logical Device / Profileに置く。
- Identifyは候補sessionの最初の入力を選び、source切断または候補消滅時はcancelする。
- RebindはLogical DeviceとProfileを残してPhysical Bindingだけを交換する。一意なVID / PID / Serialを確認できる場合だけ自動永続化し、LocationIDはhintに限定する。Serialなし、同一identity複数台、別Logical Deviceへbinding済みの場合は拒否する。
- ForgetはPhysical Bindingの削除とLogical Device削除を別操作にする。
- Generic HIDの永続候補descriptorはUsage Page / Usage / Report ID / collection pathで表す。IOHIDElement cookieはruntime診断にだけ使い、同一descriptorがdevice内で複数ある場合は永続化しない。
- Generic HID Learnは最初のactivation sourceへ固定し、別device入力を混在させない。
- Generic HID eventは既存`ActionTarget` / `ActionEvent`へ変換し、rekordbox commandId解決とkeyboard outputは既存Action Layer以降だけで行う。
- Generic HID mappingは実機identityの証拠が揃うまでconfigへ追加せず、version 9を維持する。

## 理由

- session identityとpersistent identityを分けることで、同型deviceや同一Serialでもlive入力状態を共有しない。
- ProfileをLogical Device側へ残すことで、機器交換時にPhysical Bindingだけを差し替えられ、将来のRig / Parent PresetもLogical Device集合として拡張できる。
- LocationIDやcookieの安定性を仮定せず、実機到着前の推測実装を避けられる。
- Generic HIDを既存Action Layerへ合流させることで、ACK05とrekordbox adapterの責務を複製せず、Generic層へrekordbox固有知識を漏らさない。

## 影響

- Devices UIはRegistry / Identify / Binding file store APIを利用できるが、今回の変更ではUIを作らない。
- Serialを持たないdeviceや同一Serial複数台は、将来の明示Identify / Rebind UXまたは追加の実機根拠が必要になる。
- probeはcookieとdescriptor重複を表示するため、実機到着後にpersistent mapping schemaの判断材料を採取できる。
- Generic HIDのruntime mappingとconfig migrationは後続変更になる。実機根拠によりversion 10が必要と判明した場合だけmigrationを追加する。
- Physical Device → Binding → Logical Device → Profile → Action → rekordbox Adapterの責務境界を維持する。

## 代替案

- LocationIDをpersistent identityにする案: hub / port変更や別個体差し替えで誤bindingするため不採用。
- IOHIDElement cookieを入力の永続IDにする案: 再接続時の安定性を確認できず、同じUsageの複数element問題も隠すため不採用。
- VID / PIDだけでRebindする案: 同型複数台を区別できないため不採用。
- Generic HIDから直接rekordbox shortcutを送る案: Action定義、hold/repeat、Deck解決を二重管理するため不採用。
- 実機到着前にconfig v10とGeneric mapping schemaを追加する案: evidenceなしに恒久形式を固定するため不採用。

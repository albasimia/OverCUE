# Generic HIDのnative入力抑止はCGEvent相関方式を採用する

Date: 2026-09-03
Status: accepted

## Context

Serial-backed Generic HIDを通常runtime / Shortcuts Learnへ接続したところ、keyboard / Consumer ControlとしてのmacOS標準入力がOverCUE入力と同時に発火した。

`kIOHIDOptionsTypeSeizeDevice`はAPI上はsystem / other clientsへのevent deliveryを止めるが、keyboard-class HIDでは通常ユーザーprocessからexclusive openが`kIOReturnNotPrivileged (0xE00002C1)`になる実機挙動を確認した。root / privileged helperを通常runtimeの前提にはしない。

## Decision

- Generic HID runtimeは`SeizeDevice`を試みても`kIOReturnNotPrivileged`ならshared openへfall backする。
- 登録済みGeneric HIDだけを別のshared IOHID observerで監視する。
- concrete keyboard / Consumer Control inputを受けた直後、対応するdownstream CGEventを短時間だけpendingとして相関し、そのeventだけactive CGEventTapでdropする。
- 相関できない入力はfail-openとし、ユーザーの通常キーボード入力を広く抑止しない。
- Shortcuts Learnは通常runtimeと同じGeneric HID owner / suppression lifecycleを使い、専用mapping UIは持たない。
- root helper / LaunchDaemonによるtrue exclusive captureは将来必要になった場合の別案とし、現MVPの前提にはしない。

## Initial verified mapping target

SDINNOVATION / SIDE-KEYBOARD (`0816:246E`):

- Keyboard usage `0x59`–`0x5C` -> Keypad 1–4
- Consumer `0xE9` -> Volume Up
- Consumer `0xEA` -> Volume Down
- Consumer `0xE2` -> Mute

実装は製品固有VID/PIDのhard-codeではなく、登録済みGeneric HIDのUsageからnative eventを相関する。

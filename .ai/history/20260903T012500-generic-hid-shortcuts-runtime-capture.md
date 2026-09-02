# 2026-09-03 Generic HID Shortcuts runtime capture

## Goal

SIDE-KEYBOARDをDevices内の専用Mapping UIではなく既存Shortcutsから設定し、Generic HIDのexclusive ownership handoffで発生していた`0xE00002C1 / 0xE00002C5`を構造的に解消する。

## Evidence

- SIDE-KEYBOARDはVID `0x0816`, PID `0x246E`, Serial `3F8701678182`。
- 4 keys + Knob Right / Left / Pushのpersistent descriptorは実機確認済み。
- Devices登録、同一USB port再接続、別hub port移動でも同じ`SIDE-KEYBOARD 1` Logical Deviceへ解決することを実機確認済み。
- 通常Generic HID runtimeが起動中はSIDE-KEYBOARDのnative Keypad / Volume入力がmacOSへ流れず、OverCUE終了時にnative挙動へ戻るため、runtimeのexclusive owner自体は成立している。
- 旧Learn実装はruntimeを閉じて別IOHIDManagerを開くため、composite HIDのownership transferで`kIOReturnExclusiveAccess` / `kIOReturnNotPrivileged`が発生した。

## Changes

- DevicesのGeneric HID専用mapping UI/modelを撤去済み。
- Shortcuts INPUT列へACK05とGeneric HID assignmentを統合。
- `GenericHIDRuntimeCoordinator`へcapture modeを追加。通常runtimeが保持する同じexclusive IOHIDManagerでpersistable input descriptorをLearnする。
- capture mode中はGeneric HID eventをAction Layerへ流さず、最初のpersistent binding keyをShortcutsへ返す。
- `GenericHIDShortcutCaptureBroker`を追加。既存`ShortcutSettingsModel.beginCapture()`が呼ぶ`runtimeBridge.stop()`を、unified capture時だけ「ACK05停止 + Generic HID capture mode開始」へ変換する。
- capture終了時、Generic HIDはclose/reopenせずそのままruntimeへ戻し、ACK05 CLIだけ再起動する。
- Generic HID専用`GenericHIDLearnMonitor`はmapping Learn経路から外れた。Identify/Rebindとは分離。

## Verification pending

GitHub connector環境のためmacOS local build/testは未実施。

次の実機確認:

1. `git pull && ./Scripts/build-app.sh`
2. Shortcuts > P Deck 1 > 任意Actionの編集開始
3. SIDE-KEYBOARD入力でassignmentが保存され、`0xE00002C1 / 02C5`が出ない
4. ACK05入力でも従来どおりassignmentできる
5. Learn後、SIDE-KEYBOARD native Volume/KeypadがmacOSへ漏れず、割当Actionのみ動作する
6. Rebindは別途Devices経路で確認する

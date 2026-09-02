# Rebind後のinput runtime経路を監査

- Date: 2026-09-03
- Branch: `codex/performance-4deck`

## 目的

ACK05 USBとGeneric HID（SIDE-KEYBOARD）の両方で、DevicesのRebind後にPhysical Device identityがLogical Device / Preset / Action runtimeへ正しく反映されるかを静的に監査し、帰宅後の実機切り分け手順を準備する。

## 監査結果

現行実装ではRebind自体のfresh-config反映経路に共通の欠落は確認できなかった。

- `DevicesView`はIdentify / Rebind開始前にcontroller runtimeを一時停止し、操作完了後に元の有効状態ならruntimeを再起動する。
- `DeviceManagementModel`はRebindを`OverCUEConfigurationFileStore.updateCurrent`でdiskへ保存し、`OverCUEConfigurationChangedNotification`を送信する。
- ACK05 USBは`HIDPhysicalDeviceDescriptor.sessionIdentifier`で`ack05USBSlotIdentifier`を優先するため、同じ`locationID`を持つ3 IOHID interfaceが同じruntime sessionへ解決される。
- ACK05 USB bindingは`usb-slot:<locationID>`を`legacyDeviceIdentifier`へ保存し、Rebind直後の新しいCLI processはdisk上のfresh configからbindingを解決する。
- ACK05 CLIはHID入力の直前にもconfig revisionを確認し、変更時はconfig / mappingを再読込してから入力を処理する。
- Generic HID runtimeはSerialをpersistent identityとして使用し、configuration change時にconfigを再読込して`bindingResolution`からruntime stateを再構築する。
- Generic HID native suppressorも登録済みGeneric HID bindingからIOHID match条件を作る。

したがって、Rebind直後にもACK05 USBとSIDEの両方がrekordboxを操作できない場合は、UI上のstale bindingだけを原因とみなさず、runtime上の`Physical Device -> Logical Device -> Preset -> Action -> rekordbox output`を実機ログで確認する。

## 診断準備

`Scripts/diagnose-input-runtime.sh`を追加した。

- `bash Scripts/diagnose-input-runtime.sh config`
  - current configのPhysical Binding / Logical Device / Group Presetを表示する。
- `bash Scripts/diagnose-input-runtime.sh side`
  - Generic HID runtime diagnosticsとnative suppression diagnosticsを有効にした状態でOverCUE.appをterminalから起動し、SIDEのraw input / Logical Device / Preset / mapping / rekordbox shortcut / native event dropを観測する。
- `bash Scripts/diagnose-input-runtime.sh ack05 [preset-number]`
  - appでBind/Rebind済みのconfigを使い、bundled `overcue-cli`を直接起動してACK05 session / profile / Action / rekordbox shortcut経路をstdoutで観測する。

ログは`.build/input-diagnostics/`へ保存する。

## 実機で確認する最小ゲート

1. Controller InputをONにする。
2. ACK05 USBをRebindし、直後に1 inputだけ押してAction発火を確認する。
3. SIDEをRebindし、直後に1 inputだけ押してraw input -> mapping -> shortcut送信を確認する。
4. SIDEでは同じ入力についてnative Keypad / Volume / MuteがSuppressorでdropされるかを同時に確認する。
5. どこまでログが到達したかで、identity / binding / preset / Action / rekordbox output / suppressionを分離して判断する。

## 検証

GitHub上の静的監査と診断helper追加のみ。macOS実機build / runtime testは帰宅後の確認待ち。

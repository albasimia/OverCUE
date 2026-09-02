# Generic HID mappingはShortcutsへ統合する

- Date: 2026-09-03
- Status: accepted

## Context

Generic HIDの実機検証後、Devices detail内へ専用のGeneric HID Mapping / Learn UIを追加した。しかしACK05の既存Shortcuts captureとは別のruntime停止・exclusive capture・runtime復帰経路になり、`kIOReturnExclusiveAccess`のownership handoffが二重管理になった。

また、Logical DeviceへPresetを紐づけた後に入力割り当てだけ別画面で編集する構造は、PresetをAction Mappingの単位として扱う既存UIと一致しない。

## Decision

- DevicesはPhysical Binding / Logical Device / Profile / Group Preset assignmentだけを扱う。
- Action Mappingの編集面はShortcutsへ一本化する。
- Shortcutsの1つのedit actionでACK05 captureと登録済みGeneric HID captureを並行して待ち受ける。
- 先に入力されたPhysical Inputを、現在選択中Presetの選択Actionへ割り当てる。
- Generic HIDの表示ラベルにはLogical Device名とLearn済みdescriptor名を含める。
- Generic HID専用のDevices Mapping UI / Modelは削除する。
- HID ownership handoffの一時的な`kIOReturnExclusiveAccess`はUIの固定waitではなくHID open層のretryで扱う。

## Persistence

現段階では既存実機テストで作成済みの割り当てを失わないため、Generic HID adapter固有の`generic-hid.json` persistenceは維持する。ただしこれはUI上の別Mapping Sourceではなく、Preset stable ID + Logical Device IDに従属するadapter persistenceとする。

将来config schemaへ統合する場合も、Shortcutsを唯一のMapping編集面とする本決定は維持する。

## Consequences

- ユーザーはPresetを選び、通常のShortcuts画面だけでACK05 / Generic HIDを混在して割り当てられる。
- Devices画面でAction Mappingを意識する必要がなくなる。
- ACK05とGeneric HIDのcapture lifecycleを別UIで維持する必要がなくなる。
- Generic HID実機descriptor検証結果（Keypad 1-4 / Consumer Volume +/- / Mute）はそのままLearn adapterで利用できる。

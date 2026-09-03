# Separate Shortcuts editor Preset from runtime orchestration

- Change ID: `20260904T014017-89c027`
- 状態: 採用


## 背景

複数Logical Deviceが異なるPresetを同時使用できるようになった後も、Shortcutsの`selectedGroup` / `selectedPresetGroupID`がruntime statusで更新されていた。そのためeditorでPresetを選ぶ操作とLogical Deviceごとの実行Presetが相互に上書きし、Preset selectorの往復、Group Preset controlの再送、Learn途中の保存先変動が起き得た。

直前のstatus suppressionはLearn中だけ通知を別名へ逃がしていたが、editor stateとruntime stateのownerが同じままなので通常Preset切替のfeedback loopは解消しなかった。またGeneric HID mappingはGroup Preset assignmentを保存・表示scopeへ使い、ユーザーがShortcutsで選んだPresetと不一致になっていた。

## 決定

- ShortcutsのPreset selectionとMode表示はeditor専用stateとする。
- Runtime StatusはLogical Device / physical sessionごとのruntime stateだけを更新し、Shortcutsのeditor Preset、editor Mode、mapping表示を変更しない。
- ShortcutsのPreset / Mode編集はconfigを更新するが、device runtime controlを送らない。
- Group PresetはLogical Deviceごとのruntime開始Presetを適用するorchestration専用とし、shortcut mappingの編集scopeに使わない。
- Generic HID mappingの表示・保存・削除は`入力元Logical Device ID + editor Preset stable ID`へ統一する。Learn開始時のeditor Preset IDをsession contextへ固定し、途中のRuntime StatusやGroup Preset変更では保存先を変えない。
- Unified Learnは単一session state machineが所有する。ACK05とGeneric HIDは独立backendとして開始し、一方の開始失敗後も他方を継続する。最初に入力をclaimしたbackendだけが保存と終了を行い、進行中sessionを別のLearn要求で置換しない。
- `48eac82`で導入したruntime status suppression gateとone-shot capture brokerは撤去する。

## 理由

runtime Presetは複数device分が同時に存在するため、単一のeditor selectionへ同期する正しい写像がない。状態のownerを分ければnotificationの順序やdelayに依存せずfeedback loopを除去できる。

mapping編集のユーザー意図はShortcutsで選んだPresetにあり、Group Presetは演奏開始構成である。両者を分離することで、同じLogical Deviceでも複数Presetのmappingを明示的に編集できる。Learn lifecycleも単一ownerにすることで、ACK05 capture失敗がGeneric HID sessionを終了する、あるいは一方のcallbackが二重cleanupする経路をなくせる。

## 影響

- ShortcutsのPreset selectorはruntime操作ではなく純粋な編集対象selectorになる。
- Group Preset切替とdevice接続時のruntime適用は`GroupPresetRuntimeCoordinator`と各runtime adapterだけが担当する。
- Generic HID sidecar schemaはversion 1、main configはversion 10のままでschema migrationは不要。
- Runtime Statusは引き続きdevice-scopedな状態表示と入力ハイライトtargetに利用できるが、editor stateへは書き戻さない。
- Learn中にeditor Presetが削除された場合は、別Presetへfallback保存せずエラーとして終了する。

## 代替案

- Runtime Statusのdebounce / delay / suppression: event順序を隠すだけでownership競合を残すため不採用。
- Group Preset assignmentをGeneric HID mapping scopeとして継続: runtime orchestrationとeditor intentが一致しない複数device構成で誤保存するため不採用。
- ACK05とGeneric HIDに別々のLearn UI/session ownerを維持: Shortcutsを唯一のmapping UIとする既存決定に反し、終了処理とruntime handoffを二重化するため不採用。

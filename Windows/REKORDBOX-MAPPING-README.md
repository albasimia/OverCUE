# rekordbox keyboard mapping for OverCUE

[日本語](#日本語) | [English](#english) | [简体中文](#简体中文)

`OverCUE-Performance.mappings` is the tested Windows rekordbox keyboard mapping for OverCUE. F13–F24 are reserved for the XPPen-to-OverCUE bridge and are not assigned directly to rekordbox functions.

## 日本語

1. rekordboxを起動し、環境設定の「キーボード」を開きます。
2. PERFORMANCEモードで`OverCUE-Performance.mappings`をインポートし、使用するマッピングとして選択します。
3. 環境設定を閉じ、デッキまたは波形領域へフォーカスを戻します。
4. OverCUEを再起動するか、画面の「再読み込み」を押します。

OverCUEは選択中のPERFORMANCEマッピングを`rekordbox3.settings`から読み取ります。EXPORTマッピングが明示されていない、存在しない、または空の場合は`Export (Preset)`を読み取ります。対象機能にrekordboxショートカットが割り当てられていない場合、OverCUEはキーを推測送信しません。

## English

1. Start rekordbox and open Preferences > Keyboard.
2. In PERFORMANCE mode, import `OverCUE-Performance.mappings` and select it as the active mapping.
3. Close Preferences and return focus to the deck or waveform area.
4. Restart OverCUE or click Reload in its window.

OverCUE reads the selected PERFORMANCE mapping from `rekordbox3.settings`. If the EXPORT mapping is not explicitly selected, missing, or empty, it reads `Export (Preset)`. If a target function has no rekordbox shortcut, OverCUE does not guess a key combination.

## 简体中文

1. 启动 rekordbox，然后打开“首选项”>“键盘”。
2. 在 PERFORMANCE 模式下导入 `OverCUE-Performance.mappings`，并将其选为当前映射。
3. 关闭“首选项”，将焦点返回到 Deck 或波形区域。
4. 重新启动 OverCUE，或点击窗口中的“重新载入”。

OverCUE 会从 `rekordbox3.settings` 读取当前选择的 PERFORMANCE 映射。如果 EXPORT 映射未明确选择、不存在或为空，则读取 `Export (Preset)`。如果目标功能没有分配 rekordbox 快捷键，OverCUE 不会猜测并发送按键组合。

# 2026-09-09 Web Shortcuts editor migration

## Context

`codex/web-ui`でnative app shell + WKWebView、Group Preset、DevicesまでWeb UIへ移行した後、SwiftUI版Shortcutsの主要編集機能をWeb UIへ移植した。

## Implementation

- `WebShortcutEditingCoordinator`を追加し、Web DTO / command変換だけを担当させた。
- mapping/config/runtime ownershipは既存`ShortcutSettingsModel`に残した。
- Generic HID Learnは既存`GenericHIDShortcutCaptureModel`を共有し、Web専用capture pathを作っていない。
- ACK05 mapからkey / dialを選択するとnative modelのAction選択と同期する。
- Action一覧から選択するとACK05側のassigned/highlighted stateへ同期する。
- Preset切替、add、rename、delete、rekordbox mode切替、Reload、device rotationをWebから操作可能にした。
- Action rowからUnified Learn開始、cancel、ACK05 + Generic HID binding削除、overwrite confirm/cancelを操作可能にした。
- Learnは既存session owner、editor Preset pinning、ACK05/Generic HID first-wins、競合解決、runtime復帰を利用する。
- Device IdentifyとShortcut Learnは同時開始をWeb API境界で禁止した。
- `GET /api/v1/shortcuts/panel`は初回load / mutation用のfull editor model。
- `GET /api/v1/shortcuts/live`は50ms polling用で、ACK05 pressed key、dial activity、capture stateだけを返す。
- polling中のGETと編集PUTが競合した場合、古いlive responseが新panelを上書きしないようPinia側でpanel identity / mutation stateを確認する。
- Learn終了をlive pollingで検出した時だけfull panelを再取得し、新しいbinding表示を反映する。
- Generic HID Learnも既存inputが別Actionに割り当て済みの場合は即時上書きせずpending化し、ACK05と同じoverwrite confirmation経路へ入る。

## UI

- 左: ACK05 device map、Preset selector、Preset add/manage、rotation、physical input readout。
- physical pressed inputはgreen、selected / assigned highlightはaccent blue。
- 右: rekordbox mode、Reload、Learn/overwrite status、search、mapping summary、category折りたたみ、Action / rekordbox shortcut / INPUT columns。
- INPUTにはACK05 bindingとGeneric HID `device · input` labelを同じchip列で表示する。
- ACK05 map clickでActionが選択された場合、対象categoryを自動展開してAction rowを中央付近までsmooth scrollする。
- overwrite confirmationはACK05 / Generic HID共通のmodal dialogとして表示する。

## Verification status

2026-09-09実機確認:

- ACK05 physical press -> Web UI green表示: **OK**
- ACK05 map click -> Action selection同期: **OK**
- Action rowまでの自動scroll: 修正後の再確認待ち
- ACK05 overwrite Learn: 既存confirmation表示を確認済み。modal化後の再確認待ち
- Generic HID overwrite Learn: 修正前は警告なし即時上書きだった。共通confirmation化後の再確認待ち

このchat実行環境は`github.com`を名前解決できずrepo clone/buildを実行できない。GitHub Actions workflowもrepoに存在しないため、今回の追加修正は静的レビューまで。

次のローカルgate:

```sh
cd WebUI
npm run typecheck
npm run build
cd ..
swift build
swift test
swift run overcue-checks
./Scripts/verify-macos.sh
aal doctor
git diff --check
```

その後の実機gate:

1. ACK05 map clickで選択Actionのcategoryが自動展開され、対象rowまでscrollする。
2. ACK05既存inputへのLearnでmodal overwrite dialogが出て、Cancelでは既存割当維持、Replaceで上書きされる。
3. Generic HID既存inputへのLearnでも同じmodal overwrite dialogが出て、Cancelでは既存割当維持、Replaceで上書きされる。
4. ACK05 Learn、chord、dial、dial chord、removeが既存SwiftUIと同じ結果になる。
5. Generic HID Learnが対象Logical Device / editor Presetへ保存され、ACK05とのfirst-wins session競合が維持される。
6. Learn中のPreset / mode変更、Device Identify同時開始が拒否される。
7. Preset add / rename / delete、先頭Preset delete拒否、最後のPreset delete拒否を確認する。
8. Learn完了後にINPUT chipがfull panel refreshで更新される。
9. Shortcuts画面を離れた時にactive Learnがcancelされる。

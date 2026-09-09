# Web UIをOverCUEの主設定UIとして採用する

## Status

Adopted — 2026-09-08

## Context

OverCUEは本番DJ運用で3Deck構成まで実用確認でき、次の主要課題は設定UIになった。Preset / Group Presetの並び替え、Group内assignment編集、複数device状態の一覧はSwiftUIでも実装可能だが、Windows対応を含めると設定UIをプラットフォームごとに二重管理する利点が薄い。

現行CoreではPreset stable ID/order、Group Preset order/assignment、Logical Device、runtime ownership、config v10の責務境界が既に成立している。UI移行のためにこれらのownershipを変更しないことが重要。

## Decision

- 主設定UIをWeb UIへ移行する。
- frontendはVue 3 + TypeScript + Vite + Vue Router + Piniaを採用する。
- Piniaは状態共有の必要量だけでなく、Preset / Group Preset / Device / Runtime / Settingsの状態所在を明示するため最初から使用する。
- Web UIは`config.json`を直接読み書きしない。Swift側がloopback-only Local APIを提供し、既存のFileStore / runtime coordinatorを経由して更新する。
- Local APIは`127.0.0.1`だけにbindする。wildcard CORSを許可しない。write endpointは外部Webページからのlocalhost操作を防ぐorigin + startup-scoped session token境界を持つ。
- macOSの通常起動は**native app shell + WKWebView**とする。外部ブラウザを本番UIにはしない。
- built Vue assetsとLocal APIは同じ`127.0.0.1:4173`から配信し、WKWebViewはそのrootを表示する。Vue Router history routeはnative static serverが`index.html`へfallbackする。
- Vite `127.0.0.1:4174`はfrontend開発用だけに残し、`/api`をnative serverへproxyする。
- packaged appでは`WebUI/dist`を`OverCUE.app/Contents/Resources/WebUI`へ同梱する。開発時はrepo内`WebUI/dist`または`OVERCUE_WEB_UI_ROOT`を利用できる。
- 既存SwiftUI設定画面はWeb UIがfeature parityに達するまで削除せず、移行中の退避経路として`OVERCUE_NATIVE_UI=1`で起動可能にする。
- runtime、Generic HID、Learn、Group Preset baselineのownershipはこの移行では変更しない。
- macOS MenuBarExtraはruntime状態・active Group Preset・主ウィンドウへの入口へ薄くする。Preset個別表示を主役にしない。
- Preset order / Group Preset orderは既存`order`をSSOTとして永続化する。表示側だけで並び替えを持たない。
- drag and dropはVue wrapperを追加せず、SortableJSを薄いcomposableから直接利用する。

## Reorder invariants

Presetの`order`はruntime上のnumeric group番号でもあるため、単純な表示順変更ではない。並び替えでは以下を不変条件とする。

1. **Cycle Preset bindingを変化させない**
   - config v10ではCycle Preset系actionが先頭Presetに保存され、全Presetへoverlayされる。
   - 先頭Presetが変わる並び替えでは、旧先頭のCycle系bindingだけを新先頭へ移送する。
   - 新先頭に以前から存在したinertなCycle系bindingは削除し、並び替えだけで突然有効化されないようにする。

2. **deviceの現在のruntime Preset stable IDを変化させない**
   - order変更後は同じPreset IDのnumeric group番号が変わり得る。
   - active Group Preset baselineが変わっていない場合、`GroupPresetRuntimeCoordinator`は現在のruntime `presetID`を維持したまま新しいgroup番号へ再マップする。
   - Cycle Presetによる一時的なdevice-local runtime stateをGroup Preset baselineへ巻き戻さない。
   - Group Preset / assignment自体が変更された場合のみ、従来通りbaselineを再適用する。

## Phase 1 implementation

- `WebUI/`へVue / Router / Pinia scaffoldを追加。
- Storeを`presets` / `groupPresets` / `devices` / `runtime` / `settings`に分離。
- Swift appが`127.0.0.1:4173`でLocal APIを提供。
- `GET /api/v1/session`
- `GET /api/v1/snapshot`
- `PUT /api/v1/presets/order`
- `PUT /api/v1/group-presets/order`
- Vite dev serverは`127.0.0.1:4174`で`/api`をnative APIへproxyする。
- Preset / Group PresetをSortableJSでdrag reorderできる。
- macOS menu bar labelは個別Presetの`E/P + group number`ではなくactive Group Preset名を表示する。

## Native app shell implementation

- `OverCUEWebUIAssetStore`がpackaged / developmentのbuilt frontend rootを解決し、hashed assetを配信する。
- Vue Routerのhistory routeは`index.html`へfallbackする。
- `OverCUEWebView`がWKWebViewを生成し、`http://127.0.0.1:4173/`を表示する。
- local server起動直後のlistener ready raceに備え、WKWebView初回navigationは有限回retryする。
- WKWebViewからloopback外のHTTP(S)へ遷移する場合はnative browserへ渡し、WebView内navigationは拒否する。
- `Scripts/build-app.sh`はWebUI buildを先に実行し、生成物をapp bundleへコピーしてからcodesignする。
- 通常の`WindowGroup`はWKWebViewを表示し、旧SwiftUIは`OVERCUE_NATIVE_UI=1`の場合だけ表示する。

## Feature migration implementation

- Group Preset Web UIは既存`GroupPresetManagementModel`を共有し、add / rename / delete / activate / reorder / device include / device→Preset assignmentをLocal API経由で操作する。
- Devices Web UIは共有`DeviceManagementModel`を使い、ACK05 / Generic HID identify、rebind、rename、Profile変更、Forget Bindingを操作する。Identify中だけruntimeを一時停止し、完了・失敗・cancel後に元のController Input設定へ復帰する。
- Shortcuts Web UIは`ShortcutSettingsModel`と`GenericHIDShortcutCaptureModel`を共有する。Web専用mapping/capture実装は作らない。
- `WebShortcutEditingCoordinator`はWeb DTO/command変換だけを担当し、ACK05 key/dial選択、Action選択、Preset切替・追加・rename・delete、rekordbox mode、Reload、binding削除、Overwrite確認、device rotationを既存native modelへ委譲する。
- Learnは既存Unified Learnをそのまま利用し、ACK05とGeneric HIDのどちらが先に入力されても同じsession owner・Preset pinning・競合解決・runtime復帰ルールを使う。
- Shortcuts画面は50ms read pollingで実入力のpressed/dial stateとLearn状態を表示するが、write中はpoll refreshを止めてmutation応答を巻き戻さない。
- Device IdentifyとShortcut Learnは同時に物理HID ownershipを要求するため、Web API境界で同時開始を許可しない。

## Migration boundary

native shell / static asset serving、Group Preset編集、Device管理、Shortcuts編集/Learnの主要配線までWeb UIへ移植した。旧SwiftUI設定画面の縮退は、Web UIのローカルtypecheck/build、Swift build/test/checks、実機ACK05/Generic HID Learn、Preset CRUD、Device Identify、Group Preset操作のfeature parity確認後に行う。

## Verification

frontend変更時は最低限`npm run typecheck`と`npm run build`を実行する。Swift側接続を追加した時点から既存の`swift build` / `swift test` / `swift run overcue-checks` / `./Scripts/verify-macos.sh` / `aal doctor` / `git diff --check`も従来通り必要。

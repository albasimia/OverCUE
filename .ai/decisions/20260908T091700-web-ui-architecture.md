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
- SwiftUI設定画面はWeb UIがfeature parityに達するまで残す。runtime、Generic HID、Learn、Group Preset baselineのownershipはこの移行では変更しない。
- macOS MenuBarExtraはruntime状態・active Group Preset・Web UIへの入口へ薄くする。Preset個別表示を主役にしない。
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

## Migration boundary

Phase 1では既存SwiftUIを削除しない。次段階でstatic asset servingを追加し、Group Preset編集、Device管理、Shortcuts編集を順にWeb UIへ移植してfeature parityを作った後、native設定UIを縮退する。

## Verification

frontend変更時は最低限`npm run typecheck`と`npm run build`を実行する。Swift側接続を追加した時点から既存の`swift build` / `swift test` / `swift run overcue-checks` / `./Scripts/verify-macos.sh` / `aal doctor` / `git diff --check`も従来通り必要。

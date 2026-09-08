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
- Local APIは`127.0.0.1`だけにbindする。wildcard CORSを許可しない。write endpoint導入時は外部Webページからのlocalhost操作を防ぐorigin/session-token境界を同時に実装する。
- SwiftUI設定画面はWeb UIがfeature parityに達するまで残す。runtime、Generic HID、Learn、Group Preset baselineのownershipはこの移行では変更しない。
- macOS MenuBarExtraは最終的にruntime状態・active Group Preset・Web UIへの入口へ薄くする。Preset個別表示を主役にしない。
- Preset order / Group Preset orderは既存`order`をSSOTとして永続化する。表示側だけで並び替えを持たない。
- drag and dropのライブラリは並び替え実装段階で追加する。初期scaffoldでは導入しない。

## Initial implementation boundary

最初のコミットでは`WebUI/`へfrontend scaffold、API client contract、Pinia store境界、主要routeを追加する。Swift runtime/configには接続しない。次段階でLocal API、static asset serving、既存SwiftUI機能の段階移植を行う。

## Verification

frontend変更時は最低限`npm run typecheck`と`npm run build`を実行する。Swift側接続を追加した時点から既存の`swift build` / `swift test` / `swift run overcue-checks` / `./Scripts/verify-macos.sh` / `aal doctor` / `git diff --check`も従来通り必要。

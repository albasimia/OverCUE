# Cache immutable runtime data without changing HID ownership or timing

- Change ID: `20260904T084205-a76908`
- 状態: 採用


## 背景

SIDEのキーとノブだけに体感遅延があるとの報告。実機操作なしで監査すると、GUIのmain runloopにinput処理とstatus起点のJSON再decodeが同居し、入力ごとに不変metadataとshortcutを再構築していた。不要コード整理と低リスクの遅延対策が依頼された。

## 決定

- 不変処理をcacheするが、Action、Preset、capture、native抑止の意味と時系列は変更しない。
- config cacheはread-only。revisionを毎回確認し、通知でもinvalidate。不正/欠損時に古い値を返さない。symlink先のrevisionを使い、read/stat間の置換があればcacheしない。書込とGUI merge baselineへ流用しない。
- HID metadata cacheのcookieはlive interface内でのみ使用し、disconnectとruntime再起動で破棄。永続descriptorやPhysical Bindingには使わない。
- unused exclusive Learn monitorのみ削除。現行shared runtime captureを正本とする。
- 診断機能はdefault OFFで残す。性能測定値は実機end-to-endとは分離する。
- Decision 20260904T014017-89c027のownershipを維持する追加決定であり、supersedeしない。

## 理由

重複作業削減はイベント順序やデバイス識別を変更せず検証できる。稼働中のbooleanや待機を単に消すと新しい競合や入力漏れを導入する危険がある。

## 影響

config v10 / sidecar v1、UI、ユーザーmapping、ACK05実装は不変。main-thread依存と初回XML読込は残るため、低遅延を保証したとは扱わない。cacheの失効条件を将来変更する際もruntime開始/停止とconfig freshnessの回帰を維持する。

## 代替案

HID/actionのbackground移動はteardown/output ownership変更が必要なので今回は見送る。抑止8ms短縮はraw/native相関の実測なしでは入力漏れリスクがあるため見送る。XML eager loadはsnapshot時点を変えるため、更新検知仕様と共に別途検討する。

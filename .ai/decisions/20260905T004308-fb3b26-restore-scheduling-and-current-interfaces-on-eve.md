# Restore scheduling and current interfaces on every Generic HID runtime start

- Change ID: `20260905T004308-fb3b26`
- 状態: 採用


## 背景

初回起動は正常だがstop/start後にGeneric HIDのmatch/input callbackがなくなる実機報告。
旧実装はinit時のrunloop scheduleを永続とみなしていたが、
[Apple公開実装](https://github.com/apple-oss-distributions/IOKitUser/blob/main/hid.subproj/IOHIDManager.c)では
Closeはunscheduleし、Openはそれを復元しない。さらに破棄済みruntime stateの復元をmatch再配送に依存していた。

## 決定

- 同じshared IOHIDManagerを使用し、成功した各startでmain-runloop scheduleを復元する。
- startのcurrent-device snapshotとhotplug matchを、単一のidempotent登録/preload/state解決経路へ渡す。
  再配送されるmatch通知だけを既接続device復元の条件にしない。
- stopでcallback受理を止め、live interface/catalog/sessionを破棄。Open失敗は部分openもCloseする。
- snapshot未取得やpreload失敗はfail-closed。config reload/reconnect/next startで再試行でき、入力内scanへ戻さない。
- shared runtimeでLearnする既存Decision、editor/runtime ownership、cacheの生存境界を補足する。
  過去Decisionをsupersedeせず、製品仕様/schemaは変更しない。

## 理由

Schedule復元がcallback消失の直接原因を解消する。snapshot復元は通知順序への依存を除き、
既存identity/groupingとcatalogを使えば二重実装なしで入力ready状態を再構築できる。
新しいthreadやmonitorを追加する必要はない。

## 影響

start/stopと一時Learn起動が同じ監視復帰契約を持つ。cookieはliveのみ、restart後は再構築。
初回750ms入力走査撤去、native correlation 8ms、Logical Device/Preset/mappingは不変。
preloadのmain-threadコストは残る。OS/UI実機確認はsynthetic/構造testsとは別ゲート。

## 代替案

- manager毎回生成：今回確認した欠落はSchedule復元であり、callback contextの新世代管理を増やす必要がない。
- snapshotだけ追加：監視unscheduleを直さずinput callback不在が残る。
- Scheduleだけ追加：既接続state復元をmatch再配送へ依存させる。
- 入力時再走査や固定sleep：latency修正を壊すか、ライフサイクル不備を時間で隠すため不採用。

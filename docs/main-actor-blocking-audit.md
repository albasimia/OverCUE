# UI設定操作のMainActor blocking調査・修正

2026-09-12、`codex/web-ui`起点。UI仕様、config v10、Generic sidecar v1、stable ID、localhost認証境界は維持。
実機で報告された数秒のビーチボールと、今回のコード上の原因特定・自動検証は区別する。修正後の実機QAは未実施。

## 修正前のcall chain

### Group Preset Activate / assignment

```text
Vue → PUT /api/v1/group-presets/active（または assignment/include）
→ OverCUEWebAPICoordinator.handle [MainActor]
→ GroupPresetManagementModel.activate / assignPreset [MainActor]
→ FileStore.updateCurrent [同期 flock / latest read / JSON decode / atomic write]
→ ConfigurationChanged distributed notification
  → GenericHIDRuntimeCoordinator [main runloop]
    → config read/decode → configureDeviceMatching → CopyDevices
    → registerCurrentInterfaces → metadata preload（ready catalogは既存でも再走査経路へ入る）
    → XML/key cache破棄 → runtime state更新 → deviceごとにsidecar read/decode
  → GenericHIDNativeEventSuppressor [main callback]
    → config read/decode → 毎回device matchingを再設定
  → ShortcutSettingsModel [MainActor]
    → config reconciliation → binding表示再構築 → 毎回rekordbox XML読込
  → GroupPresetRuntimeCoordinator [MainActor]
    → baseline signature比較 → device-scoped Preset control
```

Group Preset適用の所有者は既存のGroupPresetRuntimeCoordinator。通常statusでCycleによる一時状態を戻さず、baseline/assignment変更時だけ切り替える設計は変えない。

### Shortcut Remove

```text
Vue → PUT /api/v1/shortcuts/command (removeBindings)
→ WebShortcutEditingCoordinator [MainActor]
→ GenericHIDShortcutCaptureModel.removeBindings
  → editor Presetのscope解決 → sidecar read/modify/atomic write + notification
→ ShortcutSettingsModel.removeBindings
  → ACK05 key/chord/dial/dialChord編集 → configの3-way merge + locked write
  → rebuildBindings → restartRuntimeIfEnabled → runtime.start → stop
    → suppressor thread終了待ち
    → process.terminate → process.waitUntilExit [MainActor、上限なし]
    → ACK05起動 → Generic runtime起動
      → exclusive-access retryにThread.sleep(100ms)、16 attemptsで最大15回=約1,500ms
```

ACK05 bridgeには既にConfigurationChanged受信と入力前のconfig revision検査があり、最新profile/mappingを再構築する。mapping削除のためのhelper再起動は不要だった。

### Learn / overwrite / Preset変更

Learn開始はACK05 helperのexclusive claimを解放してからcapture monitorへ渡すため、終了待ち自体は必要。
保存はACK05 configまたはGeneric sidecarへ同期I/Oし、完了後にruntimeを再開していた。
Generic identifierのHIDManagerOpenRetryにもmain runloop上のThread.sleepが存在した。
Preset/Mode編集と設定通知ではrekordbox XMLの同期loadが追加の負荷になっていた。

## 修正後

```text
Group変更 → MainActorで入力値を確定
→ persistence専用serial queueでlocked latest read/modify/atomic write
→ MainActorへ結果を反映 → 既存通知
→ Generic runtime: backgroundでconfig + sidecar snapshotを取得
  → main runloopで差分判定
  → Generic physical bindingが変わったときだけmatching/列挙/preload
  → 既存stateとXML cacheを保持してrefresh
  → 既存Group coordinatorのdevice-scoped controlでPreset/Mode/mappingを切替
```

```text
Shortcut Remove → sidecar削除をawait → config merge保存をawait
→ 表示更新 + 既存ConfigurationChanged
→ ACK05は既存helper内でmapping更新、Genericはsnapshotからmapping更新
→ helper / Generic manager / suppressorの全restartなし
```

- Processの起動・所有はMainActor。終了待ちはtimer continuationでsuspendし、後続の起動とLearn handoffは直列化する。終了要求から2秒経っても終了しない当該childだけSIGKILLへ進む。cancel済みTaskでもbusy loopを起こさない。
- start/stop/captureの世代を管理し、古い起動結果による再開を防ぐ。captureは最初の入力のclaimを同期で確定し、その後の保存だけ非同期化。旧sessionのcallback・保存完了は次のsessionへ適用しない。
- HID retryはMainActorでIOHIDOpenを呼び、attempt間だけTask.sleepでsuspendする。identifierのcancelはretryを中断する。既存runloopのschedule、explicit start snapshot、hotplug登録経路は維持。
- native event suppressorは既存のHID専用runloopとevent-tap専用runloopを保持。ready/exit semaphore待ちを含むstart/stop/config matchingだけ専用lifecycle queueへ移した。8msのraw-event correlation待機は変更していない。
- Generic runtimeは一度読んだsidecar documentからdevice/Preset別mappingを解決する。Preset controlはreload中だけ保持して新snapshot適用後に処理する。mode変更時はheld output/resolver/repeatを解放する。
- sidecarのread-modify-write lockとatomic writeは保持。read-only読込はatomic replacementによる完全な旧/新documentを読み、writerのNSLockをUIから待たない。
- ConfigurationChangedのwire形式は変えず、受信側が実データ差分でreload範囲を判定する。旧CLIや外部writerとの互換性を保つ。
- Shortcut configはworkerで既存base/local/remote mergeを実行。await中に追加されたlocal変更も、完了時のreconciliationで保持する。orderのremote優先規則には変更なし。
- 通常config通知ではeditor Modeが変わった場合だけXMLを再読込し、XML load自体もworkerへ移した。
- reorder endpointもI/Oだけworkerへ移動。ドラッグ中draft、Save時1回のPUT、snapshot順序同期は変更なし。

## 変更ファイル

| 責務 | ファイル（Sources/OverCUEApp配下、別記を除く） |
| --- | --- |
| 非同期process handoff / backend lifecycle | OverCUECLIRuntime.swift、OverCUEProcessTermination.swift、GenericHIDNativeEventSuppressor.swift |
| I/O / 診断 | OverCUEPersistenceWorker.swift、GenericHIDMappingStore.swift |
| 差分hot apply | GenericHIDRuntimeCoordinator.swift、Sources/OverCUECore/OverCUEConfigurationReloadPlan.swift |
| Group Preset保存とnative呼出し | GroupPresetManagementModel.swift、GroupPresetViews.swift、GroupPresetsView.swift |
| Shortcut保存 / Learn / native呼出し | ShortcutSettingsModel.swift、GenericHIDShortcutCaptureModel.swift、ShortcutListView.swift、OverCUEApp.swift |
| API await伝播 | OverCUEWebAPICoordinator.swift、WebShortcutEditingCoordinator.swift |
| identifierの非同期retry | HIDManagerOpenRetry.swift、ACK05DeviceIdentifierMonitor.swift、GenericHIDDeviceIdentifierMonitor.swift、DeviceManagementModel.swift |
| 回帰テスト | Package.swift、Tests/OverCUEAppTests/*、Tests/OverCUECoreTests/ConfigurationReloadPlanTests.swift |

WebUIのソース、ConfigurationMerger、保存schemaは未変更。作業開始時から存在した未追跡のWebUI/package-lock.jsonは今回のcommit対象に含めない。

## 診断と測定

通常起動はログ無効。診断する場合はアプリを終了してから、ビルド済み実行ファイルを次の環境で起動する。

```sh
OVERCUE_PERFORMANCE_DIAGNOSTICS=1 ./dist/OverCUE.app/Contents/MacOS/OverCUE 2> /tmp/overcue-performance.log
```

mutation APIのoperation start/end、Group/Shortcut config saved、Generic runtime reload start/end、process exitが、thread=main/backgroundと開始からのelapsed msを出す。GET pollingは診断対象から外した。Generic起動/列挙の詳細は既存OVERCUE_GENERIC_HID_DIAGNOSTICS=1を併用できる。

2026-09-12の一時ファイルを用いたsynthetic測定例：

| 処理 | 観測 |
| --- | --- |
| Group activateのconfig保存 | background 0.691ms、operation end 0.728ms |
| Group assignmentのconfig保存 | background 0.532ms、operation end 0.557ms |
| ACK05 mapping削除のconfig保存 | background 0.641ms、operation end 0.677ms |
| 250ms生存するテストchildの終了待ち | elapsed 263.642ms、40ms後のMainActor heartbeatはchild生存中に実行 |
| lockを保持して200msかかるテストtransaction | 30ms後のMainActor heartbeatが保存完了前に実行 |

これらは実機のUI end-to-end測定ではない。修正前の実機msログは今回取得していない。修正前コードのretryは約1,500msの同期sleep、process待ちは上限なし。修正後は待ち時間そのものがあってもMainActorを占有しないことをテストした。接続device数・実config・権限状態での実測は下記QAで行う。

## 検証

- swift build：成功。
- swift test：61 tests、0 failures（既存54 + 追加7）。configuration reconciliation/order、Generic lifecycle/hotplug構造guard、Unified Learnの既存テストを含む。
- swift run overcue-checks：412 checks成功。
- npm run typecheck / npm run build：成功。Webソースは変更なしだがpackaging経路を確認。
- Scripts/verify-macos.sh：Universal app/helper (arm64 + x86_64)、ad-hoc codesign deep/strict成功。
- aal doctor：0 failures / 0 warnings。git diff --check：成功。
- Sources/OverCUEApp内のThread.sleep / waitUntilExit：残存なし。

## 残るリスク・実機QA

今回のテストはOSのHID callback配信や実機抑止を証明しない。Generic IOHIDOpen/Close・初回列挙・metadata preloadはmain runloop所有を維持し、起動/hotplug/実際のtopology変更時にはそのコストが残る。readyでないmetadataの再試行はtopology変更、再接続または明示Reload/restartで行う。
また、すべてのアプリI/Oを移したわけではない。軽いconfig表示用read、初期migration、Device管理/Preset CRUDの別経路、Generic初回入力時のXML cache missは追加の計測対象。今回の通常Group切替/Shortcut削除ではこれらの全restart経路を通らない。

1. ACK05 + 複数SIDEを接続しController Input ON。Groupを連続切替し、各deviceのPreset/Mode/action、stable identity/binding、ビーチボール不在を確認。ログに通常切替でconfig-reload列挙が出ないこと。
2. deviceをCycleで一時Presetへ移動。Group rename/reorder、Shortcut削除、editor選択では巻き戻らず、Group active/assignment変更時だけbaselineを適用すること。Groupから除外したdeviceを停止しないこと。
3. ACK05 key/chord/dial/dialChordとGenericのpress/正負relativeを削除し、再起動なしで出力が止まること。別device・別editor Presetのmappingを残すこと。
4. ACK05とGenericのLearnを3回以上連続実行。開始直後の入力、overwrite承認/取消、保存中cancel→次Learn、source切断、片backend失敗を確認。editorに固定したPresetへ保存し、重複完了・旧callback・勝手なruntime復帰がないこと。
5. Input OFF→Learn→保存/取消、ON/OFF連打、Identify/Rebind→cancel→再開を確認。helperの二重起動、exclusive access失敗、抑止threadの残存がないこと。
6. Genericの抜き差し・再接続・binding追加/削除で登録/metadataが復元し、登録deviceのnative eventだけ抑止、未登録はfail-openであること。
7. Web UIでPreset / Group Presetをdrag中は永続化せずSave後だけ確定順序がdropdownへ同期すること。OVERCUE_NATIVE_UI=1でもGroup編集、Mode変更、Learn/overwrite/削除が動くこと。

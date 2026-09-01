# Project Context

## 目的

OverCUEは、任意の物理入力インターフェースとrekordboxの間をつなぐソフトウェアアダプターである。XPPen ACK05を標準・First-classデバイスとして扱い、macOS版rekordboxのCUE仕込み、波形移動、Deck操作を一貫したAction体系へ変換する。rekordbox Freeプランでも利用できるキーボード・マウス操作を主経路としつつ、将来的なGeneric HIDや他入力アダプターを同じAction Layerへ接続できる構造を維持する。

## 現在のフェーズ

PERFORMANCE Deck 1〜4対応とmacOSローカルビルドは完了している。ACK05 1台でGroup/Profileを切り替えながらDeck 1〜3を操作する実地DJは成立済み。次の主フェーズは、複数ACK05の同時操作、Generic HID入力、Physical DeviceとLogical Deviceの分離を導入し、3Deck標準物理リグを成立させること。

## 現在地

- Swift Package ManagerでCore、SwiftUIアプリ、CLI bridge、probe、core checksを管理している。
- ACK05のHID入力、キー／任意数コード、Cue hold、Jump長押しリピート、ダイヤル操作をAction Layerへ変換する。
- 4つのGroupがあり、各Groupは`rekordboxMode`、`rekordboxDeck`、`waveformPosition`、キー／コード／ダイヤル割り当てを独立して保持する。
- PERFORMANCEではDeck 1〜4を選択できる。EXPORTではDeck指定を保持するが操作解決には使わない。
- rekordboxの選択中KeyMappings XMLを読み、commandIdから実際のキーボードショートカットを解決する。
- configはversion 8。version 1〜7からのmigrationとバックアップを持つ。
- `Scripts/verify-macos.sh`でdebug build、core checks、Universal Binary app生成、ad-hoc codesign検証を一括実行できる。
- 2026-08-30時点の4Deck対応はcommit `28631d4de001331d8aceaa96bf57f778cd9c2ac6`、branch `codex/performance-4deck`へpush済み。
- ACK05 1台のProfile切り替えによるDeck 1〜3操作は、実際のDJ運用で成立済み。
- DJM-750 original + macOS Tahoe 26.6.2 + DJM-750 driver 4.0.1 + rekordbox PERFORMANCE / External Mixerで、4ch独立出力を実機確認済み。
- 標準物理リグは3Deckを基本とし、1DeckあたりACK05 + 小型Generic HID（4キー + endless encoder想定）を組み合わせる。ソフトウェア上は4Deckを維持する。
- Generic HIDの候補実機としてKoolertron系小型マクロパッドを検証するが、OverCUEのUI・データモデルを特定製品へ依存させない。

## 制約

- 対象はmacOS 13以降、Swift 6以降、Apple Silicon／IntelのUniversal Binary。
- HID取得には入力監視、キーボード／マウス送信にはアクセシビリティ権限が必要。
- XPPenPenTabletがACK05入力を消費する場合がある。
- rekordboxが最前面のときだけキーボード／マウスイベントを送る。
- GitHub Actionsを唯一の検証経路にしない。macOSローカル検証を正本とする。
- 現在選択中の`Performance 1 (Preset)`ではDeck 1=`30xx`、Deck 2=`31xx`、Deck 3=`32xx`を実データで確認したが、Deck 4の割り当て行は存在しない。Deck 4=`33xx`は未確認事項として扱う。
- Core checksの成功だけで実機確認済みとは扱わない。
- Generic HIDはAdvanced / Best-effortとし、任意のvendor-specific HIDを無条件にサポートすると約束しない。

## 採用済みの決定

- 新しいDeck modeは作らず、既存の4 Groupへ対象Deckを持たせる。
- Deck依存操作は`ActionID + RekordboxDeck`からcommandIdへ解決し、Deck別Action定義を複製しない。
- commandIdの操作suffixは`RekordboxActionAdapter`をSingle Source of Truthとする。
- ユーザーが明示したGeneric `rekordbox:<commandId>`はDeck変換しない。
- 既存configの意味を優先し、旧既定Group 2だけをDeck 2 + 標準Actionへmigrationする。Group 3のEXPORT用途は変更しない。
- 波形ドラッグ座標はProfile共通ではなくGroupごとに保存・復元する。
- Freeプラン向けの主運用はマウス／キーボード出力とし、DDJ-SX互換MIDIは補助経路として残す。
- release appは`dist/OverCUE.app`へ生成し、`OverCUE`と`overcue-cli`の両方をarm64 + x86_64にする。
- ACK05はOfficial / First-class device、Generic HIDはAdvanced / Best-effortとして扱う。
- Physical DeviceとLogical Deviceを分離し、Profileや将来のParent PresetはLogical Deviceを参照する。
- Generic HID入力は可能な限りIOHIDのdevice sourceを保持した状態で扱い、同じキーコードを送る同型デバイス同士を区別できるようにする。
- 未登録Generic HIDの検出は受動的に行い、勝手に登録・画面遷移しない。登録はDevicesからAdd Generic Device → Identify/Learnで明示的に行う。
- 物理デバイス識別は固有Serialを最優先し、USB topology / locationは補助ヒントに留める。曖昧な場合はユーザーに対象デバイスを操作してもらいIdentify / Rebindする。
- 標準物理構成は3Deckとし、4Deckはソフトウェア能力とオプション拡張として残す。

## 変更してよい範囲

- 現行Action Layer、Group構造、migration方針に沿う局所的な実装・テスト・ドキュメント更新。
- 複数ACK05を物理個体ごとに分離する入力状態管理。
- Generic HIDのdevice-aware入力、Logical Device binding、Identify / Rebind、Learn、Devices UI。
- ローカル検証の再現性、エラー表示、未割り当て時の診断改善。
- 既存挙動を保持するための可逆なCore checks追加。

## 変更してはいけない範囲

- 明示なしにGroup 3の既定EXPORT用途や既存ユーザー設定の意味を変えない。
- Generic `rekordbox:<commandId>`を標準Action扱いして勝手にDeck変換しない。
- Generic HID対応をKoolertron固有モデルとして設計しない。
- 同型デバイスをVID/PIDだけで恒久的に個体識別したことにしない。
- USB topology / locationを永続的なLogical Device IDとして扱わない。
- 未登録HIDの接続を理由に設定画面へ自動遷移しない。
- 実データや実機で確認できていない項目を成功済みと記録しない。
- `.aal/logos/`を直接編集しない。
- 未追跡の`Windows/`、`_site/`をOverCUE macOS実装の一部として勝手に削除・追加しない。
- Ableton Live / Launchpad Xを使う演奏体系の検討を、明示なしにOverCUE製品機能へ取り込まない。現時点ではexplorationとして扱う。

## 未決事項

- 複数ACK05接続時のIOHID identityと入力状態分離の具体実装。
- Koolertron系Generic HIDのキー、encoder CW/CCW、encoder pushがmacOS IOHID上でどのUsage / Reportとして見えるか。
- 同型Generic HIDが固有Serialを持たない場合のbinding永続化と再接続UX。
- Devices画面、Logical Device命名、Profile assignment、Rebind / Forgetの最終UI。
- Parent Preset / Sceneの名称と実装時期。
- Deck 4の実際のKeyMapping commandIdを、Deck 4ショートカットが保存されたrekordbox XMLまたは実機動作で直接確認する。
- GitHub Actionsを復旧する場合、独自手順を重複させず`Scripts/verify-macos.sh`を呼ぶ構造にする。

## 参照文書

- `README.md`
- `specs/current-spec.md`
- `Sources/OverCUECore/RekordboxActionAdapter.swift`
- `Sources/OverCUECore/OverCUEConfiguration.swift`
- `Sources/OverCUECore/Resources/DefaultKeyMapping.json`
- `Sources/OverCUEChecks/main.swift`
- `Scripts/verify-macos.sh`
- `.ai/decisions/20260830T200000-28631d.md`
- `.ai/decisions/20260901T110700-c8f4b1.md`
- `.ai/decisions/20260901T110701-e31a76.md`

## 有効なモード

- implementation
- review
- reporting
- exploration
- conversation

## 次の行動

複数ACK05の同時操作とGeneric HIDのdevice-aware入力基盤を実装・実機検証し、Physical Device → Logical Device → Profile → Actionの経路を成立させる。

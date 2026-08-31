# Project Context

## 目的

OverCUEは、XPPen ACK05のダイヤルと10個のキーを、macOS版rekordboxのCUE仕込み・波形移動操作へ変換するアプリケーションである。rekordbox Freeプランでも利用できるキーボード・マウス操作を主経路とし、ACK05からDeck 1〜4を一貫したAction体系で操作できる状態を維持する。

## 現在のフェーズ

macOS版の実装・ローカル検証を継続中。基本機能とPERFORMANCE 4Deck対応は実装済みで、実機およびrekordbox側の未割り当てショートカットを使った確認が残っている。

## 現在地

- Swift Package ManagerでCore、SwiftUIアプリ、CLI bridge、probe、core checksを管理している。
- ACK05のHID入力、キー／任意数コード、Cue hold、Jump長押しリピート、ダイヤル操作をAction Layerへ変換する。
- 4つのGroupがあり、各Groupは`rekordboxMode`、`rekordboxDeck`、`waveformPosition`、キー／コード／ダイヤル割り当てを独立して保持する。
- PERFORMANCEではDeck 1〜4を選択できる。EXPORTではDeck指定を保持するが操作解決には使わない。
- rekordboxの選択中KeyMappings XMLを読み、commandIdから実際のキーボードショートカットを解決する。
- configはversion 8。version 1〜7からのmigrationとバックアップを持つ。
- `Scripts/verify-macos.sh`でdebug build、241件のcore checks、Universal Binary app生成、ad-hoc codesign検証を一括実行できる。
- 2026-08-30時点の4Deck対応はcommit `28631d4de001331d8aceaa96bf57f778cd9c2ac6`、branch `codex/performance-4deck`へpush済み。

## 制約

- 対象はmacOS 13以降、Swift 6以降、Apple Silicon／IntelのUniversal Binary。
- HID取得には入力監視、キーボード／マウス送信にはアクセシビリティ権限が必要。
- XPPenPenTabletがACK05入力を消費する場合がある。
- rekordboxが最前面のときだけキーボード／マウスイベントを送る。
- GitHub Actionsを唯一の検証経路にしない。macOSローカル検証を正本とする。
- 現在選択中の`Performance 1 (Preset)`ではDeck 1=`30xx`、Deck 2=`31xx`、Deck 3=`32xx`を実データで確認したが、Deck 4の割り当て行は存在しない。Deck 4=`33xx`の実機送信は未検証として扱う。
- ACK05実機、アクセシビリティ、rekordbox UI操作を伴う確認を、Core checksの成功だけで「実機確認済み」としない。

## 採用済みの決定

- 新しいDeck modeは作らず、既存の4 Groupへ対象Deckを持たせる。
- Deck依存操作は`ActionID + RekordboxDeck`からcommandIdへ解決し、Deck別Action定義を複製しない。
- commandIdの操作suffixは`RekordboxActionAdapter`をSingle Source of Truthとする。
- ユーザーが明示したGeneric `rekordbox:<commandId>`はDeck変換しない。
- 既存configの意味を優先し、旧既定Group 2だけをDeck 2 + 標準Actionへmigrationする。Group 3のEXPORT用途は変更しない。
- 波形ドラッグ座標はProfile共通ではなくGroupごとに保存・復元する。
- Freeプラン向けの主運用はマウス／キーボード出力とし、DDJ-SX互換MIDIは補助経路として残す。
- release appは`dist/OverCUE.app`へ生成し、`OverCUE`と`overcue-cli`の両方をarm64 + x86_64にする。

## 変更してよい範囲

- 現行Action Layer、Group構造、migration方針に沿う局所的な実装・テスト・ドキュメント更新。
- ローカル検証の再現性、エラー表示、未割り当て時の診断改善。
- 既存挙動を保持するための可逆なCore checks追加。

## 変更してはいけない範囲

- 明示なしにGroup 3の既定EXPORT用途や既存ユーザー設定の意味を変えない。
- Generic `rekordbox:<commandId>`を標準Action扱いして勝手にDeck変換しない。
- 実データや実機で確認できていない項目を成功済みと記録しない。
- `.aal/logos/`を直接編集しない。
- 未追跡の`Windows/`、`_site/`をOverCUE macOS実装の一部として勝手に削除・追加しない。

## 未決事項

- Deck 4の実際のKeyMapping commandIdを、Deck 4ショートカットが保存されたrekordbox XMLまたは実機動作で直接確認する。
- ACK05実機でDeck 1〜4切り替え、Group別波形ドラッグ、Cue hold、Jump repeat、コード操作を通しで確認する。
- GitHub Actionsを復旧する場合、独自手順を重複させず`Scripts/verify-macos.sh`を呼ぶ構造にする。

## 参照文書

- `README.md`
- `specs/current-spec.md`
- `Sources/OverCUECore/RekordboxActionAdapter.swift`
- `Sources/OverCUECore/OverCUEConfiguration.swift`
- `Sources/OverCUECore/Resources/DefaultKeyMapping.json`
- `Sources/OverCUEChecks/main.swift`
- `Scripts/verify-macos.sh`

## 有効なモード

- implementation
- review
- reporting
- exploration
- conversation

## 次の行動

Deck 4ショートカットを含む実データを取得し、`33xx`規則と実際のrekordbox動作を照合する。

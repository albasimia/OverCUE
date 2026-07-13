# OverCUE Windows版 開発・配布方針

更新日: 2026-07-13

## 1. 基本方針

Windows版はC# / .NET 10 / WPFでネイティブ実装する。macOS版Swiftコードとのバイナリ共有は行わず、次の仕様とデータを共有する。

- Action IDとrekordbox commandId
- 設定JSONの論理構造と設定バージョン
- デフォルトキーマッピング
- 日本語・英語・簡体字中国語の翻訳JSON
- ACK05入力とAction解決のテストベクトル

Windows版は設定画面、通知領域、入力監視、Action解決、rekordboxへの`SendInput`を単一プロセスにまとめる。入力調査用の`OverCUE.Probe`だけを別プロセスとする。

## 2. 対象環境

- Windows 10 22H2 / Windows 11
- x64
- 自己完結型.NET 10アプリケーション
- XPPen ACK05（USB / Bluetooth Low Energy）
- XPPen Tablet Driver 4.0.17でエクスポートした同梱プロファイル
- rekordbox 7
- 通常ユーザー権限

ARM64、複数ACK05の同時操作、自動更新、Windowsログイン時の自動起動は初回リリースの対象外とする。

## 3. ACK05入力方式

実機検証の結果、XPPenドライバー有効時はACK05のHIDレポートをOverCUEが直接取得できない。正式なWindows構成では、同梱するXPPenプロファイルでACK05を次の予約キーへ割り当てる。

- K1〜K10: F13〜F22
- ダイヤル反時計回り／時計回り: F23／F24

OverCUEは低レベルキーボードフックでF13〜F24を取得してACK05入力へ戻し、他アプリへ渡さない。XPPenドライバーを使用しない既存環境との互換性のため、VID `28BD` / PID `0202`のキーボードRaw InputとACK05既定ショートカットのデコードも維持する。

`RIDEV_NOLEGACY`を他プロセスへのグローバルな入力抑止手段としては使用しない。デバイスを推測する時刻相関フックや、署名が必要なフィルタードライバーも現在の製品構成には採用しない。

## 4. コンポーネント境界

`OverCUE.Core`にはOS非依存ロジックを置く。

- ACK05キーボード入力Decoder
- Action Layer、Cue保持、同時押し、長押し状態機械
- Jump加速とダイヤル加速
- 設定モデルと移行
- rekordbox commandIdアダプター

`OverCUE.Windows`にはWindows固有処理を置く。

- Raw InputとF13〜F24予約キーフック
- `SendInput`によるキーボード・マウス出力
- rekordbox最前面プロセス判定
- 波形位置保存とドラッグ
- `%LocalAppData%\OverCUE`への設定保存
- WPF設定画面、言語切替、タスクトレイ

## 5. 現行機能

- EXPORT / PERFORMANCEモードと4グループ
- Deck 1 / Deck 2の初期マッピング
- Cue保持、Play/Pause、Memory Cue、Hot Cue、Quantize
- Jump長押し加速、Hot Cue削除、Memory Cue移動
- キー／任意数の同時押し／ダイヤル／キー保持＋ダイヤルの再割り当て
- rekordboxの割り当て済みショートカット一覧、検索、カテゴリ折りたたみ
- デバイス図と一覧の双方向選択、青い選択表示、緑の実入力表示
- デバイス図の90度回転と向き保存
- 日本語・英語・簡体字中国語の即時切替と選択保存
- タスクトレイ常駐

rekordboxのキーボード・マウス出力はrekordboxが最前面のときだけ行う。対象commandIdにショートカットがない場合は推測せず、未割り当てとして表示する。

## 6. 設定とrekordbox連携

OverCUE設定は`%LocalAppData%\OverCUE\config.json`、UI状態と言語選択は同じ`OverCUE`ディレクトリへ保存する。

rekordboxは`%AppData%\Pioneer\rekordbox6`の設定と`KeyMappings`を読み取る。選択中のマッピングが存在しない、または割り当てが空の場合は、次のrekordbox既定マッピングへフォールバックする。

- PERFORMANCE: `Performance 1 (Preset)` / ID `0000000000000`
- EXPORT: `Export (Preset)` / ID `0000000000030`

## 7. リリース

Windows版はMicrosoft Storeを使用せず、自己完結型`win-x64` ZIPをGitHub Releasesから直接配布する。ZIPには次を同梱する。

- OverCUEアプリ本体と.NET 10ランタイム
- XPPen ACK05プロファイルと導入手順
- rekordboxキーボードマッピングと導入手順
- 日本語・英語・簡体字中国語の翻訳JSON
- MIT License

正式なZIP名は`OverCUE-vX.Y.Z-windows-x64.zip`とし、Releaseに`SHA256SUMS.txt`を添付する。現在は未署名のためSmartScreen警告が表示される場合がある。自己署名証明書は一般配布に使用しない。将来の公開署名は、条件を満たす場合にSignPath Foundationを第一候補とする。

`develop`更新とPull RequestでWindows/macOSのビルドとチェックを実行し、`main`上の`vX.Y.Z`タグからReleaseを作成する。詳細は[`branch-and-release-policy.md`](branch-and-release-policy.md)を参照する。

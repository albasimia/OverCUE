# OverCUE Windows版 開発方針

更新日: 2026-07-13

## 1. 基本方針

Windows版はC# / .NET 10 / WPFでWindowsネイティブ実装する。macOS版Swiftコードとのバイナリ共有は行わず、次の仕様とデータを共有する。

- Action IDとrekordbox commandId
- 設定JSONの論理構造
- ACK05 HIDレポートのデコード仕様
- デフォルトキーマッピングと翻訳リソース
- OS非依存ロジックのテストベクトル

Windows版は設定画面、通知領域、入力監視、Action解決、rekordboxへの入力送信を単一プロセスにまとめる。診断用の`OverCUE.Probe`だけを別プロセスとする。

## 2. 対象環境

- Windows 10 22H2 / Windows 11
- x64
- .NET 10 LTS
- XPPen ACK05（USB / Bluetooth Low Energy）
- rekordbox 7
- 通常ユーザー権限

ARM64、仮想MIDI、複数ACK05の完全同時操作、自動更新は初回リリースの対象外とする。

## 3. Gate 0: 入力方式の実機検証

GUI本実装より先に、`OverCUE.Probe`をWindows実機で実行して次を確認する。

1. USB / BLEそれぞれのRaw Inputデバイスパス、VID/PID、Usage Page、Usage IDを記録する。
2. キーとダイヤルのRaw InputレポートがmacOS版の8バイトReport ID 6と一致することを確認する。
3. XPPenドライバー停止時と稼働時でレポートを比較する。
4. XPPen設定で通常キー出力を無効化してもRaw Inputを取得できるか確認する。
5. Notepadとrekordboxを前面にし、ACK05の元ショートカットが対象アプリへ漏れないか確認する。
6. USB再接続、BLE再接続、BLE再ペアリング後のデバイスパスを比較する。
7. Windows版rekordboxの設定ファイルと`KeyMappings`の保存場所、XML表現を採取する。

Raw Inputは入力を識別して受信するために使う。`RIDEV_NOLEGACY`を他プロセスへのグローバルな入力抑止手段として扱わない。

入力抑止方式は次の優先順で採用する。

1. XPPen公式設定で通常出力を無効化し、Raw Inputだけを読む。
2. ACK05を利用上無害なキーへ割り当て、Raw Inputを読む。
3. 署名済みデバイス固有フィルタードライバーを別プロジェクトとして検討する。

低レベルキーボードフックの時刻相関によるデバイス推測は製品実装に採用しない。

## 4. コンポーネント境界

`OverCUE.Core`はWin32型を公開しない。以下をCoreに置く。

- ACK05レポートDecoder
- Action Layerと長押し状態機械
- 設定モデル、移行、競合検査
- ダイヤル加速とJump加速
- rekordbox KeyMappings XMLの論理モデル

`OverCUE.Windows`に以下のアダプターを置く。

- Raw Inputとデバイス接続通知
- `SendInput`によるキーボード・マウス出力
- rekordbox最前面プロセス判定
- Per-Monitor DPI対応の波形座標処理
- `%LocalAppData%\OverCUE`への保存
- WPF設定画面と通知領域

## 5. MVP完了条件

- ACK05の元ショートカットがrekordboxへ漏れない。
- 共通HIDテストベクトルからmacOS版と同じキー状態を復元する。
- Cue保持、Jump加速、コード、キー＋ダイヤル、4グループが動作する。
- rekordboxが前面にない場合は入力を送らない。
- 未割り当てのrekordbox操作を推測送信しない。
- Windows 10 / 11、USB / BLE、複数DPI・複数モニターで検証する。
- 通常ユーザー権限で動作し、アンインストール後に常駐物を残さない。

## 6. リリース

開発ビルドは自己完結型x64で生成する。一般配布は署名済みMSIXとし、Microsoft Storeまたは信頼されたコード署名サービスを使用する。自己署名は実機開発だけに使用する。

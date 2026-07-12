---
layout: default
title: OverCUE | ACK05をCUE仕込みデバイスへ
lang: ja
description: XPPen ACK05を、rekordboxのCUE仕込み用デバイスへ。片手だけで快適なCUE打ちを実現するmacOS向けオープンソースツール。
locale: ja_JP
canonical_url: https://albasimia.github.io/OverCUE/
og_image: https://albasimia.github.io/OverCUE/assets/ogp/ja.png?v=e082a3b
og_image_alt: OverCUEでXPPen ACK05をrekordboxのCUE仕込みデバイスとして使用
---

<nav class="language-nav">日本語 ｜ <a href="./en/">English</a> ｜ <a href="./zh-hans/">简体中文</a></nav>

# OverCUE 使い方
{: #overcue }

XPPen ACK05のダイヤルと10個のキーを、macOS版rekordboxのCUE仕込み操作へ変換する常駐アプリです。rekordbox Freeプランで利用できるマウス・キーボード方式を採用しています。

![OverCUEの設定画面](./assets/images/overcue-ja.png)

## OverCUEを応援する

<div class="support-card">
  <p>OverCUEがCUE仕込みの助けになったら、今後の開発・保守・多言語対応を支援していただけると嬉しいです。</p>
  <div class="support-actions">
    <a class="support-link sponsors" href="https://github.com/sponsors/albasimia/" target="_blank" rel="noopener noreferrer">♥ GitHub Sponsors</a>
    <a class="support-link kofi" href="https://ko-fi.com/albasimia" target="_blank" rel="noopener noreferrer">☕ Ko-fi</a>
  </div>
</div>

## 動作環境

- macOS 13 Ventura以降
- Apple Silicon Mac／Intel Mac
- XPPen ACK05 Wireless Shortcut Remote
- rekordbox 7

## インストール

<div class="notice">
この配布版はApple Developer Programを使用しておらず、Developer ID署名・Apple公証を行っていません。初回起動時にmacOSの警告が表示されます。
</div>

1. ZIPを展開します。
2. `OverCUE.app`を「アプリケーション」フォルダへ移動します。
3. OverCUEを一度開き、macOSの警告を表示させます。
4. 「システム設定」→「プライバシーとセキュリティ」を開きます。
5. セキュリティ欄に表示されるOverCUEの「このまま開く」を押します。
6. 確認画面でも「開く」を選択します。

Gatekeeper全体を無効化したり、`xattr`で隔離属性を削除したりする必要はありません。配布物の確認には、Releaseに添付している`SHA256SUMS.txt`を利用できます。

```sh
shasum -a 256 OverCUE-v0.1.1-macos-universal.zip
```

## 初回設定

OverCUEはACK05入力の取得とrekordbox操作のため、次の権限を使用します。

- 入力監視：ACK05のキーとダイヤル入力を受け取る
- アクセシビリティ：rekordboxへキーボード・マウス操作を送る

初回起動時の案内に従って「システム設定」からOverCUEを許可してください。権限変更後はOverCUEを終了して起動し直します。

XPPenPenTabletがACK05入力を消費する場合は終了してください。ACK05を接続したままOverCUEを再起動すると改善することがあります。

## 基本的な使い方

1. rekordboxを起動します。
2. ACK05を接続してOverCUEを起動します。
3. OverCUEのグループとEXPORT／PERFORMANCEモードを選択します。
4. 波形操作を使う場合は、rekordboxの拡大波形上へポインターを置き、`K8+K1`で位置を保存します。
5. rekordboxを最前面にしてACK05を操作します。

キーボード・マウス出力はrekordboxが最前面のときだけ有効です。ウインドウを閉じてもメニューバーの👻アイコンから動作を継続できます。

## グループとモード

| グループ | 初期モード | 対象 |
| --- | --- | --- |
| 1 | PERFORMANCE | Deck 1 |
| 2 | PERFORMANCE | Deck 2 |
| 3 | EXPORT | Deck 1 |
| 4 | EXPORT | ユーザー設定用 |

各グループは最後に使用したEXPORT／PERFORMANCEモードを保存します。GUI、ACK05、CLI、メニューバーのグループとモードは連動します。

`K8+K1`で保存する波形位置もグループごとに独立しています。グループを切り替えると、そのグループで最後に保存した位置へ切り替わります。

## デフォルトキーマップ

| 入力 | 操作 |
| --- | --- |
| K1 | Hot Cue C |
| K2 | Memory Cue削除 |
| K3 | 後方へジャンプ（長押しリピート） |
| K4 | Hot Cue B |
| K5 | Memory Cue追加 |
| K6 | 前方へジャンプ（長押しリピート） |
| K7 | Quantize ON/OFF |
| K8 | Hot Cue A |
| K9 | Cue（押下中のみ再生） |
| K10 | Play/Pause |
| ダイヤル左／右 | Jog Search左／右 |
| K8+K1 | 波形位置を保存 |
| K7+K8／K4／K1 | Hot Cue A／B／Cを削除 |
| K7+K3／K6 | 次／前のMemory Cue |
| K7+K2 | グループを昇順で切り替え |
| K7+K5 | グループを降順で切り替え |
| K7+ダイヤル左／右 | Pitch Bend −／＋ |

## キーマッピングの編集

ショートカット一覧の編集ボタンを押し、ACK05のキー、任意数の同時押し、ダイヤル、またはキーを保持したダイヤル操作を入力します。

- 既存の入力と重複する場合は上書き確認を表示します。
- 長押し機能と同時押しが競合する場合は保存せず理由を表示します。
- デバイス図のキーやダイヤル左右をクリックすると、対応する一覧位置へ移動します。
- 一覧選択・デバイス選択は青、実機入力中は緑で表示します。
- rekordbox由来の機能名は、rekordboxのキーマッピングファイルに保存された言語で表示されます。

設定は次の場所へ保存されます。

```text
~/Library/Application Support/OverCUE/config.json
```

## トラブルシューティング

### ACK05を開けない

- XPPenPenTabletを終了する
- ACK05を切断して再接続する
- OverCUEの入力監視権限を確認する
- OverCUEを終了して再起動する

### rekordboxが反応しない

- rekordboxを最前面にする
- OverCUEのアクセシビリティ権限を確認する
- rekordbox側で対象機能にショートカットが割り当てられているか確認する
- EXPORT／PERFORMANCEモードとグループを確認する

### アップデート後に動かない

アドホック署名のため、アプリを差し替えると入力監視・アクセシビリティ権限の再付与が必要になる場合があります。システム設定から古いOverCUEを削除し、新しいOverCUEを追加してください。

## プライバシーと安全性

<div class="safe">
OverCUEはテレメトリ、広告、アカウント機能、自動アップロードを実装していません。設定はMac内へ保存されます。
</div>

配布ZIPはAppleによる公証・マルウェア検査を受けていません。GitHub Releaseのチェックサムと公開ソースを確認したうえで利用してください。

## ライセンスと商標

OverCUEは[MIT License](https://github.com/albasimia/OverCUE/blob/main/LICENSE)で公開しています。

OverCUEは独立した非公式プロジェクトです。XPPen、AlphaTheta、rekordboxとの提携・承認関係はありません。製品名・商標は各権利者に帰属します。

詳細な実装仕様は[GitHubリポジトリ](https://github.com/albasimia/OverCUE)を参照してください。

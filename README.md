# OverCUE

OverCUE turns the XPPen ACK05 dial and keys into cue-preparation controls for rekordbox on macOS.

XPPen ACK05のダイヤルとキーを、macOS版rekordboxのCUE仕込み操作へ変換するアプリです。

![OverCUE](docs/assets/images/overcue-ja.png)

## Requirements / 動作環境

- macOS 13 or later（Apple Silicon / Intel）
- XPPen ACK05
- rekordbox 7

## Download / ダウンロード

Download the latest Universal Binary from [GitHub Releases](https://github.com/albasimia/OverCUE/releases/latest).

最新のUniversal Binaryは[GitHub Releases](https://github.com/albasimia/OverCUE/releases/latest)からダウンロードできます。

This build is not signed with an Apple Developer ID or notarized. Follow the installation guide instead of disabling Gatekeeper.

この配布版はDeveloper ID署名・Apple公証を行っていません。Gatekeeperを無効化せず、ガイドの手順で個別に起動を許可してください。

## Guides / ガイド

- [日本語](https://albasimia.github.io/OverCUE/)
- [English](https://albasimia.github.io/OverCUE/en/)
- [简体中文](https://albasimia.github.io/OverCUE/zh-hans/)

## Build

```sh
./Scripts/build-app.sh
```

The generated `dist/OverCUE.app` is an `arm64 + x86_64` Universal Binary.

## License

[MIT License](LICENSE)

OverCUE is an independent project and is not affiliated with or endorsed by XPPen, AlphaTheta, or rekordbox.

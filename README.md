# OverCUE

OverCUE turns the XPPen ACK05 dial and keys into cue-preparation controls for rekordbox on macOS and Windows.

XPPen ACK05のダイヤルとキーを、macOS／Windows版rekordboxのCUE仕込み操作へ変換するアプリです。

![OverCUE](docs/assets/images/overcue-ja.png)

## Requirements / 動作環境

| Platform | Requirements |
| --- | --- |
| macOS | macOS 13 or later, Apple silicon or Intel Mac |
| Windows | Windows 10 22H2 or Windows 11, x64 |
| Both | XPPen ACK05 Wireless Shortcut Remote, rekordbox 7 |

## Download / ダウンロード

Download the latest macOS Universal Binary or self-contained Windows x64 package from [GitHub Releases](https://github.com/albasimia/OverCUE/releases/latest).

[GitHub Releases](https://github.com/albasimia/OverCUE/releases/latest)から、macOS Universal Binaryまたは自己完結型Windows x64版をダウンロードできます。

- macOS: `OverCUE-vX.Y.Z-macos-universal.zip`
- Windows: `OverCUE-vX.Y.Z-windows-x64.zip`
- Checksums: `SHA256SUMS.txt`

The macOS build is not Developer ID signed or notarized. The Windows build is distributed directly rather than through Microsoft Store and may show a SmartScreen warning while it is unsigned. Follow the installation guide instead of disabling OS security features.

macOS版はDeveloper ID署名・Apple公証を行っていません。Windows版はMicrosoft Storeを経由せず直接配布し、未署名の間はSmartScreen警告が表示される場合があります。OSのセキュリティ機能を無効化せず、ガイドの手順に従ってください。

The Windows ZIP also contains the tested XPPen ACK05 profile, rekordbox keyboard mapping, and setup instructions.

Windows版ZIPには、動作確認済みXPPen ACK05プロファイル、rekordboxキーボードマッピング、導入手順を同梱します。

## Guides / ガイド

- [日本語](https://albasimia.github.io/OverCUE/)
- [English](https://albasimia.github.io/OverCUE/en/)
- [简体中文](https://albasimia.github.io/OverCUE/zh-hans/)

The application interface and menus support Japanese, English, and Simplified Chinese on both platforms. rekordbox function names follow the language stored in the selected rekordbox key-mapping file.

アプリ画面とメニューは両OSとも日本語・英語・簡体字中国語に対応します。rekordbox由来の機能名は、選択中のキーマッピングファイルに保存された言語で表示されます。

## Support / 開発支援

If OverCUE helps your workflow, you can support its continued development.

OverCUEが役に立ったら、今後の開発を支援していただけると嬉しいです。

[![GitHub Sponsors](https://img.shields.io/badge/GitHub%20Sponsors-Sponsor-EA4AAA?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/albasimia/)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-FF5E5B?logo=kofi&logoColor=white)](https://ko-fi.com/albasimia)

## Build

macOS:

```sh
./Scripts/build-app.sh
```

Windows:

```powershell
dotnet build .\Windows\OverCUE.Windows.sln
```

The release process and branch policy are documented in [`docs/branch-and-release-policy.md`](docs/branch-and-release-policy.md).

## License

[MIT License](LICENSE)

OverCUE is an independent project and is not affiliated with or endorsed by XPPen, AlphaTheta, or rekordbox.

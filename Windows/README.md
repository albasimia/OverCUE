# OverCUE for Windows

Windows版の開発領域です。入力方式、実装済み機能、設定保存、配布方式は
[`docs/windows-development-policy.md`](../docs/windows-development-policy.md)を参照してください。

## Requirements

- Windows 10 22H2 or Windows 11
- Visual Studio 2022 with the .NET desktop development workload, or .NET 10 SDK
- XPPen ACK05

## Build

```powershell
dotnet build .\OverCUE.Windows.sln
dotnet run --project .\src\OverCUE.Probe\OverCUE.Probe.csproj
dotnet run --project .\tests\OverCUE.Core.Checks\OverCUE.Core.Checks.csproj
```

Build、Core checks、Windows UI checksは`.github/workflows/ci.yml`でWindows runner上でも実行します。

## Distribution

Windows版はMicrosoft Storeを経由せず、自己完結型の`win-x64`アプリをGitHub Releasesで直接配布します。
配布ZIPにはアプリ本体に加えて、次の初期設定ファイルを同梱します。

画面、タスクトレイ、状態メッセージはmacOS版と同じ日本語・英語・簡体字中国語に対応し、
ヘッダーの表示言語メニューから切り替えます。翻訳JSONはmacOS版とWindows版で共有します。

- `Setup/XPPen/PenTablet_Config_2026-07-13.pcfg`
- `Setup/XPPen/README.md`
- `Setup/rekordbox/OverCUE-Performance.mappings`
- `Setup/rekordbox/README.md`

XPPen設定のインポートは現在のドライバー設定を置き換えるため、利用者には先にバックアップを
エクスポートしてもらいます。CIとReleaseは`Scripts/package-windows-release.ps1`を共用し、
同じファイル構成を生成します。

`OverCUE.Probe`はACK05のRaw InputをJSON Linesで記録します。終了は`Ctrl+C`です。

```powershell
dotnet run --project .\src\OverCUE.Probe\OverCUE.Probe.csproj -- --jsonl
```

通常はVID `28BD` / PID `0202`だけを表示します。初期調査でデバイスパスにVID/PIDが現れない場合は`--all-hid`を指定します。

```powershell
dotnet run --project .\src\OverCUE.Probe\OverCUE.Probe.csproj -- --all-hid
```

Probeは入力を抑止しません。Notepadまたはrekordboxを前面にして、ACK05の元入力が漏れるかを別途確認してください。

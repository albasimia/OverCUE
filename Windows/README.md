# OverCUE for Windows

Windows版の開発領域です。設計判断とGate 0の手順は[`docs/windows-development-policy.md`](../docs/windows-development-policy.md)を参照してください。

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

同じBuildとCore checksは`.github/workflows/windows.yml`でWindows runner上でも実行します。

`OverCUE.Probe`はACK05のRaw InputをJSON Linesで記録します。終了は`Ctrl+C`です。

```powershell
dotnet run --project .\src\OverCUE.Probe\OverCUE.Probe.csproj -- --jsonl
```

通常はVID `28BD` / PID `0202`だけを表示します。初期調査でデバイスパスにVID/PIDが現れない場合は`--all-hid`を指定します。

```powershell
dotnet run --project .\src\OverCUE.Probe\OverCUE.Probe.csproj -- --all-hid
```

Probeは入力を抑止しません。Notepadまたはrekordboxを前面にして、ACK05の元入力が漏れるかを別途確認してください。

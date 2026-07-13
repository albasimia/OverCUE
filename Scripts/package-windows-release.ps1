[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDirectory,

    [Parameter(Mandatory = $true)]
    [string]$PackageDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$publishPath = (Resolve-Path -LiteralPath $PublishDirectory).Path
$packagePath = [System.IO.Path]::GetFullPath($PackageDirectory)

if (Test-Path -LiteralPath $packagePath) {
    throw "Package directory already exists: $packagePath"
}

$requiredFiles = @(
    (Join-Path $publishPath "OverCUE.Windows.exe"),
    (Join-Path $repositoryRoot "Windows\PenTablet_Config_2026-07-13.pcfg"),
    (Join-Path $repositoryRoot "Windows\XPPen-ACK05-OverCUE-README.md"),
    (Join-Path $repositoryRoot "Windows\OverCUE-Performance.mappings"),
    (Join-Path $repositoryRoot "Windows\REKORDBOX-MAPPING-README.md"),
    (Join-Path $repositoryRoot "Windows\DISTRIBUTION-README.md"),
    (Join-Path $repositoryRoot "LICENSE")
)

foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Required Windows package file is missing: $file"
    }
}

$xpPenDirectory = Join-Path $packagePath "Setup\XPPen"
$rekordboxDirectory = Join-Path $packagePath "Setup\rekordbox"
New-Item -ItemType Directory -Path $xpPenDirectory, $rekordboxDirectory | Out-Null

Copy-Item -Path (Join-Path $publishPath "*") -Destination $packagePath -Recurse
Copy-Item -LiteralPath (Join-Path $repositoryRoot "Windows\DISTRIBUTION-README.md") -Destination (Join-Path $packagePath "README.md")
Copy-Item -LiteralPath (Join-Path $repositoryRoot "LICENSE") -Destination (Join-Path $packagePath "LICENSE.txt")
Copy-Item -LiteralPath (Join-Path $repositoryRoot "Windows\PenTablet_Config_2026-07-13.pcfg") -Destination $xpPenDirectory
Copy-Item -LiteralPath (Join-Path $repositoryRoot "Windows\XPPen-ACK05-OverCUE-README.md") -Destination (Join-Path $xpPenDirectory "README.md")
Copy-Item -LiteralPath (Join-Path $repositoryRoot "Windows\OverCUE-Performance.mappings") -Destination $rekordboxDirectory
Copy-Item -LiteralPath (Join-Path $repositoryRoot "Windows\REKORDBOX-MAPPING-README.md") -Destination (Join-Path $rekordboxDirectory "README.md")

Write-Host "Prepared Windows release package: $packagePath"

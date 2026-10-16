# Builds this plugin for a release: compiles it for Win64 against the given
# Unreal Engine with RunUAT BuildPlugin, then zips the packaged plugin as
# <Plugin>-<VersionName>-UE<engine>-Win64.zip, holding a <Plugin>/ folder to
# extract into a project's Plugins/. Config/FilterPlugin.ini adds the LICENSE,
# README and docs/ to it. Takes ~2 minutes.
#
#   powershell -ExecutionPolicy Bypass -File Scripts\Package.ps1
#   powershell -ExecutionPolicy Bypass -File Scripts\Package.ps1 -EngineDir "D:\UE_5.7" -OutDir "D:\releases"
param(
    [string]$EngineDir = "C:\Program Files\Epic Games\UE_5.7",
    [string]$OutDir = (Join-Path $env:TEMP "UnrealPluginRelease")
)
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$descriptor = Get-ChildItem $root -Filter *.uplugin | Select-Object -First 1
$plugin = $descriptor.BaseName
$version = (Get-Content $descriptor.FullName -Raw | ConvertFrom-Json).VersionName
$engine = ((Get-Content (Join-Path $EngineDir "Engine\Build\Build.version") -Raw | ConvertFrom-Json) |
    ForEach-Object { "$($_.MajorVersion).$($_.MinorVersion)" })
$runUat = Join-Path $EngineDir "Engine\Build\BatchFiles\RunUAT.bat"
if (-not (Test-Path $runUat)) { throw "RunUAT.bat not found under $EngineDir (set -EngineDir)" }

$staging = Join-Path $OutDir "$plugin-staging"
$package = Join-Path $staging $plugin
if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
New-Item -ItemType Directory -Force $staging | Out-Null

& $runUat BuildPlugin "-Plugin=$($descriptor.FullName)" "-Package=$package" -TargetPlatforms=Win64
if ($LASTEXITCODE -ne 0) { throw "BuildPlugin failed (exit $LASTEXITCODE): see the log above" }

# BuildPlugin leaves the throwaway project it compiled in; it is not part of the plugin.
Remove-Item -Recurse -Force (Join-Path $package "HostProject") -ErrorAction SilentlyContinue

$zip = Join-Path $OutDir "$plugin-$version-UE$engine-Win64.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
# Entry names written with '/', the zip standard: Compress-Archive and .NET Framework's
# ZipFile write '\' under Windows PowerShell, which other unzip tools mishandle.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$base = (Get-Item $package).FullName     # long form, as the file listing gives (TEMP may be an 8.3 short path)
$archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem $base -Recurse -File | ForEach-Object {
        $name = "$plugin/" + $_.FullName.Substring($base.Length + 1).Replace('\', '/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $_.FullName, $name, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $archive.Dispose() }
Remove-Item -Recurse -Force $staging
Write-Host "Release package: $zip ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)"

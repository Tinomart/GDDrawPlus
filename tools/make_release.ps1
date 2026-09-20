<#
.SYNOPSIS
  Builds releases\GDDrawPlus-v<version>.zip: addons/GDDrawPlus plus the license files, with forward-slash entry names.

.EXAMPLE
  .\tools\make_release.ps1
#>
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$config = [System.IO.File]::ReadAllText((Join-Path $root "addons\GDDrawPlus\plugin.cfg"))
$version = [regex]::Match($config, 'version="([^"]+)"').Groups[1].Value
if (-not $version) { throw "No version in addons\GDDrawPlus\plugin.cfg" }
$releases = Join-Path $root "releases"
[System.IO.Directory]::CreateDirectory($releases) | Out-Null
$zipPath = Join-Path $releases "GDDrawPlus-v$version.zip"
if (Test-Path $zipPath) { [System.IO.File]::Delete($zipPath) }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $files = @(Get-ChildItem (Join-Path $root "addons\GDDrawPlus") -Recurse -File | Where-Object { $_.Extension -ne ".import" })
    $files += Get-Item (Join-Path $root "LICENSE"), (Join-Path $root "THIRD_PARTY_NOTICES.md")
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($root.Length + 1).Replace("\", "/")
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $relative, [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally { $zip.Dispose() }
"{0} ({1:N1} MB, {2} files)" -f $zipPath, ((Get-Item $zipPath).Length / 1MB), $files.Count
<#
.SYNOPSIS
  Renders material channels with the real renderer and checks that creating a new channel texture
  does not change how the surface looks (emission, roughness, metallic, ambient occlusion, height).

.DESCRIPTION
  Needs a GPU and opens a small Godot window for a moment, so it is separate from run_tests.ps1
  (which runs headless and cannot see rendering). It exists because a headless test once passed while
  a new emission texture lit the whole mesh white: Godot ADDS the emission colour to the emission
  texture unless the Multiply operator is set.

.EXAMPLE
  .\run_render_test.ps1
#>
param(
    [string]$Godot = $env:GODOT_CONSOLE,
    [string]$Addon = (Join-Path $PSScriptRoot "..\addons\GDDraw")
)
# Godot console executable: -Godot, else the GODOT_CONSOLE environment variable, else a godot*console* on PATH.
if (-not $Godot) { $found = Get-Command "godot*console*" -ErrorAction SilentlyContinue | Select-Object -First 1; if ($found) { $Godot = $found.Source } }
if (-not $Godot -or -not (Test-Path $Godot)) { throw "Godot console executable not found. Pass -Godot <path to Godot_v4.x_win64_console.exe>, set GODOT_CONSOLE, or put it on PATH." }
$ErrorActionPreference = "Continue"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$Addon = (Resolve-Path $Addon).Path
$work = Join-Path $env:TEMP "gddraw_render_test"
if (Test-Path $work) { [System.IO.Directory]::Delete($work, $true) }
[System.IO.Directory]::CreateDirectory($work) | Out-Null
Copy-Item "$PSScriptRoot\render\main.gd" $work
Copy-Item "$PSScriptRoot\render\main.tscn" $work
Copy-Item "$Addon\material\gddraw_material_channels.gd" $work
Copy-Item "$Addon\material\gddraw_shader_baker.gd" $work
[System.IO.File]::WriteAllText("$work\project.godot", "config_version=5`n[application]`nconfig/name=`"gddraw_render_test`"`nrun/main_scene=`"res://main.tscn`"`n[display]`nwindow/size/viewport_width=160`nwindow/size/viewport_height=160`n", $utf8)
& $Godot --path $work --editor --quit-after 200 --headless *> $null
$out = & $Godot --path $work --resolution 160x160 --rendering-method forward_plus 2>&1 | ForEach-Object { ([string]$_) -replace '\x1b\[[0-9;]*m', '' }
$out | Where-Object { $_ -match "RENDER|SCRIPT ERROR|Parse Error" }
if ($out | Where-Object { $_ -match "RENDER  RESULT: ALL PASSED" }) { exit 0 }
Write-Host "Render test FAILED (or no GPU/window was available)." -ForegroundColor Red
exit 1
<#
.SYNOPSIS
  Runs all test suites (UV tools, hotkeys, paint channels, Material Brush, ORM materials, 3D workflow) against the GDDraw addon in throwaway Godot projects.

.DESCRIPTION
  Never touches your real project: it copies the addon into %TEMP%\gddraw_uv_tests and runs Godot
  headless there. Needs the *console* build of Godot 4.7+ (Godot_v4.x-stable_win64_console.exe).

    unit tests    - the unwrap engine, saving/loading meshes, every unwrap method, UV editor window
    editor tests  - a real (headless) editor with GDDraw enabled: the UV menu, dialogs, undo/redo,
                    live paint-session refresh, the editor window, dock LAYOUT sizes, and the
                    keyboard-shortcut scoping (Ctrl+S etc.)

.EXAMPLE
  .\run_tests.ps1
  .\run_tests.ps1 -Godot "C:\path\to\Godot_v4.7-stable_win64_console.exe" -Addon "C:\some\addons\GDDraw"
#>
param(
    [string]$Godot = $env:GODOT_CONSOLE,
    [string]$Addon = (Join-Path $PSScriptRoot "..\addons\GDDraw")
)

# Godot prints harmless warnings to stderr at exit; they must not abort the script.
# Godot console executable: -Godot, else the GODOT_CONSOLE environment variable, else a godot*console* on PATH.
if (-not $Godot) { $found = Get-Command "godot*console*" -ErrorAction SilentlyContinue | Select-Object -First 1; if ($found) { $Godot = $found.Source } }
if (-not $Godot -or -not (Test-Path $Godot)) { throw "Godot console executable not found. Pass -Godot <path to Godot_v4.x_win64_console.exe>, set GODOT_CONSOLE, or put it on PATH." }
$ErrorActionPreference = "Continue"
$utf8 = New-Object System.Text.UTF8Encoding($false)
if (-not (Test-Path $Godot)) { throw "Godot executable not found: $Godot (pass -Godot with the path of the *_console.exe)" }
$Addon = (Resolve-Path $Addon).Path
$work = Join-Path $env:TEMP "gddraw_uv_tests"
if (Test-Path $work) { [System.IO.Directory]::Delete($work, $true) }
[System.IO.Directory]::CreateDirectory($work) | Out-Null

function New-TestProject([string]$dir, [string[]]$plugins) {
    [System.IO.Directory]::CreateDirectory("$dir\addons") | Out-Null
    Copy-Item $Addon "$dir\addons\GDDraw" -Recurse
    # keep the copy's update checker off the network
    $checker = "$dir\addons\GDDraw\gddraw_update_checker.gd"
    if (Test-Path $checker) {
        $text = [System.IO.File]::ReadAllText($checker).Replace("https://api.github.com/repos/ArdonyxApps/GDDraw/releases/latest", "http://127.0.0.1:9/none")
        [System.IO.File]::WriteAllText($checker, $text, $utf8)
    }
    $list = ($plugins | ForEach-Object { '"res://addons/' + $_ + '/plugin.cfg"' }) -join ", "
    $cfg = "config_version=5`n`n[application]`nconfig/name=`"gddraw_uv_tests`"`nconfig/features=PackedStringArray(`"4.7`")`n"
    if ($plugins.Count -gt 0) { $cfg += "`n[editor_plugins]`nenabled=PackedStringArray($list)`n" }
    [System.IO.File]::WriteAllText("$dir\project.godot", $cfg, $utf8)
}

function Strip-Ansi([string]$s) { return ($s -replace '\x1b\[[0-9;]*m', '') }

$results = @()

# ------------------------------------------------------------ unit tests
$unit = "$work\unit"
New-TestProject $unit @()
[System.IO.Directory]::CreateDirectory("$unit\tests") | Out-Null
Copy-Item "$PSScriptRoot\unit\*.gd" "$unit\tests\"
Write-Host "Registering classes ..."
& $Godot --headless --path $unit --editor --quit-after 300 *> $null
foreach ($test in (Get-ChildItem "$unit\tests\test_*.gd" | Sort-Object Name)) {
    Write-Host ("Running unit test {0} ..." -f $test.Name)
    $out = & $Godot --headless --path $unit --script ("res://tests/" + $test.Name) 2>&1 | ForEach-Object { Strip-Ansi ([string]$_) }
    $passed = [bool]($out | Where-Object { $_ -match '^RESULT: ALL PASSED' })
    $errors = @($out | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error|Compile Error' }).Count
    $failed = @($out | Where-Object { $_ -match '^\s+FAIL' })
    $results += [pscustomobject]@{ Suite = "unit: " + $test.Name; Passed = ($passed -and $errors -eq 0); Detail = ($failed -join "; ") + $(if ($errors) { " [$errors script error(s)]" } else { "" }) }
}

# ------------------------------------------------------------ editor tests
function Run-EditorSuite([string]$name, [string]$driver, [string]$resultPrefix, [int]$quitAfter, [int]$waitSeconds) {
    $dir = "$work\editor_$driver"
    New-TestProject $dir @("GDDraw", $driver)
    Copy-Item "$PSScriptRoot\editor\$driver" "$dir\addons\$driver" -Recurse
    Write-Host "Importing $name project ..."
    & $Godot --headless --path $dir --editor --quit-after 300 *> $null
    Write-Host "Running editor suite $name (about a minute) ..."
    $log = "$dir\run.log"
    $proc = Start-Process -FilePath $Godot -ArgumentList @("--headless", "--path", "`"$dir`"", "--editor", "--quit-after", "$quitAfter") -RedirectStandardOutput $log -RedirectStandardError "$dir\run.err" -PassThru -NoNewWindow
    $deadline = (Get-Date).AddSeconds($waitSeconds)
    while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    $out = @(Get-Content $log -ErrorAction SilentlyContinue | ForEach-Object { Strip-Ansi $_ })
    $err = @(Get-Content "$dir\run.err" -ErrorAction SilentlyContinue | ForEach-Object { Strip-Ansi $_ })
    $passed = [bool]($out | Where-Object { $_ -match ($resultPrefix + '\s+RESULT: ALL PASSED') })
    $failed = @($out | Where-Object { $_ -match ($resultPrefix + '\s+FAIL') } | ForEach-Object { $_.Trim() })
    $errors = @(($out + $err) | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error|Compile Error' }).Count
    $script:results += [pscustomobject]@{ Suite = "editor: " + $name; Passed = ($passed -and $errors -eq 0); Detail = ($failed -join "; ") + $(if ($errors) { " [$errors script error(s)]" } else { "" }) }
}
Run-EditorSuite "UV menu, unwrap, editor, layout" "uvtest_driver" "ITEST" 12000 400
Run-EditorSuite "keyboard shortcut scoping (Ctrl+S ...)" "hotkey_driver" "HKTEST" 6000 240
Run-EditorSuite "paint channels (Emission/Roughness/Metallic/AO/Height)" "channels_driver" "CHTEST" 8000 300
Run-EditorSuite "toolbar layout (2D/3D selector stays visible, tools scroll)" "toolbar_driver" "TBTEST" 3000 200
Run-EditorSuite "Material Brush (tool, material sets, companion channels)" "material_brush_driver" "MBTEST" 12000 420
Run-EditorSuite "Scale Image for 3D textures (Image menu, undo, saving)" "scale_driver" "SCTEST" 12000 420
Run-EditorSuite "Scene stays small (placeholder textures swapped for imported PNGs)" "placeholder_driver" "PHTEST" 14000 500
Run-EditorSuite "Loading another model: Also paint check, create-missing dialog, material-follow ticks" "newmesh_driver" "NMTEST" 18000 560
Run-EditorSuite "Meshes without a material (built-in shapes too): material + texture are created" "nomaterial_driver" "NOMTEST" 18000 520
Run-EditorSuite "ORM materials: packed occlusion/roughness/metallic, height settings copied, all channels follow the material" "beehive_driver" "BHTEST" 20000 560
Run-EditorSuite "GDDraw Plus release facts (name, version, updater off, notices)" "fork_driver" "FKTEST" 3000 200

# ------------------------------------------------------------ summary
Write-Host ""
Write-Host "==================== RESULTS ====================" -ForegroundColor Cyan
foreach ($r in $results) {
    if ($r.Passed) { Write-Host ("  PASS  " + $r.Suite) -ForegroundColor Green }
    else { Write-Host ("  FAIL  " + $r.Suite + "   " + $r.Detail) -ForegroundColor Red }
}
$failedCount = @($results | Where-Object { -not $_.Passed }).Count
Write-Host ""
if ($failedCount -eq 0) { Write-Host "All $($results.Count) suites passed." -ForegroundColor Green; exit 0 }
Write-Host "$failedCount of $($results.Count) suites FAILED. Please open an issue and name the failing suite." -ForegroundColor Red
exit 1

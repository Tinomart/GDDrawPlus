# Test suite

Automated tests for GDDrawPlus. They copy the addon into throwaway projects under your temp folder and run Godot headless there, so they never touch your own projects. Windows and PowerShell 5.1 or newer are needed, and the **console** build of Godot 4.7 or later (`Godot_v4.x-stable_win64_console.exe`).

    # from the repository root
    $env:GODOT_CONSOLE = "C:\path\to\Godot_v4.7-stable_win64_console.exe"
    .\test-suite\run_tests.ps1

`run_tests.ps1` runs the unit tests (`unit/`) and the editor tests (`editor/`, each a small editor plugin that drives GDDraw). It takes about ten minutes. Use `-Godot` and `-Addon` to point at a specific Godot executable or addon folder.

`run_render_test.ps1` needs a GPU and opens a small window for a moment. It renders channel textures with the real renderer, because a headless test once passed while a new emission texture made a whole mesh glow white.

The editor tests print `PASS` and `FAIL` lines and a final `RESULT`. The scripts exit with a non-zero code if anything failed.
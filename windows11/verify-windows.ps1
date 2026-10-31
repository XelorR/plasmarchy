#Requires -Version 5.1
<#
.SYNOPSIS
    Verify the Plasmarchy Windows 11 installation.

.DESCRIPTION
    Checks the komorebi.json schema/config, processes, autostart entries,
    animation registry values, and the Kanata task. It then prints the manual
    checks that cannot be automated safely.

    Exit code 0 means all automated checks passed. Exit code 1 means at least
    one automated check failed. Manual checks still need to be performed.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\verify-windows.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$ConfigHome = $env:KOMOREBI_CONFIG_HOME
if ([string]::IsNullOrWhiteSpace($ConfigHome)) {
    $ConfigHome = [Environment]::GetEnvironmentVariable('KOMOREBI_CONFIG_HOME', 'User')
}
if ([string]::IsNullOrWhiteSpace($ConfigHome)) {
    $ConfigHome = $env:USERPROFILE
}
$ConfigPath = Join-Path $ConfigHome 'komorebi.json'
$AhkPath = Join-Path $ConfigHome 'komorebi.ahk'
$KanataCfg = Join-Path $ConfigHome 'kanata.kbd'
$StartupDir = [Environment]::GetFolderPath('Startup')
$script:Failed = 0
$script:Warned = 0

function Check-Pass([string]$Message) {
    Write-Host "[ OK ]   $Message" -ForegroundColor Green
}

function Check-Fail([string]$Message) {
    Write-Host "[FAIL]   $Message" -ForegroundColor Red
    $script:Failed++
}

function Check-Warn([string]$Message) {
    Write-Host "[WARN]   $Message" -ForegroundColor Yellow
    $script:Warned++
}

function Test-Admin {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-Executable {
    param([string[]]$Names)
    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
        $fallbacks = @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\' + $name),
            (Join-Path $env:LOCALAPPDATA 'Programs\komorebi\' + $name),
            (Join-Path $env:ProgramFiles ('komorebi\' + $name)),
            (Join-Path $env:LOCALAPPDATA 'Plasmarchy\kanata\' + $name),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\' + $name)
        )
        foreach ($fallback in $fallbacks) {
            if (Test-Path $fallback) { return $fallback }
        }
        $wingetRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
        if (Test-Path $wingetRoot) {
            $hit = Get-ChildItem -Path $wingetRoot -Filter $name -Recurse -File -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return $null
}

function Test-RegValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Expected,
        [string]$Label,
        [switch]$WarnOnly
    )
    $property = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $property) {
        if ($WarnOnly) { Check-Warn "$Label is missing ($Path\$Name)" }
        else { Check-Fail "$Label is missing ($Path\$Name)" }
        return
    }
    $actual = $property.PSObject.Properties[$Name].Value
    if ("$actual" -eq "$Expected") {
        Check-Pass "$Label = $actual"
    } elseif ($WarnOnly) {
        Check-Warn "$Label = $actual (expected $Expected; install used -KeepAnimations?)"
    } else {
        Check-Fail "$Label = $actual (expected $Expected)"
    }
}

function Test-StartupShortcut {
    param([string]$Name)
    $path = Join-Path $StartupDir ($Name + '.lnk')
    if (-not (Test-Path $path)) {
        Check-Fail "Startup shortcut missing: $path"
        return
    }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($path)
    if (Test-Path $shortcut.TargetPath) {
        Check-Pass "$Name -> $($shortcut.TargetPath)"
    } else {
        Check-Fail "$Name target does not exist: $($shortcut.TargetPath)"
    }
}

Write-Host "Plasmarchy Windows 11 verification" -ForegroundColor Cyan
Write-Host "Config home: $ConfigHome"
Write-Host ""

# ---------------------------------------------------------------------------
# OS and config

$os = Get-CimInstance -ClassName Win32_OperatingSystem
if ([int]$os.BuildNumber -ge 22000) {
    Check-Pass "Windows 11 build $($os.BuildNumber)"
} else {
    Check-Fail "Windows build $($os.BuildNumber) is older than Windows 11"
}

if (Test-Path $ConfigPath) {
    try {
        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        Check-Pass "komorebi.json parses as JSON"
        if ($config.border -eq $true -and [int]$config.border_width -eq 2) {
            Check-Pass "2 px Komorebi border configured"
        } else {
            Check-Fail "Expected border=true and border_width=2"
        }
        if ($config.animation.enabled -eq $false) {
            Check-Pass "Komorebi animations disabled"
        } else {
            Check-Fail "Komorebi animation.enabled is not false"
        }
        if ([int]$config.default_workspace_padding -eq 10) {
            Check-Pass "Workspace padding = 10"
        } else {
            Check-Fail "default_workspace_padding is not 10"
        }
        if ([int]$config.default_container_padding -eq 2) {
            Check-Pass "Container padding = 2 (4 px visible gap with the Komorebi border)"
        } else {
            Check-Fail "default_container_padding is not 2"
        }
        if ($config.border_style -eq 'Square') {
            Check-Pass "Square border style"
        } else {
            Check-Fail "border_style is not Square"
        }
    } catch {
        Check-Fail "komorebi.json does not parse: $($_.Exception.Message)"
    }
} else {
    Check-Fail "komorebi.json not found: $ConfigPath"
}

$komorebic = Find-Executable -Names @('komorebic.exe', 'komorebic-no-console.exe')
if ($komorebic) {
    Check-Pass "komorebic found: $komorebic"
    if (Test-Path $ConfigPath) {
        & $komorebic check -k $ConfigPath | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Check-Pass "komorebic check passed"
        } else {
            Check-Fail "komorebic check failed (exit $LASTEXITCODE)"
        }
    }
} else {
    Check-Fail "komorebic.exe not found"
}

# ---------------------------------------------------------------------------
# Processes

foreach ($name in @('komorebi', 'masir', 'AutoHotkey64', 'PowerToys', 'PowerToys.PowerLauncher')) {
    if (Get-Process -Name $name -ErrorAction SilentlyContinue) {
        Check-Pass "Process running: $name"
    } elseif ($name -in @('PowerToys', 'PowerToys.PowerLauncher')) {
        Check-Warn "Process not running: $name (PowerToys Run depends on it)"
    } else {
        Check-Fail "Process not running: $name"
    }
}

$kanataProcess = Get-Process -Name kanata_windows_gui_winIOv2_x64, kanata_windows_gui_wintercept_x64, kanata_gui, kanata -ErrorAction SilentlyContinue
if ($kanataProcess) {
    Check-Pass "Kanata process running"
} else {
    Check-Warn "Kanata process not running (Right Ctrl layout switch and Win+L interception will not work)"
}

$kanataTask = Get-ScheduledTask -TaskName 'Plasmarchy-Kanata' -ErrorAction SilentlyContinue
if ($kanataTask) {
    Check-Pass "Scheduled task Plasmarchy-Kanata exists"
    if ($kanataTask.State -eq 'Running') {
        Check-Pass "Scheduled task Plasmarchy-Kanata is running"
    } else {
        Check-Warn "Scheduled task Plasmarchy-Kanata is $($kanataTask.State), not Running"
    }
} else {
    Check-Warn "Scheduled task Plasmarchy-Kanata does not exist"
}

# ---------------------------------------------------------------------------
# Autostart

Test-StartupShortcut -Name 'Plasmarchy Komorebi'
Test-StartupShortcut -Name 'Plasmarchy Hotkeys'

# ---------------------------------------------------------------------------
# Windows appearance

Test-RegValue -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Expected '0' -Label 'MinAnimate' -WarnOnly
Test-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Expected '0' -Label 'MenuShowDelay' -WarnOnly
Test-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAnimations' -Expected 0 -Label 'TaskbarAnimations' -WarnOnly
Test-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'SnapAssist' -Expected 0 -Label 'SnapAssist' -WarnOnly
Test-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'EnableSnapAssistFlyout' -Expected 0 -Label 'EnableSnapAssistFlyout' -WarnOnly
Test-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency' -Expected 0 -Label 'EnableTransparency' -WarnOnly

if ($env:KOMOREBI_CONFIG_HOME) {
    $persisted = [Environment]::GetEnvironmentVariable('KOMOREBI_CONFIG_HOME', 'User')
    if ($persisted -eq $ConfigHome) {
        Check-Pass "KOMOREBI_CONFIG_HOME is persisted for the user"
    } else {
        Check-Warn "KOMOREBI_CONFIG_HOME is set for this process but not persisted; autostart may not see it"
    }
} elseif ($ConfigHome -ne $env:USERPROFILE) {
    Check-Pass "Using persisted user KOMOREBI_CONFIG_HOME: $ConfigHome"
}

# ---------------------------------------------------------------------------
# Live Komorebi state

if ($komorebic) {
    try {
        $layout = & $komorebic query focused-workspace-layout 2>$null
        if ($LASTEXITCODE -eq 0 -and $layout -match 'bsp') {
            Check-Pass "Focused workspace layout: BSP"
        } else {
            Check-Warn "Could not confirm BSP layout (komorebi may not be running)"
        }
    } catch {
        Check-Warn "Could not query komorebi state"
    }
}

if (Test-Path $AhkPath) {
    Check-Pass "AutoHotkey script installed: $AhkPath"
} else {
    Check-Fail "AutoHotkey script missing: $AhkPath"
}

if (Test-Path $KanataCfg) {
    Check-Pass "Kanata config installed: $KanataCfg"
    $kanataBinary = Find-Executable -Names @(
        'kanata_windows_gui_winIOv2_x64.exe',
        'kanata_windows_gui_wintercept_x64.exe',
        'kanata_gui.exe',
        'kanata.exe'
    )
    if ($kanataBinary) {
        & $kanataBinary --check --cfg $KanataCfg | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Check-Pass "kanata --check passed"
        } else {
            Check-Fail "kanata --check failed (exit $LASTEXITCODE)"
        }
    } else {
        Check-Warn "Kanata binary not found; kanata.kbd was not validated"
    }
} else {
    Check-Warn "Kanata config missing: $KanataCfg"
}

if (-not (Test-Admin)) {
    Check-Warn "Not elevated: some checks may be incomplete (Kanata task, elevated windows)"
}

# ---------------------------------------------------------------------------
# Manual checklist

Write-Host ""
Write-Host "Manual checks (the parts that need a real keyboard):" -ForegroundColor Cyan
Write-Host @"
  1.  Win+Space opens PowerToys Run, not the Start menu.
  2.  Win+Return opens Windows Terminal; Win+Alt+Return opens WSL tmux "Work".
  3.  Open 3-4 windows. Win+Arrow focuses; Win+Shift+Arrow moves/swaps.
  4.  Win+1..9 focuses a workspace; Win+Shift+1..9 moves the window and
      follows it; Win+Shift+Alt+1..9 moves it without changing the view.
  5.  Win+L cycles the layout (F23 from Kanata); Win+Alt+L cycles back.
  6.  Win+T toggles floating; Win+J flips the layout.
  7.  Win+C / Win+X / Win+V work in Notepad and in Windows Terminal.
      Windows Terminal uses Ctrl+Shift+C/X/V; legacy conhost uses Ctrl+C/V.
  8.  Hover another window: focus changes immediately. Move focus with
      Win+Arrow: the pointer lands in the new window.
  9.  Right Ctrl tap switches the keyboard layout; holding Right Ctrl still
      works as Ctrl. Alt+Shift and Ctrl+Shift must be "Not Assigned" in
      Windows input-language hotkeys.
  10. Win+F enables monocle; Win+Alt+F / Win+Ctrl+F maximize the window.
  11. Active border: 2 px square, teal approximation of cyan -> green;
      inactive border #595959; workspace gap 10, inter-window gap about 4.
  12. No titlebars on browsers, Steam, Telegram, Lutris, LocalSend, Scan.
  13. Win+L does NOT lock the screen (Kanata must be running); Win+Ctrl+L does.
  14. Print / Alt+Print / Win+Print / Win+Ctrl+Print open Snipping Tool,
      Game Bar recording, Color Picker, and Text Extractor.
  15. Disconnect the external monitor: only the laptop panel remains and
      Komorebi retiles it. Reconnect and verify the second monitor is back.

If a manual check fails, see SPEC.md > Troubleshooting and the journal/log
locations listed there.
"@ -ForegroundColor Gray

Write-Host ""
Write-Host "Automated result: $script:Failed failed, $script:Warned warnings." -ForegroundColor Cyan
if ($script:Failed -gt 0) { exit 1 }
exit 0

#Requires -Version 5.1
<#
.SYNOPSIS
    Stop and remove the Plasmarchy Windows 11 layer.

.DESCRIPTION
    By default this script:
      * stops Komorebi, masir, the Plasmarchy AHK script, and Kanata;
      * removes the Plasmarchy startup shortcuts and Kanata scheduled task;
      * restores the animation/transparency/snap registry values saved by
        install-windows.ps1.

    Configuration files are left in place unless -RemoveConfig is used.
    Use -RestoreBackup to put the pre-install komorebi.json / komorebi.ahk /
    kanata.kbd back.

.PARAMETER RemoveConfig
    Delete %USERPROFILE%\komorebi.json, komorebi.ahk, and kanata.kbd (or the
    equivalents under KOMOREBI_CONFIG_HOME).

.PARAMETER RestoreBackup
    Restore the first-run configuration snapshot from
    %LOCALAPPDATA%\Plasmarchy\original (not the newest timestamped backup,
    which may already contain Plasmarchy's own files).

.PARAMETER RemovePackages
    Uninstall Komorebi, masir, AutoHotkey, PowerToys, and Kanata through winget.
    This is intentionally opt-in because PowerToys/AHK may be used elsewhere.

.PARAMETER KeepSettings
    Do not restore the animation/transparency/snap registry values.

.PARAMETER RemoveState
    Delete %LOCALAPPDATA%\Plasmarchy after the uninstall.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\uninstall-windows.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\uninstall-windows.ps1 -RestoreBackup -RemovePackages
#>
[CmdletBinding()]
param(
    [switch]$RemoveConfig,
    [switch]$RestoreBackup,
    [switch]$RemovePackages,
    [switch]$KeepSettings,
    [switch]$RemoveState
)

$ErrorActionPreference = 'Stop'
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
$StateDir = Join-Path $env:LOCALAPPDATA 'Plasmarchy'
$StartupDir = [Environment]::GetFolderPath('Startup')

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-Komorebic {
    $command = Get-Command komorebic.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\komorebic.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\komorebi\komorebic.exe'),
        (Join-Path $env:ProgramFiles 'komorebi\komorebic.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    $wingetRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path $wingetRoot) {
        $hit = Get-ChildItem -Path $wingetRoot -Filter komorebic.exe -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Get-OriginalBackup {
    $pointer = Join-Path $StateDir 'original-backup.txt'
    if (Test-Path $pointer) {
        $path = (Get-Content -Path $pointer -Raw).Trim()
        if (Test-Path $path) { return $path }
    }
    return $null
}

function Get-LastBackup {
    $pointer = Join-Path $StateDir 'last-backup.txt'
    if (Test-Path $pointer) {
        $path = (Get-Content -Path $pointer -Raw).Trim()
        if (Test-Path $path) { return $path }
    }
    $latest = Get-ChildItem -Path $env:USERPROFILE -Directory -Filter 'plasmarchy-backup-*' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($latest) { return $latest.FullName }
    return $null
}

function Set-RegValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [ValidateSet('DWord', 'String')]
        [string]$Kind = 'DWord'
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    if ($Kind -eq 'DWord') {
        New-ItemProperty -Path $Path -Name $Name -Value ([int]$Value) -PropertyType DWord -Force | Out-Null
    } else {
        New-ItemProperty -Path $Path -Name $Name -Value ([string]$Value) -PropertyType String -Force | Out-Null
    }
}

function Restore-AnimationSettings {
    $backup = Get-OriginalBackup
    if (-not $backup) {
        $backup = Get-LastBackup
    }
    if (-not $backup) {
        Write-Warning 'No Plasmarchy backup was found; animation settings were not restored.'
        return
    }
    $settingsPath = Join-Path $backup 'settings.json'
    if (-not (Test-Path $settingsPath)) {
        Write-Warning "No settings.json in $backup; animation settings were not restored."
        return
    }
    $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
    foreach ($setting in $settings) {
        if ($setting.Exists) {
            Set-RegValue -Path $setting.Path -Name $setting.Name -Value $setting.Value -Kind $setting.Kind
        } else {
            Remove-ItemProperty -Path $setting.Path -Name $setting.Name -ErrorAction SilentlyContinue
        }
    }
    Write-Host "Restored Windows settings from $settingsPath"
}

function Restore-ConfigFiles {
    $original = Get-OriginalBackup
    $last = Get-LastBackup
    if ((-not $original) -and (-not $last)) {
        Write-Warning 'No Plasmarchy backup was found; configuration files were not restored.'
        return
    }

    foreach ($file in @('komorebi.json', 'komorebi.ahk', 'kanata.kbd')) {
        $destination = Join-Path $ConfigHome $file
        $missingMarker = if ($original) { Join-Path $original ($file + '.missing') } else { $null }

        if ($missingMarker -and (Test-Path $missingMarker)) {
            if (Test-Path $destination) {
                Remove-Item -Path $destination -Force
                Write-Host "Removed $file (it did not exist before Plasmarchy)"
            }
            continue
        }

        $source = $null
        if ($original) {
            $candidate = Join-Path $original $file
            if (Test-Path $candidate) { $source = $candidate }
        }
        if ((-not $source) -and $last) {
            $candidate = Join-Path $last $file
            if (Test-Path $candidate) { $source = $candidate }
        }

        if ($source) {
            Copy-Item -Path $source -Destination $destination -Force
            Write-Host "Restored $file from $source"
        } else {
            Write-Warning "No pre-install backup for $file; left the current file in place."
        }
    }
}

function Remove-KanataTask {
    $taskName = 'Plasmarchy-Kanata'
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "Removed scheduled task $taskName"
    }
}

# ---------------------------------------------------------------------------
# Stop

Write-Step 'Stopping Plasmarchy'
$komorebic = Get-Komorebic
if ($komorebic) {
    try { & $komorebic stop 2>$null | Out-Null } catch { }
}
Get-Process -Name komorebi, masir -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Get-CimInstance Win32_Process -Filter "Name = 'AutoHotkey64.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*komorebi.ahk*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Get-Process -Name kanata_windows_gui_winIOv2_x64, kanata_windows_gui_wintercept_x64, kanata_gui, kanata -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# Autostart

Write-Step 'Removing autostart entries'
foreach ($name in @('Plasmarchy Komorebi.lnk', 'Plasmarchy Hotkeys.lnk', 'Plasmarchy Kanata.lnk')) {
    $path = Join-Path $StartupDir $name
    if (Test-Path $path) {
        Remove-Item -Path $path -Force
        Write-Host "Removed $path"
    }
}
Remove-KanataTask

# ---------------------------------------------------------------------------
# Settings and files

if (-not $KeepSettings) {
    Write-Step 'Restoring Windows settings'
    Restore-AnimationSettings
}

if ($RestoreBackup) {
    Write-Step 'Restoring configuration backup'
    Restore-ConfigFiles
}

if ($RemoveConfig) {
    Write-Step 'Removing Plasmarchy configuration'
    foreach ($path in @($ConfigPath, $AhkPath, $KanataCfg)) {
        if (Test-Path $path) {
            Remove-Item -Path $path -Force
            Write-Host "Removed $path"
        }
    }
}

if ($RemovePackages) {
    Write-Step 'Uninstalling packages'
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Warning 'winget.exe was not found; packages were not removed.'
    } else {
        foreach ($package in @('LGUG2Z.komorebi', 'LGUG2Z.masir', 'jtroo.kanata_gui', 'AutoHotkey.AutoHotkey', 'Microsoft.PowerToys')) {
            & winget.exe uninstall --id $package -e --silent --disable-interactivity
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "winget could not uninstall $package (exit $LASTEXITCODE)."
            }
        }
    }
}

if ($RemoveState) {
    if (Test-Path $StateDir) {
        Remove-Item -Path $StateDir -Recurse -Force
        Write-Host "Removed $StateDir"
    }
}

Write-Step 'Done'
Write-Host @"
The Plasmarchy Windows 11 layer has been stopped.

Configuration is still in: $ConfigHome
Backups are in:          $env:USERPROFILE\plasmarchy-backup-*

If animation/transparency settings were restored, sign out and back in to
apply them to Explorer and the shell.
"@ -ForegroundColor Green

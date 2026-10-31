#Requires -Version 5.1
<#
.SYNOPSIS
    Install the Plasmarchy Windows 11 layer: Komorebi, masir, AutoHotkey,
    PowerToys Run, and optionally Kanata.

.DESCRIPTION
    Copies the checked-in configuration into the Komorebi config home,
    creates logon entries, disables the most visible Windows animations, and
    starts the stack unless -NoStart is used.

    Existing komorebi.json / komorebi.ahk / kanata.kbd and the current
    animation-related registry values are copied to
    %USERPROFILE%\plasmarchy-backup-<timestamp> before anything is changed.

.PARAMETER SkipPackages
    Do not call winget. Use this when the packages are already installed.

.PARAMETER Kanata
    winget    - install jtroo.kanata_gui through winget (default)
    portable  - download the pinned Kanata v1.12.0 Windows x64 zip
    none      - do not install Kanata (Right Ctrl layout switching and Win+L
                interception will not work)

.PARAMETER KeepAnimations
    Leave Windows animation/transparency/snap settings untouched.

.PARAMETER NoStart
    Install and register autostart, but do not start Komorebi/AHK now.

.PARAMETER Force
    Continue on an unrecognised Windows build.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install-windows.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 -Kanata portable -NoStart
#>
[CmdletBinding()]
param(
    [switch]$SkipPackages,
    [ValidateSet('winget', 'portable', 'none')]
    [string]$Kanata = 'winget',
    [switch]$KeepAnimations,
    [switch]$NoStart,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
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
$OriginalDir = Join-Path $StateDir 'original'
$BackupRoot = Join-Path $env:USERPROFILE ('plasmarchy-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$StartupDir = [Environment]::GetFolderPath('Startup')

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Test-Admin {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-WingetPackage([string]$Id) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw "winget.exe was not found. Install App Installer from the Microsoft Store first."
    }
    Write-Host "winget install $Id"
    & winget.exe install --id $Id -e --source winget --silent `
        --accept-package-agreements --accept-source-agreements --disable-interactivity
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Write-Warning "winget returned $code for $Id (already installed or no applicable installer)."
    }
}

function Find-Executable {
    param(
        [string[]]$Names,
        [string[]]$ExtraDirs = @()
    )
    $dirs = @(
        $ConfigHome,
        $env:USERPROFILE,
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'),
        (Join-Path $env:LOCALAPPDATA 'Programs'),
        (Join-Path $env:LOCALAPPDATA 'PowerToys'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys'),
        (Join-Path $env:LOCALAPPDATA 'Programs\komorebi'),
        (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey'),
        (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2'),
        $env:ProgramFiles
    ) + $ExtraDirs

    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        $dirs += (Join-Path $base 'komorebi')
        $dirs += (Join-Path $base 'PowerToys')
    }

    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }

        foreach ($dir in $dirs) {
            if ([string]::IsNullOrWhiteSpace($dir)) { continue }
            $candidate = Join-Path $dir $name
            if (Test-Path $candidate) { return $candidate }
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

function Install-ScoopPackage {
    param([string]$Id)
    if (-not (Get-Command scoop.exe -ErrorAction SilentlyContinue)) { return $false }
    try {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        scoop install $Id 2>&1 | Out-Host
        $ErrorActionPreference = $previous
        return $true
    } catch {
        $ErrorActionPreference = 'Continue'
        Write-Warning "scoop install $Id failed: $($_.Exception.Message)"
        return $false
    }
}

function Request-ManualComponent {
    param(
        [string]$Name,
        [string]$DownloadUrl = '',
        [string[]]$Candidates = @(),
        [string[]]$ExtraDirs = @()
    )
    $resolved = $null
    while (-not $resolved) {
        Write-Host ''
        Write-Warning "$Name is still unavailable after the winget/scoop attempts."
        if (-not [string]::IsNullOrWhiteSpace($DownloadUrl)) {
            Write-Host "Download it here: $DownloadUrl"
            try { Start-Process $DownloadUrl | Out-Null } catch { }
        }
        Write-Host "Put the resulting binary in this folder and add it to PATH:"
        Write-Host "  $SoftwareDir"
        Write-Host "Candidate names: $($Candidates -join ', ')"
        $answer = Read-Host "Press Enter to re-check, or type 'skip' to continue without $Name"
        if ($answer -eq 'skip') { break }
        $resolved = Find-Executable -Names $Candidates -ExtraDirs $ExtraDirs
    }
    return $resolved
}



function New-StartupShortcut {
    param(
        [string]$Name,
        [string]$Target,
        [string]$Arguments,
        [string]$WorkingDirectory
    )
    if (-not (Test-Path $StartupDir)) {
        New-Item -ItemType Directory -Path $StartupDir -Force | Out-Null
    }
    $shortcutPath = Join-Path $StartupDir ($Name + '.lnk')
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $Target
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.WindowStyle = 7
    $shortcut.Description = 'Plasmarchy Windows 11'
    $shortcut.Save()
    return $shortcutPath
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

function Get-AnimationSettings {
    return @(
        @{ Path = 'HKCU:\Control Panel\Desktop\WindowMetrics'; Name = 'MinAnimate'; Kind = 'String'; Value = '0' },
        @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'MenuShowDelay'; Kind = 'String'; Value = '0' },
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarAnimations'; Kind = 'DWord'; Value = 0 },
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'SnapAssist'; Kind = 'DWord'; Value = 0 },
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'EnableSnapAssistFlyout'; Kind = 'DWord'; Value = 0 },
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'EnableTransparency'; Kind = 'DWord'; Value = 0 }
    )
}

function Backup-Settings {
    param([object[]]$Settings)
    $snapshot = foreach ($setting in $Settings) {
        $property = Get-ItemProperty -Path $setting.Path -Name $setting.Name -ErrorAction SilentlyContinue
        $value = $null
        if ($null -ne $property) {
            $value = $property.PSObject.Properties[$setting.Name].Value
        }
        [pscustomobject]@{
            Path   = $setting.Path
            Name   = $setting.Name
            Kind   = $setting.Kind
            Exists = ($null -ne $property)
            Value  = $value
        }
    }
    @($snapshot) | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $BackupRoot 'settings.json') -Encoding UTF8
}

function Apply-AnimationSettings {
    $settings = Get-AnimationSettings
    Backup-Settings -Settings $settings

    # Keep the first-run snapshot forever. Re-running the installer must not
    # overwrite the user's original values with Plasmarchy's already-applied
    # values, otherwise uninstall would "restore" the disabled state.
    $originalSettings = Join-Path $OriginalDir 'settings.json'
    if (-not (Test-Path $originalSettings)) {
        Copy-Item -Path (Join-Path $BackupRoot 'settings.json') -Destination $originalSettings -Force
    }

    foreach ($setting in $settings) {
        Set-RegValue -Path $setting.Path -Name $setting.Name -Value $setting.Value -Kind $setting.Kind
    }

    if (-not ('PlasmarchyNative' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public struct PlasmarchyAnimationInfo {
    public uint cbSize;
    public int iMinAnimate;
}
public static class PlasmarchyNative {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, ref PlasmarchyAnimationInfo pvParam, uint fWinIni);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);
}
'@
    }
    # SPI_SETANIMATION = 0x0049: ANIMATIONINFO { cbSize, iMinAnimate }.
    # SPIF_UPDATEINIFILE | SPIF_SENDCHANGE = 3.
    $animation = New-Object PlasmarchyAnimationInfo
    $animation.cbSize = 8
    $animation.iMinAnimate = 0
    [PlasmarchyNative]::SystemParametersInfo(0x0049, 8, [ref]$animation, 3) | Out-Null
    # SPI_SETMENUSHOWDELAY = 0x009B: uiParam is the delay in milliseconds.
    [PlasmarchyNative]::SystemParametersInfo(0x009B, 0, [IntPtr]::Zero, 3) | Out-Null
}

function Install-KanataPortable {
    $targetDir = Join-Path $StateDir 'kanata'
    $zip = Join-Path $env:TEMP ('plasmarchy-kanata-' + [guid]::NewGuid().ToString('N') + '.zip')
    $url = 'https://github.com/jtroo/kanata/releases/download/v1.12.0/windows-binaries-x64.zip'
    # Pinned SHA-256 of windows-binaries-x64.zip from the v1.12.0 release.
    $expectedHash = '13947ed78cfa3284bfef854e3c542c74ab366236b72fd9f7e039f8638deead9d'
    Write-Host "Downloading $url"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip
    $actualHash = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
        Remove-Item -Path $zip -Force -ErrorAction SilentlyContinue
        throw "Kanata archive checksum mismatch: expected $expectedHash, got $actualHash."
    }
    if (Test-Path $targetDir) {
        Remove-Item -Path $targetDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Expand-Archive -Path $zip -DestinationPath $targetDir -Force
    Remove-Item -Path $zip -Force -ErrorAction SilentlyContinue

    foreach ($name in @('kanata_windows_gui_winIOv2_x64.exe', 'kanata_windows_gui_wintercept_x64.exe', 'kanata.exe')) {
        $candidate = Join-Path $targetDir $name
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

function Register-KanataTask {
    param([string]$Executable, [string]$ConfigFile)
    $taskName = 'Plasmarchy-Kanata'
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $action = New-ScheduledTaskAction -Execute $Executable -Argument ('--cfg "' + $ConfigFile + '"')
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity
    # ExecutionTimeLimit=0 means unlimited; the Task Scheduler default would
    # terminate Kanata after three days. IgnoreNew avoids duplicate hooks if
    # the task is started again while Kanata is already running.
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    $principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Settings $settings -Principal $principal -Force `
        -Description 'Plasmarchy: Kanata keyboard remapping (Right Ctrl layout switch, Win+L -> F23)' | Out-Null
    Start-ScheduledTask -TaskName $taskName
}

# ---------------------------------------------------------------------------
# Preflight

Write-Step 'Preflight'
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$build = [int]$os.BuildNumber
Write-Host "Windows build: $build"
if ($build -lt 22000 -and -not $Force) {
    throw "Windows 11 (build 22000+) is required. Use -Force only for testing."
}
$isAdmin = Test-Admin
if (-not $isAdmin) {
    Write-Warning 'Not running elevated. Kanata will be skipped and some per-machine settings may not apply.'
}
if (-not (Test-Path $ConfigHome)) {
    New-Item -ItemType Directory -Path $ConfigHome -Force | Out-Null
}

# Persist a custom Komorebi config home, otherwise logon processes will not
# see the value set only in the current shell.
if ($env:KOMOREBI_CONFIG_HOME) {
    $persistedConfigHome = [Environment]::GetEnvironmentVariable('KOMOREBI_CONFIG_HOME', 'User')
    if ($persistedConfigHome -ne $ConfigHome) {
        Write-Warning "Persisting KOMOREBI_CONFIG_HOME=$ConfigHome for the current user so autostart sees it."
        [Environment]::SetEnvironmentVariable('KOMOREBI_CONFIG_HOME', $ConfigHome, 'User')
    }
}

New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
New-Item -ItemType Directory -Path $OriginalDir -Force | Out-Null
Write-Host "Komorebi config home: $ConfigHome"
Write-Host "Backup: $BackupRoot"
Write-Host "Original snapshot: $OriginalDir"

# Back up the three files that this script owns. The first-run copy in
# $OriginalDir is never overwritten; later runs only add a timestamped backup.
foreach ($file in @($ConfigPath, $AhkPath, $KanataCfg)) {
    $leaf = Split-Path -Leaf $file
    $originalFile = Join-Path $OriginalDir $leaf
    $missingMarker = Join-Path $OriginalDir ($leaf + '.missing')
    if (Test-Path $file) {
        Copy-Item -Path $file -Destination $BackupRoot -Force
        if ((-not (Test-Path $originalFile)) -and (-not (Test-Path $missingMarker))) {
            Copy-Item -Path $file -Destination $originalFile -Force
        }
    } else {
        # Record "there was no file" so a re-install does not mistake the
        # Plasmarchy copy for the user's original.
        if ((-not (Test-Path $originalFile)) -and (-not (Test-Path $missingMarker))) {
            Set-Content -Path $missingMarker -Value 'This file did not exist before Plasmarchy was installed.' -Encoding UTF8
        }
    }
}
foreach ($shortcutName in @('Plasmarchy Komorebi.lnk', 'Plasmarchy Hotkeys.lnk', 'Plasmarchy Kanata.lnk')) {
    $shortcut = Join-Path $StartupDir $shortcutName
    if (Test-Path $shortcut) {
        $shortcutBackup = Join-Path $BackupRoot 'startup'
        New-Item -ItemType Directory -Path $shortcutBackup -Force | Out-Null
        Copy-Item -Path $shortcut -Destination $shortcutBackup -Force
    }
}
$originalPointer = Join-Path $StateDir 'original-backup.txt'
if (-not (Test-Path $originalPointer)) {
    Set-Content -Path $originalPointer -Value $OriginalDir -Encoding UTF8
}
Set-Content -Path (Join-Path $StateDir 'last-backup.txt') -Value $BackupRoot -Encoding UTF8

# ---------------------------------------------------------------------------
# Packages

if (-not $SkipPackages) {
    Write-Step 'Installing packages (winget -> scoop -> direct download -> manual)'
    New-Item -ItemType Directory -Path $SoftwareDir -Force | Out-Null

    $packages = @(
        'LGUG2Z.komorebi',
        'LGUG2Z.masir',
        'AutoHotkey.AutoHotkey',
        'Microsoft.PowerToys'
    )
    if ($Kanata -eq 'winget') {
        $packages += 'jtroo.kanata_gui'
    }
    foreach ($package in $packages) {
        Install-WingetPackage -Id $package
    }

    # Scoop is tried for all package IDs. Package names differ between
    # managers, but Scoop simply prints an error for unknown IDs.
    if (Get-Command scoop.exe -ErrorAction SilentlyContinue) {
        Write-Step 'Trying Scoop for any missing packages'
        foreach ($package in $packages) {
            $stillMissing = -not (
                ($package -eq 'LGUG2Z.komorebi'   -and (Find-Executable -Names @('komorebic.exe'))) -or
                ($package -eq 'LGUG2Z.masir'        -and (Find-Executable -Names @('masir.exe'))) -or
                ($package -eq 'AutoHotkey.AutoHotkey' -and (Find-Executable -Names @('AutoHotkey64.exe'))) -or
                ($package -eq 'Microsoft.PowerToys' -and (Find-Executable -Names @('PowerToys.exe'))) -or
                ($package -eq 'jtroo.kanata_gui'    -and (Find-Executable -Names @('kanata.exe', 'kanata_gui.exe')))
            )
            if ($stillMissing) {
                Install-ScoopPackage -Id $package | Out-Null
            }
        }
    }

    # Direct downloads are attempted only for the two components whose archive
    # names are stable enough to build automatically.
    if (-not (Find-Executable -Names @('komorebic.exe', 'komorebic-no-console.exe'))) {
        Write-Step 'Trying a direct Komorebi download'
        $komorebiMsi = Join-Path $SoftwareDir 'komorebi-0.1.41-x86_64.msi'
        if (-not (Test-Path $komorebiMsi)) {
            try {
                Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/LGUG2Z/komorebi/releases/download/v0.1.41/komorebi-0.1.41-x86_64.msi' -OutFile $komorebiMsi
            } catch {
                Write-Warning "Komorebi direct download failed: $($_.Exception.Message)"
            }
        }
        if (Test-Path $komorebiMsi) {
            Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $komorebiMsi, '/qn', '/norestart') -Wait
        }
    }

    if ($Kanata -ne 'none' -and -not (Find-Executable -Names @('kanata.exe', 'kanata_windows_gui_winIOv2_x64.exe'))) {
        Write-Step 'Trying the pinned portable Kanata download'
        $kanataExe = Install-KanataPortable
    }
} else {
    Write-Step 'Skipping package managers (-SkipPackages)'
}

$komorebic = Find-Executable -Names @('komorebic-no-console.exe', 'komorebic.exe')
$komorebicConsole = Find-Executable -Names @('komorebic.exe', 'komorebic-no-console.exe')
$ahk = Find-Executable -Names @('AutoHotkey64.exe') -ExtraDirs @(
    (Join-Path $env:ProgramFiles 'AutoHotkey\v2'),
    (Join-Path $env:ProgramFiles 'AutoHotkey'),
    (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2'),
    (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey')
)
$masir = Find-Executable -Names @('masir.exe')
$masirOnPath = [bool](Get-Command 'masir.exe' -ErrorAction SilentlyContinue)
if (-not $masir) {
    $null = Request-ManualComponent -Name 'masir' -Candidates @('masir.exe') -DownloadUrl 'https://github.com/LGUG2Z/masir/releases/latest'
}

if (-not $komorebic) {
    $komorebic = Request-ManualComponent -Name 'Komorebi' `
        -Candidates @('komorebic.exe', 'komorebic-no-console.exe') `
        -DownloadUrl 'https://github.com/LGUG2Z/komorebi/releases/latest'
}
if (-not $komorebic) {
    throw 'komorebic.exe was not found. Install Komorebi and re-run this script.'
}

if (-not $ahk) {
    $ahk = Request-ManualComponent -Name 'AutoHotkey v2' `
        -Candidates @('AutoHotkey64.exe', 'AutoHotkey.exe') `
        -ExtraDirs @(
            (Join-Path $env:ProgramFiles 'AutoHotkey\v2'),
            (Join-Path $env:ProgramFiles 'AutoHotkey'),
            (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2'),
            (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey')
        ) `
        -DownloadUrl 'https://www.autohotkey.com/download/ahk-v2.exe'
    if (-not $ahk) { Write-Warning 'AutoHotkey64.exe was not found. Komorebi will start, but the shortcut layer will not.' }
}
if ($masir -and -not $masirOnPath) {
    Write-Warning "masir.exe was found at $masir but is not on PATH. komorebic start --masir requires PATH, so focus-follows-mouse will be skipped. Add that directory to PATH or install LGUG2Z.masir."
}

$komorebiDir = Split-Path -Parent $komorebic
if (-not (Get-Command 'komorebi.exe' -ErrorAction SilentlyContinue) -and
    -not (Test-Path (Join-Path $komorebiDir 'komorebi.exe'))) {
    Write-Warning "komorebi.exe was not found next to komorebic.exe or on PATH; 'komorebic start' may fail. Add the Komorebi directory to PATH."
}

$kanataExe = $null
if ($Kanata -ne 'none') {
    if ($Kanata -eq 'portable') {
        Write-Step 'Installing portable Kanata'
        $kanataExe = Install-KanataPortable
    } else {
        $kanataExe = Find-Executable -Names @(
            'kanata_windows_gui_winIOv2_x64.exe',
            'kanata_windows_gui_wintercept_x64.exe',
            'kanata_gui.exe',
            'kanata.exe'
        )
    }
    if (-not $kanataExe) {
        Write-Warning 'Kanata was not found. Right Ctrl layout switching and Win+L interception will be unavailable.'
    }
}

# ---------------------------------------------------------------------------
# Files

Write-Step 'Copying configuration'
Copy-Item -Path (Join-Path $ScriptRoot 'komorebi.json') -Destination $ConfigPath -Force
Copy-Item -Path (Join-Path $ScriptRoot 'komorebi.ahk') -Destination $AhkPath -Force
Copy-Item -Path (Join-Path $ScriptRoot 'kanata.kbd') -Destination $KanataCfg -Force
Write-Host "  $ConfigPath"
Write-Host "  $AhkPath"
Write-Host "  $KanataCfg"

Write-Step 'Validating komorebi.json'
& $komorebicConsole check -k $ConfigPath
if ($LASTEXITCODE -ne 0) {
    throw 'komorebic check failed. Fix komorebi.json or restore the backup and re-run.'
}

if ($Kanata -ne 'none' -and -not $kanataExe) {
    $kanataExe = Request-ManualComponent -Name 'Kanata' `
        -Candidates @('kanata_windows_gui_winIOv2_x64.exe', 'kanata_windows_gui_wintercept_x64.exe', 'kanata_gui.exe', 'kanata.exe') `
        -DownloadUrl 'https://github.com/jtroo/kanata/releases/latest'
}
if ($kanataExe) {
    Write-Step 'Validating kanata.kbd'
    & $kanataExe --check --cfg $KanataCfg
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "kanata --check returned $LASTEXITCODE. Inspect the output above before relying on Right Ctrl or Win+L."
    }
}

# ---------------------------------------------------------------------------
# Autostart

Write-Step 'Registering autostart'
$komorebiArgs = 'start -c "' + $ConfigPath + '"'
if ($masirOnPath) { $komorebiArgs += ' --masir' }
New-StartupShortcut -Name 'Plasmarchy Komorebi' -Target $komorebic -Arguments $komorebiArgs -WorkingDirectory $komorebiDir | Out-Null

if ($ahk) {
    New-StartupShortcut -Name 'Plasmarchy Hotkeys' -Target $ahk -Arguments ('"' + $AhkPath + '"') -WorkingDirectory $ConfigHome | Out-Null
}

if ($kanataExe) {
    if ($isAdmin) {
        try {
            Register-KanataTask -Executable $kanataExe -ConfigFile $KanataCfg
        } catch {
            Write-Warning "Could not register the Kanata scheduled task: $($_.Exception.Message)"
        }
    } else {
        Write-Warning 'Kanata needs administrator rights. Re-run this script elevated to register its scheduled task.'
    }
}

# Remove the obsolete shortcut name if an older install created it.
$oldKanataShortcut = Join-Path $StartupDir 'Plasmarchy Kanata.lnk'
if (Test-Path $oldKanataShortcut) { Remove-Item -Path $oldKanataShortcut -Force }

# ---------------------------------------------------------------------------
# Windows appearance

if (-not $KeepAnimations) {
    Write-Step 'Disabling Windows animations / transparency / snap assist'
    Apply-AnimationSettings
} else {
    Write-Step 'Keeping current Windows animation settings (-KeepAnimations)'
}

# ---------------------------------------------------------------------------
# Start

if (-not $NoStart) {
    Write-Step 'Restarting Komorebi'
    try { & $komorebicConsole stop 2>$null | Out-Null } catch { }
    Get-Process -Name komorebi, masir -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 400

    $startArgs = @('start', '-c', ('"' + $ConfigPath + '"'))
    if ($masirOnPath) { $startArgs += '--masir' }
    Start-Process -FilePath $komorebicConsole -ArgumentList $startArgs -WorkingDirectory $komorebiDir -WindowStyle Hidden
    Start-Sleep -Seconds 1

    if ($ahk) {
        Start-Process -FilePath $ahk -ArgumentList ('"' + $AhkPath + '"')
    }
    Write-Host 'Komorebi and the shortcut layer were started.'
} else {
    Write-Step 'Skipping immediate start (-NoStart)'
}

# ---------------------------------------------------------------------------
# Summary

Write-Step 'Done'
Write-Host @"
Plasmarchy Windows 11 is installed.

Next steps:
  1. Sign out and sign in again (MinAnimate and the Kanata task need a fresh session).
  2. In Settings > Time & language > Typing > Advanced keyboard settings >
     Input language hot keys, set both shortcuts to "Not Assigned".
     Right Ctrl is the only layout switch.
  3. Open PowerToys Run once (Alt+Space) and leave PowerToys running.
  4. Run verify-windows.ps1 in a new session.

Config:  $ConfigPath
Hotkeys: $AhkPath
Kanata:  $KanataCfg
Backup:  $BackupRoot
Log:     $StateDir
"@ -ForegroundColor Green

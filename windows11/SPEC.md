# Plasmarchy Windows 11 — Agent Implementation Specification

Status: **implementation complete; static validation only**. The PowerShell,
AutoHotkey, Kanata, and Komorebi files have been parsed or schema-validated,
but the stack has not yet been exercised on a live Windows 11 machine.

| Item | Value |
| --- | --- |
| Target OS | Windows 11 build 22000+ (22H2 or newer recommended), x64 |
| Linux counterpart | [`../README.md`](../README.md), [`../install.sh`](../install.sh) |
| Config source of truth | `komorebi.json`, `komorebi.ahk`, `kanata.kbd` |
| Installer | `install-windows.ps1` (PowerShell 5.1+) |
| Verifier | `verify-windows.ps1` |
| Rollback | `uninstall-windows.ps1` |
| Komorebi | v0.1.41 |
| masir | v0.1.2 |
| AutoHotkey | v2.0 |
| Kanata | v1.12.0 (optional but required for Right Ctrl and Win+L behavior) |
| Window manager layout | BSP (closest supported analogue of Hyprland `dwindle`) |

This directory is independent of the Linux/Plasma deployment. Adding or
changing files here does not alter `deploy.sh`, `install.sh`, or the Plasma
configuration snapshot.

---

## 1. What this reproduces

| Omarchy / KDE Plasma | Windows 11 implementation | Fidelity |
| --- | --- | --- |
| Krohnkite `Dwindle` tiling | Komorebi `BSP` | Close; BSP insertion order differs from Dwindle |
| Aurorae 2 px active gradient border | Komorebi 2 px square border, solid teal `#00D9B0` | Approximation; no native gradient |
| Inactive grey border `#595959` | Komorebi unfocused border `#595959` | Exact colour |
| No titlebars on tiles | `remove_titlebar_applications` regex for all executables | Global; see risks |
| Gaps 10 / 5 | Workspace padding 10, container padding 2, 2 px border | Visible inter-window gap ≈ 4 px, not 5 |
| Focus follows mouse | `masir` | Hover does not warp the pointer |
| Mouse follows focus | Komorebi `mouse_follows_focus: true` | Keyboard focus centers the pointer |
| KRunner on `Meta+Space` | PowerToys Run on `Alt+Space` | Close; different plugin ecosystem |
| KGlobalAccel shortcuts | AutoHotkey v2 | Win-key chords, terminal-aware clipboard |
| Right Ctrl layout switch | Kanata tap → `F24` → AHK `WM_INPUTLANGCHANGEREQUEST` | Requires Kanata + elevation |
| `Meta+L` next layout | Kanata `Win+L` → `F23` → AHK → Komorebi | Win+L is reserved by Windows |
| `Meta+Shift+N` moves window | `Win+Shift+1…9` moves and follows | N means a digit, not the letter N |
| `Meta+Shift+Alt+N` moves silently | `Win+Shift+Alt+1…9` sends without following | Exact Komorebi semantic |
| KWin animations disabled | Komorebi animation off + Windows registry | Windows shell animations may still need sign-out |
| Display hotplug retile | Komorebi monitor reconciliator | Built in; verify on real hardware |

Non-goals:

- Reproducing Plasma panels, widgets, activities, or KWin effects.
- Replacing Windows Explorer or the taskbar.
- Reimplementing KRunner plugins; PowerToys Run is the launcher.
- Removing DWM shadows or rounded corners globally; Windows has no supported
  per-window equivalent of KWin's shadow/corner settings.

---

## 2. Architecture

```text
Physical keyboard
   │
   ├── ordinary keys ───────────────────────────────► Windows applications
   │
   ├── Right Ctrl tap ── Kanata ──► F24 ── AHK ──► WM_INPUTLANGCHANGEREQUEST
   │
   ├── Win+L ─────────── Kanata ──► F23 ── AHK ──► komorebic cycle-layout next
   │
   └── Win+… ─────────── AHK ─────► komorebic / Run / Send

Mouse hover ── masir ──► foreground window (no pointer warp)
Keyboard focus ── Komorebi mouse_follows_focus ──► pointer centers in window

AHK ── komorebic.exe ──► Komorebi ──► Windows DWM / Win32 window placement
```

### Components

| Layer | Process | Binary | Started by | Responsibility |
| --- | --- | --- | --- | --- |
| Low-level remapper | Kanata | `kanata_windows_gui_winIOv2_x64.exe` | Scheduled task `Plasmarchy-Kanata` at logon, elevated | CapsLock/Right Ctrl tap-hold, Win+L → F23 |
| Window manager | Komorebi | `komorebic.exe` / `komorebic-no-console.exe` | Startup shortcut `Plasmarchy Komorebi.lnk` | BSP tiling, workspaces, borders, titlebar removal |
| Focus-follows-mouse | masir | `masir.exe` | `komorebic start --masir` | Hover focus without pointer warp |
| Shortcut layer | AutoHotkey v2 | `AutoHotkey64.exe` | Startup shortcut `Plasmarchy Hotkeys.lnk` | Omarchy key map, clipboard, layout switch, app launch |
| Launcher | PowerToys Run | `PowerToys.PowerLauncher.exe` | PowerToys autostart | `Alt+Space`; AHK maps `Win+Space` to it |

### Startup order

1. **Kanata** starts from the elevated scheduled task. It must be running
   before a Right Ctrl tap or `Win+L` can produce `F24` / `F23`.
2. **Komorebi** starts with `komorebic start -c <config>` and adds
   `--masir` when `masir.exe` is on `PATH`.
3. **masir** is started as a child of `komorebic`; it is not a separate
   startup entry.
4. **AutoHotkey** starts `komorebi.ahk`.
5. **PowerToys** starts through its own autostart; AHK can start
   `PowerToys.PowerLauncher.exe` on demand if PowerToys is installed but not
   running.

---

## 3. Installed paths

### 3.1 Configuration home

Default:

```text
%USERPROFILE%\
├── komorebi.json
├── komorebi.ahk
└── kanata.kbd
```

Override with `KOMOREBI_CONFIG_HOME`. The installer persists a custom value at
user scope so logon processes and the scheduled task see the same path:

```powershell
[Environment]::SetEnvironmentVariable('KOMOREBI_CONFIG_HOME', $ConfigHome, 'User')
```

The installer deliberately does **not** copy `applications.json`. `komorebic
check` may print a hint about `komorebic fetch-asc`; that is optional. App
rules that matter are in `komorebi.json`.

### 3.2 Full path inventory

| Path | Created by | Purpose |
| --- | --- | --- |
| `%USERPROFILE%\komorebi.json` | installer | Komorebi static configuration |
| `%USERPROFILE%\komorebi.ahk` | installer | AutoHotkey v2 shortcut layer |
| `%USERPROFILE%\kanata.kbd` | installer | Kanata remap configuration |
| `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Plasmarchy Komorebi.lnk` | installer | Runs `komorebic start -c ...` at logon; adds `--masir` when masir is on `PATH` |
| `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Plasmarchy Hotkeys.lnk` | installer | Runs `AutoHotkey64.exe komorebi.ahk` at logon |
| `%LOCALAPPDATA%\Plasmarchy\original\` | installer | Permanent first-run snapshots |
| `%LOCALAPPDATA%\Plasmarchy\original\komorebi.json` | first run | Original user config, if it existed |
| `%LOCALAPPDATA%\Plasmarchy\original\komorebi.json.missing` | first run | Marker: no original file existed |
| `%LOCALAPPDATA%\Plasmarchy\original\settings.json` | first run | Original animation/transparency registry values |
| `%LOCALAPPDATA%\Plasmarchy\original-backup.txt` | installer | Pointer to the permanent original snapshot |
| `%LOCALAPPDATA%\Plasmarchy\last-backup.txt` | installer | Pointer to the newest timestamped backup |
| `%LOCALAPPDATA%\Plasmarchy\kanata\` | `-Kanata portable` | Extracted Kanata binaries |
| `%USERPROFILE%\plasmarchy-backup-<yyyyMMdd-HHmmss>\` | every run | Timestamped pre-change backup |
| Scheduled task `Plasmarchy-Kanata` | installer | Elevated Kanata logon task |

When `KOMOREBI_CONFIG_HOME` is set, replace `%USERPROFILE%` with that
directory in the first three rows.

### 3.3 Package and portable paths

| Component | Winget ID | Portable asset | Expected executable | Installer search path |
| --- | --- | --- | --- | --- |
| Komorebi | `LGUG2Z.komorebi` | `komorebi-0.1.41-x86_64-pc-windows-msvc.zip` | `komorebic.exe`, `komorebic-no-console.exe` | WinGet Links/Packages, `%LOCALAPPDATA%\Programs\komorebi`, `%ProgramFiles%\komorebi` |
| masir | `LGUG2Z.masir` | `masir-0.1.2-x86_64-pc-windows-msvc.zip` | `masir.exe` | WinGet Links/Packages, `%LOCALAPPDATA%\Programs`, `%ProgramFiles%` |
| AutoHotkey | `AutoHotkey.AutoHotkey` | AutoHotkey v2 portable zip | `AutoHotkey64.exe` | WinGet Links/Packages, `%LOCALAPPDATA%\Programs\AutoHotkey\v2`, `%ProgramFiles%\AutoHotkey\v2` |
| PowerToys | `Microsoft.PowerToys` | none (installer only) | `PowerToys.PowerLauncher.exe` | `%ProgramFiles%\PowerToys`, `%LOCALAPPDATA%\PowerToys`, `%LOCALAPPDATA%\Microsoft\PowerToys`, WinGet Packages |
| Kanata | `jtroo.kanata_gui` | `windows-binaries-x64.zip` | `kanata_windows_gui_winIOv2_x64.exe` | WinGet Links/Packages, `%LOCALAPPDATA%\Plasmarchy\kanata` |

Download URLs:

```text
https://github.com/LGUG2Z/komorebi/releases/download/v0.1.41/komorebi-0.1.41-x86_64-pc-windows-msvc.zip
https://github.com/LGUG2Z/masir/releases/download/v0.1.2/masir-0.1.2-x86_64-pc-windows-msvc.zip
https://github.com/jtroo/kanata/releases/download/v1.12.0/windows-binaries-x64.zip
```

Portable Komorebi example:

```powershell
$dest = "$env:LOCALAPPDATA\Programs\komorebi"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Invoke-WebRequest -UseBasicParsing `
  -Uri 'https://github.com/LGUG2Z/komorebi/releases/download/v0.1.41/komorebi-0.1.41-x86_64-pc-windows-msvc.zip' `
  -OutFile "$env:TEMP\komorebi.zip"
Expand-Archive -Path "$env:TEMP\komorebi.zip" -DestinationPath $dest -Force

# Add the directory to PATH so komorebic can launch komorebi.exe by name.
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if (($userPath -split ';') -notcontains $dest) {
    [Environment]::SetEnvironmentVariable('PATH', "$dest;$userPath", 'User')
}
$env:PATH = "$dest;$env:PATH"
```

The installer sets the autostart working directory to the directory containing
`komorebic.exe`, so a portable `komorebi.exe` next to it is found even before
PATH is refreshed. Adding the directory to PATH is still recommended for
launching `komorebic` from arbitrary shells.

Portable masir note: `komorebic start --masir` resolves `masir.exe` through
`PATH`. If you unpack masir manually, put its directory on `PATH` or use the
winget package. The installer only passes `--masir` when `masir.exe` is on
`PATH`; it warns and starts Komorebi without hover focus otherwise. Unlike
Kanata, the installer does not start masir by absolute path.

Portable Kanata is handled by the installer:

```powershell
.\install-windows.ps1 -Kanata portable
```

It downloads the pinned v1.12.0 archive, verifies its SHA-256, extracts into
`%LOCALAPPDATA%\Plasmarchy\kanata`, and registers the scheduled task with the
full executable path.

---

## 4. Installation

### 4.1 Prerequisites

- Windows 11 build 22000+ (x64).
- PowerShell 5.1+; PowerShell 7 also works for the scripts themselves.
- `winget.exe` / App Installer for the default installation path.
- Administrator rights for Kanata. The Kanata scheduled task is registered
  with `RunLevel Highest`; without elevation the installer skips it and warns.
- PowerToys installed and running for `Win+Space` → PowerToys Run.
- Optional: Windows Terminal (`wt.exe`), WSL (`wsl.exe`), and the applications
  referenced by the app shortcuts. Missing applications produce a tray
  notification instead of a crash.
- In Windows **Settings → Time & language → Typing → Advanced keyboard
  settings → Input language hot keys**, set both shortcuts to **Not Assigned**.
  Right Ctrl is the only keyboard layout switch.

### 4.2 Default install

Open an elevated PowerShell in this directory:

```powershell
cd windows11
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-windows.ps1
```

Or install without starting the stack yet:

```powershell
.\install-windows.ps1 -NoStart
```

The script runs `winget install --id <id> -e --source winget --silent` for:

- `LGUG2Z.komorebi`
- `LGUG2Z.masir`
- `AutoHotkey.AutoHotkey`
- `Microsoft.PowerToys`
- `jtroo.kanata_gui` when `-Kanata winget` (the default)

### 4.3 Parameters

| Parameter | Values | Default | Effect |
| --- | --- | --- | --- |
| `-SkipPackages` | switch | off | Do not call `winget`; use already-installed binaries |
| `-Kanata` | `winget`, `portable`, `none` | `winget` | How to provide Kanata |
| `-KeepAnimations` | switch | off | Do not change animation/transparency/snap registry values |
| `-NoStart` | switch | off | Register autostart but do not start Komorebi/AHK now |
| `-Force` | switch | off | Continue on a Windows build older than 22000 |

Examples:

```powershell
# Fully offline: binaries already installed, no immediate restart
.\install-windows.ps1 -SkipPackages -NoStart

# Pin Kanata to the portable v1.12.0 archive
.\install-windows.ps1 -Kanata portable

# No Kanata: Win+L locks the screen and Right Ctrl no longer switches layout
.\install-windows.ps1 -Kanata none
```

### 4.4 What the installer changes

| Step | Action |
| --- | --- |
| 1 | Checks Windows build; refuses pre-Windows 11 unless `-Force` |
| 2 | Warns if not elevated; Kanata task is skipped without admin |
| 3 | Creates the config home, state directory, and first-run snapshot directory |
| 4 | Persists a custom `KOMOREBI_CONFIG_HOME` at user scope |
| 5 | Copies existing config files and startup shortcuts into a timestamped backup |
| 6 | Preserves the first-run `komorebi.json` / `komorebi.ahk` / `kanata.kbd` or records `.missing` markers |
| 7 | Installs winget packages unless `-SkipPackages` |
| 8 | Copies the three checked-in config files into the config home |
| 9 | Runs `komorebic check -k <config>` and aborts on failure; runs `kanata --check` when Kanata is present |
| 10 | Creates `Plasmarchy Komorebi.lnk` and `Plasmarchy Hotkeys.lnk` |
| 11 | Registers and starts `Plasmarchy-Kanata` when Kanata is available and the shell is elevated |
| 12 | Disables animations/transparency/snap assist unless `-KeepAnimations` |
| 13 | Stops old Komorebi/masir processes and starts Komorebi + AHK unless `-NoStart` |

The installer does **not** install optional applications (browsers, Telegram,
Steam, Lutris, LocalSend, Scan, WSL distributions, etc.). App shortcuts fail
gracefully if their target is absent.

### 4.5 Backup semantics

There are two distinct backup layers:

| Layer | Location | Lifetime | Used by |
| --- | --- | --- | --- |
| First-run original | `%LOCALAPPDATA%\Plasmarchy\original` | Permanent; never overwritten | `uninstall-windows.ps1 -RestoreBackup` |
| Timestamped run backup | `%USERPROFILE%\plasmarchy-backup-<timestamp>` | One per install run | Manual inspection/recovery |

The first-run layer is important: a second install must not copy Plasmarchy's
own already-installed config into the "original" snapshot. The `.missing`
markers record that a file did not exist before Plasmarchy, so uninstall can
remove the file instead of pretending to restore it.

The animation settings snapshot follows the same rule: the first-run
`settings.json` is copied before any registry change and is never overwritten.

The first-run snapshot is not a version history. If you edit `komorebi.json`
or `komorebi.ahk` after installing, the next run's timestamped backup contains
that edited version; use it for manual recovery if you need later changes.


---

## 5. Komorebi configuration

`komorebi.json` is validated against the Komorebi v0.1.41 schema.

### 5.1 Core settings

| Key | Value | Reason |
| --- | --- | --- |
| `window_hiding_behaviour` | `Cloak` | Hide windows on inactive workspaces without moving them off-screen |
| `cross_monitor_move_behaviour` | `Insert` | Insert moved windows into the target layout |
| `default_workspace_padding` | `10` | Outer gap at monitor edges |
| `default_container_padding` | `2` | Gap around each tiled container |
| `border` | `true` | Enable Komorebi borders |
| `border_width` | `2` | 2 px frame, matching Plasma |
| `border_offset` | `-1` | Draw the border tight to the window; avoids a visible seam |
| `border_style` | `Square` | No rounded corners from Komorebi |
| `border_implementation` | `Komorebi` | Use Komorebi's native border renderer |
| `border_colours.single` | `#00D9B0` | Active teal approximation of the cyan→green gradient |
| `border_colours.stack` | `#00D9B0` | Same active colour for stacked containers |
| `border_colours.monocle` | `#00D9B0` | Same active colour in monocle |
| `border_colours.floating` | `#00D9B0` | Same active colour for floating windows |
| `border_colours.unfocused` | `#595959` | Inactive grey, identical to Plasma |
| `border_colours.unfocused_locked` | `#595959` | Inactive grey |
| `animation.enabled` | `false` | Instant movement |
| `mouse_follows_focus` | `true` | Center pointer on Komorebi-initiated keyboard focus |
| `resize_delta` | `32` | Resize step in pixels |
| `window_container_behaviour` | `Create` | New windows become new containers |
| `float_override` | `false` | Do not force floating |
| `transparency` | `false` | No Komorebi transparency |

`focus_follows_mouse` is intentionally absent. It is an end-of-life Komorebi
feature; hover focus is provided by `masir`, started through
`komorebic start --masir`. Do not add `focus_follows_mouse` to the config.

### 5.2 Gaps and border geometry

| Measurement | Plasma/Linux | Windows/Komorebi |
| --- | --- | --- |
| Outer workspace gap | 10 px | 10 px |
| Per-container padding | 5 px total | 2 px per side |
| Border width | 2 px | 2 px |
| Visible gap between two windows | 5 px | ≈ 4 px |
| Active border | Cyan→green gradient | Solid `#00D9B0` |
| Inactive border | `#595959` | `#595959` |

Komorebi applies container padding symmetrically, so two adjacent windows
receive `2 + 2 = 4` px between them. Obtaining exactly 5 px would require an
asymmetric or per-monitor workaround that Komorebi does not expose cleanly.
The 1 px difference is accepted and documented.

### 5.3 Application rules

| Rule list | Applications | Effect |
| --- | --- | --- |
| `remove_titlebar_applications` | all executables (`.*` regex) | Remove native titlebars globally, including browsers, Steam, Telegram, Lutris, LocalSend, Scan |
| `border_overflow_applications` | `chrome.exe`, `msedge.exe`, `brave.exe`, `firefox.exe`, `zen.exe`, `steam.exe`, `Telegram.exe`, `lutris.exe`, `LocalSend.exe`, `WindowsScan.exe` | Let the Komorebi border cover client-area overflow |
| `manage_rules` | same list as border overflow | Force these apps to be managed by Komorebi |
| `tray_and_multi_window_applications` | `steam.exe`, `Telegram.exe`, `Discord.exe`, `Spotify.exe`, `lutris.exe`, `LocalSend.exe` | Treat secondary/tray windows correctly |
| `ignore_rules` | `PowerToys.PowerLauncher.exe`, `PowerToys.ColorPickerUI.exe`, `PowerToys.TextExtractor.exe` | Do not tile launcher/overlay windows |

Risks:

- `remove_titlebar_applications: .*` hides titlebars from **every** normal
  window. Most apps are fine because Komorebi manages them; a few apps with
  custom chrome or modal windows may lose their drag handle. Use `Win+T` to
  float, or replace the global regex with an explicit allow-list if a critical
  app needs its titlebar.
- `border_overflow_applications` is a fixed list. Apps with unusual custom
  frames that are not in the list may still show 1–2 px of client overflow.
  Add the executable to both `border_overflow_applications` and `manage_rules`.
- Browsers and Electron apps can create elevated or cloaked windows. If a
  browser appears above everything, verify that its executable is in
  `manage_rules` and that it is not running elevated.
- Windows may still draw DWM shadows and rounded corners around the Komorebi
  frame. There is no supported global per-window switch to remove them.

### 5.4 Workspaces and monitors

`komorebi.json` declares two monitors with nine BSP workspaces each:

```json
"monitors": [
  { "workspaces": [ { "name": "1", "layout": "BSP" }, ... ] },
  { "workspaces": [ { "name": "1", "layout": "BSP" }, ... ] }
]
```

- Workspace indices in `komorebic` are **zero-based**: `focus-workspace 0` is
  the first workspace, which AHK maps to `Win+1`.
- `move-to-workspace <idx>` moves the focused window and follows it.
- `send-to-workspace <idx>` moves the window but leaves the current view.
- Komorebi's monitor reconciliator listens for display topology changes. On
  unplug, the remaining monitor keeps its workspace set and retiles. On
  replug, the second monitor returns. Verify on real hardware; Windows monitor
  ordering can change which physical display is index 0.
- `komorebic monitor-information` prints the live monitor map. Use it if the
  workspace/monitor assignment does not match the physical layout.
- `Win+Ctrl+Delete` runs `DisplaySwitch.exe /internal` for a manual
  laptop-panel-only switch; `Win+Ctrl+Alt+Delete` runs `/clone`.

---

## 6. Keyboard implementation

### 6.1 Kanata

`kanata.kbd` is validated with the Kanata v1.12.0 binary (`config file is
valid`).

| Physical key | Tap | Hold | Notes |
| --- | --- | --- | --- |
| `CapsLock` | `Esc` | Left `Ctrl` | No CapsLock behavior remains |
| Right `Ctrl` | `F24` | Left `Ctrl` | `F24` is caught by AHK and switches layout |
| Left `Win` + `L` | `F23` | — | Bare chord only; Ctrl/Alt/Shift are excluded |
| Right `Win` + `L` | `F23` | — | Same override for the right Windows key |
| Everything else | Unchanged | Unchanged | `process-unmapped-keys yes` |

Key settings:

```lisp
(defcfg
  process-unmapped-keys yes
  override-release-on-activation yes
)

(defvar tap-time 200)
(defvar hold-time 200)

(defoverridesv2
  (lmet l) (f23) (lctl rctl lalt ralt lsft rsft) ()
  (rmet l) (f23) (lctl rctl lalt ralt lsft rsft) ()
)
```

- Tap/hold threshold is 200 ms. A Right Ctrl tap shorter than 200 ms emits
  `F24`; a longer press acts as Ctrl.
- `override-release-on-activation yes` ensures the physical Win/L keys are
  released when the override fires.
- Kanata needs administrator rights because it installs a low-level keyboard
  hook. The installer creates the `Plasmarchy-Kanata` scheduled task with
  `RunLevel Highest` and starts it immediately.
- Without Kanata:
  - Right Ctrl remains a normal Ctrl; there is no keyboard layout switch.
  - `Win+L` locks the screen (native Windows behavior).
  - `Win+Ctrl+L` remains the lock shortcut.
  - `CapsLock` remains CapsLock.
- With Kanata:
  - `Win+L` cycles to the next layout.
  - `Win+Ctrl+L` still locks because the `defoverridesv2` entries exclude
    Ctrl/Alt/Shift; only bare `Win+L` is rewritten.
  - `Win+Alt+L` cycles to the previous layout.

### 6.2 AutoHotkey layers

`komorebi.ahk` uses AutoHotkey v2 syntax:

| Prefix | Modifier |
| --- | --- |
| `#` | Win (Meta) |
| `!` | Alt |
| `^` | Ctrl |
| `+` | Shift |

Important helpers:

- `RunKomorebi(args)` invokes `komorebic-no-console.exe` or `komorebic.exe`
  hidden. If the binary is missing, a tray tip is shown instead of a crash.
- `ReleaseModifiers()` releases Win/Ctrl/Alt/Shift before injecting a different
  chord. This is required because AHK hotkeys fire while the physical modifiers
  are still down. Without it, `Win+Ctrl+C` can become `Ctrl+Win+C` in the
  target application.
- `IsWindowsTerminal()` detects Windows Terminal, OpenConsole, Alacritty,
  WezTerm, mintty, Tabby, and Hyper. Legacy `conhost.exe`, `cmd.exe`, and
  `powershell.exe` are intentionally not in this list.
- `SendTerminalAware(key)` sends `Ctrl+Shift+<key>` to modern terminals and
  `Ctrl+<key>` elsewhere.
- `SwitchLayout()` enumerates keyboard layouts, finds the current layout for
  the foreground window, and posts `WM_INPUTLANGCHANGEREQUEST` (`0x0050`) to
  that window. It does not change the layout only for the AHK thread.
- `OpenRun()` sends `Alt+Space` to PowerToys Run. If PowerToys is installed but
  not running, it starts `PowerToys.PowerLauncher.exe` first.

### 6.3 Session and workspace shortcuts

`Win` is the leader key. `N` below means a digit **1–9**, not the letter N.

| Shortcut | Action | Implementation |
| --- | --- | --- |
| `Win+Space` | Open PowerToys Run | AHK → `Alt+Space` |
| `Win+Alt+Space` | Task View | `explorer.exe shell:::{3080F90E-...}` |
| `Win+G` | Task View | Same |
| `Win+Tab` | Next workspace | `komorebic cycle-workspace next` |
| `Win+Shift+Tab` | Previous workspace | `komorebic cycle-workspace previous` |
| `Ctrl+Alt+Tab` | Next monitor | `komorebic cycle-monitor next` |
| `Ctrl+Alt+Shift+Tab` | Previous monitor | `komorebic cycle-monitor previous` |
| `Win+Alt+Tab` | Per-app window switcher (next) | Releases Win+Alt, sends `Alt+\`` |
| `Win+Alt+Shift+Tab` | Per-app window switcher (previous) | Releases Win+Alt+Shift, sends `Alt+Shift+\`` |
| `Win+1…9` | Focus workspace N | `komorebic focus-workspace 0…8` |
| `Win+Shift+1…9` | Move window to workspace N and follow | `komorebic move-to-workspace 0…8` |
| `Win+Shift+Alt+1…9` | Send window to workspace N without following | `komorebic send-to-workspace 0…8` |
| `Win+Escape` | Power overlay | `SlideToShutDown.exe` |
| `Win+Ctrl+L` | Lock screen | `rundll32.exe user32.dll,LockWorkStation` |
| `Win+Ctrl+I` | Sign-in options | `ms-settings:signinoptions` |
| `Win+K` | Keyboard settings | `ms-settings:keyboard` |
| `Win+Ctrl+Delete` | Internal display only | `DisplaySwitch.exe /internal` |
| `Win+Ctrl+Alt+Delete` | Clone displays | `DisplaySwitch.exe /clone` |
| `Win+Ctrl+X` / `F9` | Toggle dictation | `Win+H` |
| `Win+Ctrl+E` | Emoji picker | `Win+.` |
| `Win+Ctrl+T` / `Win+Ctrl+Shift+Space` | Themes | `ms-settings:themes` |
| `Win+Ctrl+W` / `Win+Ctrl+Space` | Background | `ms-settings:personalization-background` |

### 6.4 Tiling and window shortcuts

| Shortcut | Action | `komorebic` command |
| --- | --- | --- |
| `Win+Left/Right/Up/Down` | Focus in direction | `focus left/right/up/down` |
| `Win+Shift+Left/Right/Up/Down` | Move/swap in direction | `move left/right/up/down` |
| `Win+Ctrl+Left/Right` | Focus previous/next monitor | `cycle-monitor previous/next` |
| `Win+Ctrl+Shift+Left/Right` | Move window previous/next monitor | `cycle-move-to-monitor previous/next` |
| `Win+T` | Toggle floating | `toggle-float` |
| `Win+L` | Next layout | Kanata `F23` → AHK → `cycle-layout next` |
| `Win+Alt+L` | Previous layout | `cycle-layout previous` |
| `Win+J` | Flip layout horizontally | `flip-layout horizontal` |
| `Win+F` | Monocle mode | `toggle-monocle` |
| `Win+Alt+F` / `Win+Ctrl+F` | Maximize | `toggle-maximize` |
| `Win+=` | Shrink width | `resize-axis horizontal decrease` |
| `Win+-` | Grow width | `resize-axis horizontal increase` |
| `Win+Shift+=` | Grow height | `resize-axis vertical increase` |
| `Win+Shift+-` | Shrink height | `resize-axis vertical decrease` |
| `Win+W` / `Win+Q` | Close window | `close` |

Komorebi has no separate borderless fullscreen command. `Win+F` is mapped to
monocle, the closest tiling equivalent of KDE's `Meta+F` fullscreen. Use
`Win+Alt+F` or `Win+Ctrl+F` for a maximized window that remains under
Komorebi management.

### 6.5 Clipboard shortcuts

| Shortcut | Action | Target-aware chord |
| --- | --- | --- |
| `Win+C` | Copy | `Ctrl+C`; `Ctrl+Shift+C` in modern terminals |
| `Win+X` | Cut | `Ctrl+X`; `Ctrl+Shift+X` in modern terminals |
| `Win+V` | Paste | `Ctrl+V`; `Ctrl+Shift+V` in modern terminals |
| `Alt+Shift+L` | Copy current browser URL | Releases Alt+Shift, sends `Ctrl+L`, `Ctrl+C` |
| `Alt+Shift+D` | Download clipboard URL with yt-dlp | Runs `yt-dlp.exe <url>` in Windows Terminal, or directly if `wt.exe` is absent |

Terminal detection:

| Target | Examples | Injected chord |
| --- | --- | --- |
| Modern terminal | Windows Terminal, OpenConsole, Alacritty, WezTerm, mintty, Tabby, Hyper | `Ctrl+Shift+C/X/V` |
| Legacy console | `conhost.exe`, `cmd.exe`, `powershell.exe` | `Ctrl+C/X/V` |
| GUI application | Notepad, browsers, Electron apps, Office | `Ctrl+C/X/V` |

Caveats:

- `Win+V` is normally Windows clipboard history. Plasmarchy repurposes it for
  paste. Clipboard history is not available on that chord.
- `Win+C` is normally the Windows Copilot/chat chord; Plasmarchy repurposes
  it. Copilot remains available from the taskbar.
- `Win+X` is normally the Quick Link menu; Plasmarchy repurposes it. The
  Quick Link menu remains available by right-clicking Start.
- Apps with custom copy/paste bindings may ignore the injected chord. This is
  an application limitation, not an AHK failure.
- Elevated windows may reject input injection from a non-elevated AHK process.
  Run AHK elevated or avoid mixing elevation levels.

### 6.6 Application shortcuts

| Shortcut | Target |
| --- | --- |
| `Win+Return` | Windows Terminal, or PowerShell if `wt.exe` is absent |
| `Win+Alt+Return` | WSL tmux session `Work` |
| `Win+Shift+Return` / `Win+Shift+B` | Default browser |
| `Win+Shift+Alt+B` | Private browser window |
| `Win+Shift+F` | File Explorer |
| `Win+Shift+/` | KeePassXC |
| `Win+Shift+Q` | Calculator |
| `Win+Shift+T` | `btop` in WSL |
| `Win+Shift+N` | `nvim` in WSL |
| `Win+Shift+C` | Calendar (`outlookcal:`) |
| `Win+Shift+E` | Thunderbird |
| `Win+Shift+Alt+E` | Thunderbird compose |
| `Win+Shift+A` | ChatGPT |
| `Win+Shift+Alt+A` | Grok |
| `Win+Shift+G` | Signal |
| `Win+Shift+P` | Google Photos |
| `Win+Shift+S` | Google Maps |
| `Win+Shift+Alt+G` | WhatsApp Web |
| `Win+Shift+Ctrl+G` | Google Messages |
| `Win+Shift+O` | Obsidian |
| `Win+Shift+W` | Notepad |
| `Win+Shift+X` | X |
| `Win+Shift+Alt+X` | X compose |
| `Win+Shift+Y` | YouTube |
| `Win+Shift+D` | `lazydocker` in WSL |
| `Win+Shift+Alt+M` | VLC |
| `Win+Ctrl+S` | LocalSend |
| `Win+Ctrl+C` | Snipping Tool |
| `Win+Ctrl+H` | System Information (`msinfo32.exe`) |
| `Win+Ctrl+R` | Calendar |
| `Win+Ctrl+.` (`SC034`) | HandBrake |

### 6.7 Settings and utility shortcuts

| Shortcut | Target |
| --- | --- |
| `Win+Ctrl+A` | Sound settings |
| `Win+Ctrl+B` | Bluetooth settings |
| `Win+Ctrl+N` | Network settings |
| `Win+Ctrl+D` | Display settings |
| `Win+Ctrl+P` | Battery saver |
| `Win+Ctrl+Alt+B` | Battery saver (duplicate) |
| `Win+Ctrl+Alt+C` | Snipping Tool region capture |
| `Win+Ctrl+Alt+T` | Show current time in a tray tip |
| `Win+Ctrl+Alt+W` | Weather (`wttr.in`) |
| `Win+Ctrl+Alt+R` | Calendar |
| `Win+Ctrl+Alt+E` | Clock app |
| `Win+Ctrl+Alt+D` | Clock app |
| `PrintScreen` | Snipping Tool region capture |
| `Alt+PrintScreen` | Xbox Game Bar recording (`Win+Alt+R`) |
| `Win+PrintScreen` | PowerToys Color Picker |
| `Win+Ctrl+PrintScreen` | PowerToys Text Extractor (OCR) |

### 6.8 Windows shortcuts intentionally overridden

| Native Windows shortcut | Plasmarchy behavior | How to get the native behavior |
| --- | --- | --- |
| `Win+Space` | PowerToys Run | Use Right Ctrl for layout; open Start menu for app search |
| `Win+Tab` | Next workspace | `Win+Alt+Space` or `Win+G` for Task View |
| `Win+1…9` | Focus workspace | Launch taskbar apps with the mouse or Start menu |
| `Win+C` | Copy | Open Copilot from the taskbar |
| `Win+X` | Cut | Right-click Start for the Quick Link menu |
| `Win+V` | Paste | Clipboard history is unavailable on a chord |
| `Win+Shift+S` | Google Maps | Use `PrintScreen` for screenshot region |
| `Win+PrintScreen` | PowerToys Color Picker | Use Snipping Tool full-screen mode |
| `Alt+PrintScreen` | Xbox Game Bar recording | Use Snipping Tool window mode |
| `Win+Ctrl+D` | Display settings | Create virtual desktops from Task View |
| `Ctrl+Alt+Tab` | Next monitor | Use `Alt+Tab` for the window switcher |
| `Win+G` | Task View | Xbox Game Bar remains available via its own UI |
| `Win+Ctrl+C` | Snipping Tool | Color filters can be enabled in Settings |
| `Win+K` | Keyboard settings | Cast is available from Quick Settings |
| `Win+Escape` | Power overlay | Use the Start menu power button |
| `Win+L` (with Kanata) | Next layout | Lock with `Win+Ctrl+L` |
| `Ctrl+Alt+Del` | Not interceptable | Windows secure attention sequence; use `Win+Escape` |

`Ctrl+Alt+Del` is reserved by Windows and cannot be bound by AutoHotkey. The
`Win+Escape` overlay (`SlideToShutDown.exe`) is the closest built-in power
menu. Full Task Manager access remains on `Ctrl+Shift+Esc`.

---

## 7. Focus and pointer behaviour

| Behaviour | Implementation | Result |
| --- | --- | --- |
| Hover focus | `masir` | Moving the mouse over another window focuses it |
| Hover pointer warp | None | Hovering does **not** move the pointer |
| Keyboard focus | Komorebi `mouse_follows_focus: true` | Moving focus with `Win+Arrow`, workspace switch, etc. centers the pointer in the new window |
| Focus after window open | Komorebi focus path | Pointer may center on a newly focused window; expected |
| Focus after close | Komorebi focus path | Next window becomes active and receives the pointer |

`masir` is a separate process. If Komorebi is started without `--masir`,
hover focus stops working but tiling and keyboard focus continue. The
installer passes `--masir` only when `masir.exe` is on `PATH`; otherwise it
warns and starts Komorebi without hover focus. Add the masir directory to
`PATH` or use the winget package to enable it.

Komorebi's own `focus_follows_mouse` setting is **not** used. It is an
end-of-life feature; adding it to `komorebi.json` would create a second,
conflicting focus mechanism.

---

## 8. Animations and visual settings

Komorebi animation is disabled in `komorebi.json`:

```json
"animation": { "enabled": false }
```

The installer also applies these per-user settings unless `-KeepAnimations`
is used:

| Registry path | Name | Value | Effect |
| --- | --- | --- | --- |
| `HKCU:\Control Panel\Desktop\WindowMetrics` | `MinAnimate` | `0` (string) | Disable minimize/maximize animation |
| `HKCU:\Control Panel\Desktop` | `MenuShowDelay` | `0` (string) | Remove menu delay |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `TaskbarAnimations` | `0` | Disable taskbar animations |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `SnapAssist` | `0` | Disable Snap Assist |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `EnableSnapAssistFlyout` | `0` | Disable Snap Assist flyout |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize` | `EnableTransparency` | `0` | Disable transparency/blur |

It also calls:

- `SystemParametersInfo(SPI_SETANIMATION, ..., ANIMATIONINFO{ cbSize=8, iMinAnimate=0 }, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE)`
- `SystemParametersInfo(SPI_SETMENUSHOWDELAY, 0, ...)`

Komorebi workspaces are not Windows virtual desktops, so `Win+Tab` workspace
switching does not play the Windows desktop-slide animation.

Sign out and back in for Explorer and the shell to pick up all changes.

Windows still owns some DWM effects that have no supported per-user switch:
window shadows, rounded corners, and some shell transitions. `MinAnimate=0`
removes the common minimize/maximize animation; it does not turn Windows into
a compositor-free environment.

---

## 9. Displays and hotplug

Komorebi's monitor reconciliator handles `WM_DISPLAYCHANGE` events:

- Monitor removed: windows from the removed monitor are reconciled onto the
  remaining monitor and retiled.
- Monitor added: the new monitor receives its configured workspace set and
  windows are redistributed.
- Resolution/work-area change: layouts are recalculated.

Operational notes:

- The static config declares two monitors. When the laptop is undocked,
  Komorebi reconciles the connected monitor set and moves windows from the
  missing monitor onto the panel that remains.
- Windows may reorder monitor indices after hotplug. Use
  `komorebic monitor-information` to see the current zero-based mapping.
- `Win+Ctrl+Delete` forces internal-only display mode; `Win+Ctrl+Alt+Delete`
  clones. These are manual overrides, not required for normal hotplug.
- If a window ends up on a hidden workspace after hotplug, use
  `Win+Tab` / `Win+Shift+Tab` or `komorebic focus-workspace <idx>`.

Verification:

1. Disconnect the external monitor.
2. Confirm only the laptop panel remains and the open windows retile.
3. Reconnect the external monitor.
4. Confirm the second monitor returns and windows can be moved to it with
   `Win+Ctrl+Shift+Left/Right`.
5. Run `komorebic monitor-information` and compare the indices with the
   physical arrangement.

---

## 10. Verification

### 10.1 Automated

```powershell
cd windows11
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-windows.ps1
```

Exit code `0` means all automated checks passed; `1` means at least one
failed. Warnings do not fail the script.

| Check | Pass condition |
| --- | --- |
| Windows version | Build ≥ 22000 |
| Config presence | `komorebi.json` exists and parses |
| Border | `border=true`, `border_width=2` |
| Animation | `animation.enabled=false` |
| Padding | Workspace 10, container 2 |
| Border style | `Square` |
| Komorebi schema | `komorebic check` exits 0 |
| Processes | `komorebi`, `masir`, `AutoHotkey64` running |
| PowerToys | Warns if PowerToys/PowerToys Run is not running |
| Kanata | Warns if the process or scheduled task is missing; fails if `kanata --check` fails |
| Kanata task state | Warns unless `Plasmarchy-Kanata` is `Running` |
| Startup | Both startup shortcuts exist and targets resolve |
| Registry | Animation values match; warnings only because `-KeepAnimations` is valid |
| Config home | Custom `KOMOREBI_CONFIG_HOME` is set for the process or persisted at user scope |
| Live layout | Focused workspace reports BSP (warning if Komorebi is not running) |
| Installed files | `komorebi.ahk` and `kanata.kbd` exist |

### 10.2 Manual checklist

Run these after signing out and back in. Use a real keyboard; some chords
cannot be validated by automation.

| # | Check | Expected |
| --- | --- | --- |
| 1 | `Win+Space` | PowerToys Run opens, not the Start menu |
| 2 | `Win+Return` | Windows Terminal opens |
| 3 | `Win+Alt+Return` | WSL tmux session `Work` opens/attaches |
| 4 | Open 3–4 windows, `Win+Arrow` | Focus moves; pointer centers in the new window |
| 5 | `Win+Shift+Arrow` | Window swaps/moves in the layout |
| 6 | `Win+1…9` | Workspace focus changes |
| 7 | `Win+Shift+1…9` | Window moves to workspace and view follows |
| 8 | `Win+Shift+Alt+1…9` | Window moves without changing the view |
| 9 | `Win+L` | Layout cycles (Kanata must be running) |
| 10 | `Win+Alt+L` | Layout cycles back |
| 11 | `Win+T` | Window floats/unfloats |
| 12 | `Win+J` | Layout flips horizontally |
| 13 | Hover another window | Focus changes immediately; pointer does not warp |
| 14 | `Win+C` / `Win+X` / `Win+V` in Notepad | Copy/cut/paste work |
| 15 | Same chords in Windows Terminal | Copy/cut/paste use Ctrl+Shift chords |
| 16 | Same chords in `cmd.exe` | Copy/paste use Ctrl chords |
| 17 | `Alt+Shift+L` in a browser | URL is copied |
| 18 | `PrintScreen` | Snipping Tool region capture |
| 19 | `Win+PrintScreen` | PowerToys Color Picker |
| 20 | `Win+Ctrl+PrintScreen` | PowerToys Text Extractor |
| 21 | Right Ctrl tap | Keyboard layout switches |
| 22 | Right Ctrl hold | Acts as Ctrl |
| 23 | `Win+L` with `-Kanata none` | Locks the screen |
| 24 | `Win+Ctrl+L` with Kanata running | Locks the screen |
| 25 | Active border | 2 px square, teal, no titlebar |
| 26 | Inactive border | `#595959` |
| 27 | Browsers / Steam / Telegram / Lutris / LocalSend / Scan | Tiled, bordered, no titlebar |
| 28 | Disconnect/reconnect external monitor | Retiles to remaining panel and back |
| 29 | Animations | Workspace/window changes are instant |
| 30 | Sign out/in | Startup shortcuts and Kanata task start automatically |

### 10.3 Useful commands

```powershell
# Config validation
komorebic check -k "$env:USERPROFILE\komorebi.json"

# Live state
komorebic monitor-information
komorebic query focused-workspace-layout
komorebic query focused-workspace-index
komorebic query focused-window-index

# Process check
Get-Process komorebi, masir, AutoHotkey64, kanata_windows_gui_winIOv2_x64 -ErrorAction SilentlyContinue

# Scheduled task
Get-ScheduledTask -TaskName Plasmarchy-Kanata
Get-ScheduledTaskInfo -TaskName Plasmarchy-Kanata

# Startup entries
explorer "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
```

---

## 11. Rollback

### 11.1 Default uninstall

```powershell
cd windows11
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall-windows.ps1
```

Default behavior:

- Stops `komorebi`, `masir`, the Plasmarchy AHK script, and Kanata.
- Removes `Plasmarchy Komorebi.lnk`, `Plasmarchy Hotkeys.lnk`, and
  `Plasmarchy-Kanata`.
- Restores animation/transparency/snap registry values from the first-run
  snapshot.
- Leaves `komorebi.json`, `komorebi.ahk`, and `kanata.kbd` in place.
- Leaves a custom `KOMOREBI_CONFIG_HOME` user environment variable in place;
  it may be user-owned. Clear it manually if you want the default path back:

```powershell
[Environment]::SetEnvironmentVariable('KOMOREBI_CONFIG_HOME', $null, 'User')
```

### 11.2 Uninstall options

| Flag | Effect |
| --- | --- |
| `-RestoreBackup` | Restore the first-run `komorebi.json` / `komorebi.ahk` / `kanata.kbd`; remove files that did not exist before Plasmarchy |
| `-RemoveConfig` | Delete the three config files from the config home |
| `-RemovePackages` | Winget-uninstall Komorebi, masir, AutoHotkey, PowerToys, and Kanata |
| `-KeepSettings` | Do not restore animation/transparency registry values |
| `-RemoveState` | Delete `%LOCALAPPDATA%\Plasmarchy` after uninstall |

Examples:

```powershell
# Full rollback: restore the files that existed before Plasmarchy
.\uninstall-windows.ps1 -RestoreBackup

# Remove Plasmarchy's config files instead of restoring anything
.\uninstall-windows.ps1 -RemoveConfig

# Remove packages too, while restoring the pre-install config
.\uninstall-windows.ps1 -RestoreBackup -RemovePackages

# Stop Plasmarchy but keep its configuration and settings
.\uninstall-windows.ps1 -KeepSettings
```

`-RestoreBackup` and `-RemoveConfig` should not be combined: the uninstall
script restores first and then removes, leaving no configuration behind.

### 11.3 Manual recovery

Timestamped backups are at:

```text
%USERPROFILE%\plasmarchy-backup-<yyyyMMdd-HHmmss>\
```

They contain the pre-change `komorebi.json`, `komorebi.ahk`, `kanata.kbd`,
any startup shortcuts, and — when animations were changed — `settings.json`.
Copy files back manually if the uninstall script cannot run.

If Explorer still looks animated after uninstall, sign out and back in, or
re-apply the values from the first-run `settings.json`.

---

## 12. Troubleshooting

| Symptom | Check | Fix |
| --- | --- | --- |
| No tiling | `Get-Process komorebi`; `komorebic check -k ...` | Start `komorebic start -c ... --masir`; fix config errors |
| Hover does not focus | `Get-Process masir`; startup shortcut arguments | Start Komorebi with `--masir`; ensure `masir.exe` is on `PATH` |
| Pointer does not follow keyboard focus | `mouse_follows_focus` in config | Set `true`; restart Komorebi |
| `Win+Space` opens Start | PowerToys Run not running or `Alt+Space` changed | Start PowerToys; set PowerToys Run activation to `Alt+Space` |
| `Win+C/X/V` sends wrong chord | Active process name; terminal detection | Check `IsWindowsTerminal`; add the terminal executable if needed |
| `Win+C/X/V` does nothing | AHK not running; target elevated | Start AHK; run AHK elevated for elevated targets |
| Right Ctrl does not switch layout | Kanata process/task; input-language hotkeys | Start Kanata; set Windows language hotkeys to Not Assigned |
| `Win+L` locks instead of cycling | Kanata not running | Start `Plasmarchy-Kanata`; use `Win+Ctrl+L` to lock |
| `Win+L` cycles when you wanted lock | Kanata is running | Use `Win+Ctrl+L` |
| `Win+Alt+L` does not work | AHK running; another app may capture the chord | Confirm AHK is running and `#!l` is not captured by another app |
| Browsers appear above all windows | Browser elevated; not in `manage_rules`; border overflow | Add executable to `manage_rules` + `border_overflow_applications`; avoid elevation |
| Titlebar missing on an app that needs it | Global `remove_titlebar_applications` regex | Replace `.*` with an explicit app list, or float the window |
| Border gap/overflow on an app | App in `border_overflow_applications`? | Add executable to that list and `manage_rules` |
| Monitor hotplug does not retile | `komorebic monitor-information`; Komorebi running | Restart Komorebi; verify Windows display arrangement |
| Kanata task fails | Task history; run the exe manually | Re-run installer elevated; check antivirus/EDR |
| AHK reports a syntax error | AHK version | Install AutoHotkey v2, not v1 |
| Installer fails at winget | `winget --version`; App Installer | Install App Installer; use `-SkipPackages` with manual binaries |
| Installer cannot find `komorebic.exe` | Portable path | Extract the whole archive to `%LOCALAPPDATA%\Programs\komorebi`, or add its directory to `PATH` |
| Animations remain | Registry values; sign-out state | Run installer without `-KeepAnimations`; sign out/in |
| Config path differs in autostart | `KOMOREBI_CONFIG_HOME` user value | Re-run installer; it persists the value |
| Uninstall restored wrong files | First-run vs timestamped backup | Use `-RestoreBackup` with `%LOCALAPPDATA%\Plasmarchy\original`; timestamped backups are manual |

Logs and diagnostics:

```powershell
# Komorebi writes daily logs under %TEMP%
Get-ChildItem $env:TEMP -Filter 'komorebi*.log*' |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 3 FullName, LastWriteTime

# Scheduled task history
Get-ScheduledTaskInfo -TaskName Plasmarchy-Kanata

# AHK process and command line
Get-CimInstance Win32_Process -Filter "Name = 'AutoHotkey64.exe'" |
  Select-Object ProcessId, CommandLine

# Installed package list
winget list --id LGUG2Z.komorebi
winget list --id LGUG2Z.masir
winget list --id jtroo.kanata_gui
```

---

## 13. Known limitations and deviations

| Limitation | Impact | Mitigation |
| --- | --- | --- |
| Active border is solid teal, not cyan→green gradient | Visual difference from Plasma | Accepted; a custom overlay would be required |
| Inter-window gap ≈ 4 px, not 5 px | 1 px visual difference | Accepted; Komorebi padding is symmetric |
| DWM shadows remain | Slight visual difference | No supported global per-window switch |
| DWM rounded corners may remain | Visual difference | No supported global switch; `border_style: Square` only affects Komorebi's frame |
| `Win+F` is monocle, not true fullscreen | Fullscreen semantics differ | Use `Win+Alt+F`/`Win+Ctrl+F` to maximize; use app fullscreen (F11) when needed |
| `Win+L` requires Kanata | Without Kanata, layout cycling via `Win+L` is unavailable | Install Kanata, or use `Win+Alt+L` / `Win+L` native lock |
| Kanata requires administrator rights | Task must be elevated; some games/anti-cheat may block hooks | Use a dedicated keyboard if needed; disable Kanata for competitive games |
| AHK may not reach elevated windows | Clipboard and app shortcuts can fail in admin apps | Run AHK elevated or avoid mixing integrity levels |
| No native per-application Alt+Tab | `Win+Alt+Tab` sends `Alt+\`` | Windows has no equivalent per-app switcher |
| Win-key chords override Windows defaults | `Win+V`, `Win+Tab`, `Win+1…9`, `Win+Shift+S`, `Win+Ctrl+D`, `Win+G`, `Win+Space` change behavior | See §6.8; use documented alternatives |
| `Ctrl+Alt+Del` cannot be bound | No direct power-menu replacement | `Win+Escape` overlay; `Ctrl+Shift+Esc` Task Manager |
| Global titlebar removal | Apps that need a titlebar lose it | Float with `Win+T`; replace `.*` with an explicit list |
| Fixed border-overflow list | Unlisted custom-chrome apps may show a seam | Add the executable to `border_overflow_applications` and `manage_rules` |
| No automatic optional-app installation | App shortcuts may show a tray tip | Install browsers/Telegram/Steam/etc. separately |
| No `applications.json` shipped | Some app-specific Komorebi rules are missing | Optional `komorebic fetch-asc` |
| Russian-layout symbol shortcuts are not mapped | Symbol-based Omarchy chords may not fire on a Russian layout | Deferred; physical/scan-code bindings used where possible |
| Static validation only | AHK/PowerShell/Kanata behavior has not run on real Windows yet | Run `install-windows.ps1`, `verify-windows.ps1`, and §10.2 on hardware |
| Komorebi/Kanata versions pinned | Future releases may change CLI/config schema | Re-validate with `komorebic check` and `kanata --check` before upgrading |

---

## 14. Agent acceptance criteria

Before declaring the Windows layer complete on a real machine:

| Area | Acceptance |
| --- | --- |
| Files | `komorebi.json`, `komorebi.ahk`, `kanata.kbd` copied to the config home |
| Komorebi schema | `komorebic check -k <config>` exits 0 |
| AHK | Script loads under AutoHotkey v2 with no syntax error |
| Kanata | `kanata --check --cfg <config>` reports `config file is valid` |
| PowerShell | All three scripts parse under PowerShell 5.1/7 |
| Autostart | Both startup shortcuts exist and targets resolve |
| Kanata task | `Plasmarchy-Kanata` exists, is elevated, and is running |
| Focus | Hover focuses without pointer warp; keyboard focus centers pointer |
| Clipboard | Notepad, Windows Terminal, and legacy console all copy/paste correctly |
| Layout | `Win+L` cycles; `Win+Alt+L` cycles back; `Win+J` flips |
| Workspaces | `Win+1…9`, `Win+Shift+1…9`, `Win+Shift+Alt+1…9` behave as specified |
| Border | 2 px square teal active; `#595959` inactive; no titlebar |
| Apps | Browsers, Steam, Telegram, Lutris, LocalSend, Scan tile without overflow |
| Displays | Unplug/replug retiles and preserves usable workspaces |
| Animations | No workspace/window animation; registry values applied |
| Backup | Re-install does not overwrite the first-run original snapshot |
| Rollback | `uninstall-windows.ps1 -RestoreBackup` restores the first-run files; `-RemoveConfig` removes them |

---

## 15. File inventory

| File | Purpose | Validation performed |
| --- | --- | --- |
| `komorebi.json` | Komorebi static config | JSON parse + v0.1.41 JSON Schema |
| `komorebi.ahk` | AutoHotkey v2 shortcut/clipboard layer | Parsed under AutoHotkey v2 in Wine |
| `kanata.kbd` | Kanata remaps | `kanata --check` v1.12.0 |
| `install-windows.ps1` | Installer | PowerShell parser; PSScriptAnalyzer (warnings only); C# block compile check |
| `uninstall-windows.ps1` | Rollback | PowerShell parser; PSScriptAnalyzer (warnings only) |
| `verify-windows.ps1` | Automated checks + manual checklist | PowerShell parser; PSScriptAnalyzer (warnings only) |
| `SPEC.md` | This document | Manual review |

No Windows file is referenced by the Linux `deploy.sh` or `install.sh`.

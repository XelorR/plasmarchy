# Plasmarchy

Omarchy-like tiling, shortcuts, borders and focus behaviour for non-Omarchy
machines: KDE Plasma 6 on Arch/CachyOS and Windows 11.

Reference look and feel: [Omarchy hotkeys](https://omarchy.org/manual/hotkeys/).

Plasmarchy does not install Omarchy itself.  It reproduces the ergonomic
parts that matter on your existing desktop: a Hyprland-style `dwindle`-like
tiling layout, practical keyboard shortcuts, server-side window borders, low
visual friction and predictable focus behaviour.

## Quick start

Linux (Arch or CachyOS):

```bash
git clone https://github.com/XeloR/plasmarchy.git
cd plasmarchy
./install.sh --yes
```

Afterwards log out and log in once.  That applies the input group, the Aurorae
theme, the focus logger and the deferred Krohnkite shortcuts.

Windows 11:

```powershell
cd windows11
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-windows.ps1
```

## Requirements

- Arch Linux or CachyOS.
- KDE Plasma 6 on Wayland.
- `sudo`.
- A working Plasma session for `deploy.sh`.

The Windows edition is a separate implementation.  It uses Komorebi,
AutoHotkey v2 and Kanata instead of KWin/Krohnkite.  See
`windows11/SPEC.md` for the full specification.

## What Plasmarchy changes

By default the deployer does **not** install unrelated applications.  It
configures:

- KDE Plasma tiling through a vendored Krohnkite 0.9.10.0 build.
- Hyprland-like daily-driver shortcuts for navigation, resize, layout and
  workspace movement.
- Server-side decoration with a 2 px border, an active cyan to green
  gradient and an inactive grey border.
- No title bars, small gaps and disabled animations.
- Focus follows mouse immediately plus keyboard-driven pointer warp.
- Clipboard shortcuts that behave logically in both GUI applications and
  Konsole.
- A Plasmarchy Konsole profile with a hidden scrollbar.
- Meta+K opens a categorized keyboard-shortcut reference.
- Right Ctrl as the only keyboard-layout switch.
- A portable Plasma/KWin configuration snapshot.

Optional software installation is available with explicit flags, so a
clean base system can remain small.

## Deployer flags

`deploy.sh` is the user-side installer.  `install.sh` runs it as part of a
full one-command installation.

Linux:

```bash
./deploy.sh [--yes] [--check] [--dry-run]
./deploy.sh --install-software
./deploy.sh --with-dictation [--dictation-languages ru,en]
./deploy.sh --restore-backup latest
```

Common flags:

| Flag                      | Effect                                                     |
| ------------------------- | ---------------------------------------------------------- |
| `--yes`                   | Do not ask for confirmation.                               |
| `--check`                 | Preflight only.                                            |
| `--dry-run`               | Print actions without changing anything.                   |
| `--no-backup`             | Skip the pre-deploy snapshot.                              |
| `--reset-plasma`         | Remove core Plasma configs so KDE regenerates defaults.    |
| `--install-software`      | Install the distro/AUR/third-party applications too.       |
| `--with-dictation`        | Install and configure Voxtype.                              |
| `--dictation-languages`   | Language list; auto-detected from the KDE keymap otherwise.|
| `--restore-backup SNAP`   | Restore a Plasma/KWin snapshot and exit.                    |
| `--skip-packages`         | Skip distribution package installation.                    |
| `--skip-krohnkite`        | Do not install or configure Krohnkite.                     |
| `--skip-theme`            | Do not install or activate the border theme.               |
| `--skip-focus`            | Do not change focus behaviour.                             |
| `--skip-shortcuts`        | Do not change shortcuts.                                   |
| `--krohnkite-version`  | Download a specific Krohnkite tag; default is latest.       |
| `--krohnkite-bundled`  | Use the copy shipped in `vendor/` instead of downloading.    |
| `--skip-tmux`             | Do not install the tmux configuration.                     |
| `--skip-konsole`          | Do not install the Plasmarchy Konsole profile.             |

Dictation:

```bash
./deploy.sh --with-dictation
./deploy.sh --with-dictation --dictation-languages en,ru
```

The installer detects the installed KDE keyboard layouts automatically.  The
dictation language list can be forced with `--dictation-languages`.

## Applications and shortcuts

The shortcuts are applied from `manifests/shortcuts.tsv` and
`manifests/commands.tsv`.  Examples and supporting scripts are in `bin/`.

Check the shortcut map:

```bash
python3 lib/shortcuts.py lint manifests/shortcuts.tsv
python3 lib/shortcuts.py check manifests/shortcuts.tsv --conflicts --allow-missing
```

Generate command wrappers manually:

```bash
python3 lib/shortcuts.py gen-desktops \
  manifests/commands.tsv manifests/shortcuts.tsv \
  ~/.local/share/applications ~/.local/share/plasmarchy/bin
```

## Backups and rollback

A normal deployment creates a snapshot first.  Manual snapshots and restores
are available:

```bash
./create-backup.sh --tag before-experiment
./restore-plasma.sh latest --reload
```

Restore a specific snapshot:

```bash
./restore-plasma.sh plasma-2026-... --reload
```

`restore-plasma.sh` also creates a safety snapshot of the state it replaces.

## Diagnostics

- Krohnkite did not apply live: `~/.cache/plasmarchy/apply-krohnkite.log`.
- Theme did not apply: check `/usr/lib/plasma-apply-aurorae --list-themes` and
  `kwriteconfig6` theme keys.
- No tiling: verify `kreadconfig6 --file kwinrc --group Plugins --key krohnkiteEnabled`
  and `kreadconfig6 --file kwinrc --group Script-krohnkite --key screenDefaultLayout`.
- Focus logger: check `journalctl --user -n 200 _COMM=kwin_wayland`.
- Animations remain: verify `AnimationDurationFactor=0`,
  `[Windows] ElectricBorderTiling=false` and the loaded Plasma effects.
- Dictation: check `systemctl --user status ydotool voxtype` and `/dev/uinput`.

## Repository layout

| Path               | Purpose                                           |
| ------------------ | ------------------------------------------------- |
| `deploy.sh`        | Main user-side installer.                         |
| `install.sh`       | One-command guided installer.                     |
| `install.ps1`      | Windows PowerShell entry point.                  |
| `root-setup.sh`    | Root-side packages, LocalSend, AUR, `/dev/uinput`. |
| `create-backup.sh` | Plasma/KWin snapshot.                             |
| `restore-plasma.sh`| Restore a snapshot.                                |
| `lib/shortcuts.py` | KGlobalAccel map tooling.                         |
| `manifests/`       | Shortcut map, command map and package lists.       |
| `scripts/`         | Backup, restore, deployment, root and optional installers. |
| `bin/`             | Command wrappers and helpers.                     |
| `config/plasma/`   | Portable Plasma/KWin configuration snapshot.      |
| `theme/plasmarchy/`| Aurorae border theme.                             |
| `windows11/`       | Windows 11 implementation and specification.      |
| `vendor/`          | Optional offline fallback Krohnkite and its checksum. |

Backups are deliberately ignored by Git because they contain personal system
state.  Do not commit them to a public repository.

## Notes for contributors

- Keep every user-visible file in English.
- Treat `manifests/*.tsv` as the source of truth for shortcuts.
- Do not store personal machine identifiers, snapshots or backups.
- Prefer small, testable changes.  Use `bash -n`, `deploy.sh --check`,
  `python3 lib/shortcuts.py lint/check` and the Windows PowerShell parse
  checks when editing deployment code.

## Windows 11 (Komorebi)

The `windows11/` directory is a separate implementation.  It does not
participate in the Linux deployment and does not modify `deploy.sh` or
`install.sh`:

- Komorebi v0.1.41, layout `BSP`, 2 px borders, nine desktops per monitor.
- masir for focus follows mouse.
- AutoHotkey v2 for shortcuts and terminal-aware copy/paste.
- Kanata v1.12.0 for Right Ctrl layout switching and `Win+L` cycling.
- winget is tried first, then scoop, then direct downloads.  The user is
  asked for missing binaries if no automated installer is available.

Install from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

or directly:

```powershell
cd windows11
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-windows.ps1
```

Verify and rollback:

```powershell
.\verify-windows.ps1
.\uninstall-windows.ps1 -RestoreBackup
```

The complete specification is in
[`windows11/SPEC.md`](windows11/SPEC.md) (English).


## License

Plasmarchy is released under the GNU General Public License v3.0. See [LICENSE](LICENSE).

# Plasmarchy

Omarchy-like tiling, shortcuts, borders and focus behaviour for non-Omarchy
machines: KDE Plasma 6 on Arch/CachyOS and Windows 11.

Reference look and feel: [Omarchy hotkeys](https://omarchy.org/manual/hotkeys/).

Plasmarchy does not install Omarchy itself.  It reproduces the ergonomic
parts that matter on your existing desktop: a Hyprland-style Dwindle tiling
layout, practical keyboard shortcuts, server-side window borders, low visual
friction and predictable focus behaviour.

## Quick start

Linux (Arch or CachyOS):

```bash
git clone https://github.com/XeloR/plasmarchy.git
cd plasmarchy
./install.sh --yes
```

The guided installer creates a safety snapshot, installs the required
packages, copies the Plasma/KWin configuration snapshot and runs the
user-side deployer.  Log out and log in once afterwards to apply the input
group, the Aurorae theme, the focus logger and any shortcuts that could not
be registered in the current session.

If no Plasma session is available during the install, finish later with:

```bash
./install.sh deploy --yes
```

Windows 11:

```powershell
cd windows11
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-windows.ps1
```

or, from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

## Requirements

- Arch Linux or CachyOS.
- KDE Plasma 6 on Wayland.
- `sudo`.
- A working Plasma session for `./install.sh deploy`.

The Windows edition is a separate implementation.  It uses Komorebi,
AutoHotkey v2 and Kanata instead of KWin/Krohnkite.  See
`windows11/SPEC.md` for the full specification.

## What Plasmarchy changes

By default the deployer does **not** install unrelated applications.  The
Linux installation configures:

- Krohnkite tiling from the Plasmarchy fork
  ([XelorR/Krohnkite](https://github.com/XelorR/Krohnkite)).  The pinned fork
  build is downloaded from GitHub on demand and cached locally;
  `--krohnkite-version TAG` selects another fork tag or branch and
  `--krohnkite-bundled` uses the vendored 0.9.11.3 fallback.
- Layout order Dwindle -> Columns -> Floating.  Dwindle inserts a new window
  into the focused tile and keeps unrelated branches and split ratios intact.
- Directional focus stays inside the current virtual desktop.  At an edge
  `Meta+Left`/`Meta+Right` stops instead of wrapping or switching desktops.
- Hyprland-like daily-driver shortcuts for navigation, resize, layout and
  workspace movement.
- Server-side decoration with a 2 px border, an active cyan to green
  gradient and an inactive grey border.
- No title bars, small gaps and disabled animations.
- Focus follows mouse immediately plus keyboard-driven pointer warp.
- Clipboard shortcuts that behave logically in both GUI applications and
  Konsole.
- A Plasmarchy Konsole profile with a hidden scrollbar, selected as the
  default profile for new windows.
- Meta+K toggles a categorized keyboard-shortcut reference.
- Right Ctrl as the only keyboard-layout switch.
- A panel layout from the portable snapshot.  The existing dock launcher
  list is preserved, and an existing panel file is backed up as
  `plasma-org.kde.plasma.desktop-appletsrc.plasmarchy-user-backup`.
  Desktop files are left untouched.
- A portable Plasma/KWin configuration snapshot.

Optional software installation is available with explicit flags, so a
clean base system can remain small.

## Installation commands

`install.sh` is the public Linux entry point.  Internal helpers live under
`scripts/`.

| Command                    | Purpose                                             |
| -------------------------- | --------------------------------------------------- |
| `./install.sh`             | Full guided installation (default command).          |
| `./install.sh deploy`      | Run the in-session deployer (`scripts/deploy.sh`).   |
| `./install.sh backup`      | Create a Plasma/KWin snapshot.                       |
| `./install.sh restore`     | Restore a snapshot.                                  |

Examples:

```bash
./install.sh --yes
./install.sh deploy --check
./install.sh backup --tag before-experiment
./install.sh restore --list
./install.sh restore latest --reload
```

## Installation options

| Flag                       | Effect                                                    |
| -------------------------- | --------------------------------------------------------- |
| `--yes`, `-y`              | Do not ask for confirmation.                               |
| `--dry-run`                | Print actions without changing anything.                   |
| `--packages MODE`          | `required`, `all`, or `none`.                              |
| `--skip-software`          | Alias for `--packages none`.                               |
| `--with-dictation`         | Install and configure Voxtype.                             |
| `--dictation-languages L`  | Comma-separated languages; auto-detected otherwise.        |
| `--restore-backup SNAP`    | Restore a snapshot instead of deploying.                   |
| `--skip-root`              | Do not run `scripts/root-setup.sh`.                        |
| `--skip-config`            | Do not copy `config/plasma/` into `~/.config`.             |
| `--skip-deploy`            | Do not run the in-session deployer.                        |
| `--no-backup`              | Do not create a pre-install snapshot.                      |
| `--overwrite-panel-layout` | Replace the panel layout instead of preserving dock apps.  |
| `--reset-plasma`           | Remove core Plasma configs; KDE regenerates them on login. |

`--reset-plasma` creates a safety backup first and exits without deploying.
Log out and log in again before running the installer anew.

## Deployer options

`./install.sh deploy` (or `scripts/deploy.sh` directly) applies the live
KWin, shortcut, theme, tmux and Konsole configuration in the current Plasma
session.

| Flag                       | Effect                                                    |
| -------------------------- | --------------------------------------------------------- |
| `--yes`                    | Do not ask for confirmation.                               |
| `--check`                  | Run preflight checks and exit.                             |
| `--dry-run`                | Print actions without changing anything.                   |
| `--packages MODE`          | `required`, `all`, or `none`.                              |
| `--skip-packages`          | Alias for `--packages none`.                               |
| `--no-backup`              | Skip the pre-deploy snapshot.                              |
| `--skip-krohnkite`         | Do not install or configure Krohnkite.                     |
| `--krohnkite-version REF`  | Fork tag or branch; default is pinned `0.9.11.3`. `latest` means the fork's `master`. |
| `--krohnkite-bundled`      | Use the vendored fork build instead of downloading.        |
| `--skip-theme`             | Do not install or activate the border theme.               |
| `--skip-focus`             | Do not change focus behaviour.                             |
| `--skip-shortcuts`         | Do not change shortcuts.                                   |
| `--skip-tmux`              | Do not install the tmux configuration.                     |
| `--skip-konsole`           | Do not install the Plasmarchy Konsole profile.             |
| `--install-software`       | Install the distro/AUR/third-party applications too.       |
| `--with-dictation`         | Install and configure Voxtype.                             |
| `--dictation-languages L`  | Comma-separated languages; auto-detected otherwise.        |
| `--restore-backup SNAP`    | Restore a snapshot and exit.                               |
| `--force`                  | Continue even if the session checks are unusual.           |

Dictation:

```bash
./install.sh --with-dictation
./install.sh --with-dictation --dictation-languages en,ru
./install.sh deploy --with-dictation --skip-packages
```

The installer detects the installed KDE keyboard layouts automatically.  The
dictation language list can be forced with `--dictation-languages`.

`F9` is push-to-talk: hold it while speaking and release it to transcribe.
`Alt+Space` toggles dictation on and off; `Meta+Ctrl+X` remains an alias.
Dictation uses the multilingual Parakeet v3 (`parakeet-tdt-0.6b-v3-int8`)
model: on an AVX2-only machine it is fast enough and avoids the Whisper
memory footprint.
Voxtype reads `F9` directly through `/dev/input`, so the input group must be
active for that key to work.  Parakeet needs the ONNX backend: run
`sudo voxtype setup onnx --enable` once after installation, then restart
`voxtype.service`.

## Applications and shortcuts

The shortcuts are applied from `manifests/shortcuts.tsv` and
`manifests/commands.tsv`.  Examples and supporting scripts are in `bin/`.

Web-app shortcuts such as ChatGPT, Grok, Google Photos, Google Maps, WhatsApp,
Google Messages, X and YouTube open a Chromium app window when Chromium (or
another Chromium-family browser) is installed.  Without one they fall back to
a new window in the default browser, never to a tab in the last window.

`Meta+K` toggles a categorized HTML cheat sheet.  The second press closes the
open viewer.  The runtime copy is installed to
`~/.local/share/plasmarchy/docs/plasmarchy-shortcuts.html`.

The remaining Omarchy gaps and the implemented Dwindle layout are tracked in
[`docs/parity-roadmap.md`](docs/parity-roadmap.md).

Check the shortcut map:

```bash
python3 lib/shortcuts.py lint manifests/shortcuts.tsv
python3 lib/shortcuts.py check manifests/shortcuts.tsv --conflicts --allow-missing
```

Regenerate the shortcut reference after changing the manifest:

```bash
python3 scripts/generate-shortcuts-html.py
python3 scripts/generate-shortcuts-text.py
python3 scripts/generate-shortcuts-pdf.py
```

Generate command wrappers manually:

```bash
python3 lib/shortcuts.py gen-desktops \
  manifests/commands.tsv manifests/shortcuts.tsv \
  ~/.local/share/applications ~/.local/share/plasmarchy/bin
```

## Backups and rollback

A normal deployment creates a snapshot first.  Manual snapshots and restores
are available through the main entry point:

```bash
./install.sh backup --tag before-experiment
./install.sh restore --list
./install.sh restore latest --reload
```

Restore a specific snapshot:

```bash
./install.sh restore plasma-2026-... --reload
```

`restore` also creates a safety snapshot of the state it replaces.  The
underlying helpers are `scripts/create-backup.sh` and
`scripts/restore-plasma.sh`.

## Diagnostics

- Krohnkite did not apply live: `~/.cache/plasmarchy/apply-krohnkite.log`.
- Theme did not apply: check `/usr/lib/plasma-apply-aurorae --list-themes` and
  `kwriteconfig6` theme keys.
- No tiling: verify `kreadconfig6 --file kwinrc --group Plugins --key krohnkiteEnabled`
  and `kreadconfig6 --file kwinrc --group Script-krohnkite --key screenDefaultLayout`
  (it should print `:DwindleLayout`).
- Wrong layout cycle: check `dwindleLayoutEnabled`, `columnsLayoutEnabled` and
  `floatingLayoutEnabled` are `true` and every other `*LayoutEnabled` key in
  `[Script-krohnkite]` is `false`.
- Focus keys switch desktops: all four of `focusMoveScreensNormal`,
  `focusMoveVDesktopsNormal`, `focusMoveScreensMeta` and
  `focusMoveVDesktopsMeta` must be `false`.
- Focus logger: check `journalctl --user -n 200 _COMM=kwin_wayland`.
- Animations remain: verify `AnimationDurationFactor=0`,
  `[Windows] ElectricBorderTiling=false` and the loaded Plasma effects.
- Konsole default profile: `kreadconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile`
  should print `Plasmarchy.profile`.  The profile itself should contain
  `[Scrolling]` with `ScrollBarPosition=2`.
- Meta+K does nothing: verify that `kdialog` is installed and that
  `~/.local/share/plasmarchy/docs/plasmarchy-shortcuts.html` exists.
- Dictation: check `systemctl --user status ydotool voxtype`, `/dev/uinput`
  and that the current user is in the `input` group (needed for the F9
  push-to-talk listener).

## Repository layout

| Path                       | Purpose                                                |
| -------------------------- | ------------------------------------------------------ |
| `install.sh`               | Linux entry point (install, deploy, backup, restore).   |
| `install.ps1`              | Windows PowerShell entry point.                        |
| `scripts/deploy.sh`        | User-side, in-session deployer.                        |
| `scripts/root-setup.sh`    | Root packages, LocalSend, AUR and `/dev/uinput`.       |
| `scripts/create-backup.sh` | Plasma/KWin snapshot.                                  |
| `scripts/restore-plasma.sh` | Restore a snapshot.                                    |
| `scripts/install-*.sh`     | Theme, tmux, Konsole and dictation helpers.            |
| `bin/`                     | Runtime command wrappers and helpers.                  |
| `lib/shortcuts.py`         | KGlobalAccel map tooling.                              |
| `manifests/`               | Shortcut map, command map and package lists.           |
| `config/plasma/`           | Portable Plasma/KWin configuration snapshot.           |
| `config/konsole/`          | Plasmarchy Konsole profile and `konsolerc`.            |
| `docs/`                    | Generated shortcut reference (HTML, text and PDF).     |
| `theme/plasmarchy/`        | Aurorae border theme.                                  |
| `windows11/`               | Windows 11 implementation and specification.           |
| `vendor/`                  | Offline fallback Krohnkite fork build and its checksum. |

Backups are deliberately ignored by Git because they contain personal system
state.  Do not commit them to a public repository.

## Notes for contributors

- Keep every user-visible file in English.
- Treat `manifests/*.tsv` as the source of truth for shortcuts.
- Regenerate `docs/plasmarchy-shortcuts.*` after changing the manifest.
- Do not store personal machine identifiers, snapshots or backups.
- Prefer small, testable changes.  Use `bash -n`, `./install.sh deploy --check`,
  `python3 lib/shortcuts.py lint/check` and the Windows PowerShell parse
  checks when editing deployment code.

## Windows 11 (Komorebi)

The `windows11/` directory is a separate implementation.  It does not
participate in the Linux deployment and does not modify `install.sh` or
`scripts/deploy.sh`:

- Komorebi v0.1.41, layout `BSP`, 2 px borders, nine desktops per monitor.
- masir for focus follows mouse.
- AutoHotkey v2 for shortcuts and terminal-aware copy/paste.
- Kanata v1.12.0 for Right Ctrl layout switching and `Win+L` cycling.
- Missing components are resolved in this order: winget, scoop, direct
  download, then manual placement.  The user is asked for anything that
  remains unavailable.

Install from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

or directly:

```powershell
cd windows11
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-windows.ps1
```

Verify and roll back from `windows11/`:

```powershell
.\verify-windows.ps1
.\uninstall-windows.ps1 -RestoreBackup
```

The complete specification is in
[`windows11/SPEC.md`](windows11/SPEC.md) (English).

## License

Plasmarchy is released under the GNU General Public License v3.0. See [LICENSE](LICENSE).

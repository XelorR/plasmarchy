# Plasma config snapshot

This directory is the portable part of the live CachyOS / Plasma 6.8.1
configuration. `install.sh` copies these files into `~/.config/` before it
runs `deploy.sh`.

Included:

| File | What it preserves |
| --- | --- |
| `kdeglobals` | colour scheme, Breeze Twilight look-and-feel, fonts, animation factor |
| `kwinrc` | virtual desktops, focus policy, effects, Krohnkite, decoration, electric-border switches |
| `kglobalshortcutsrc` | the full KGlobalAccel map, including shortcuts not listed in `manifests/shortcuts.tsv` |
| `kxkbrc` | `us,ru` layouts, `grp:rctrl_toggle`, `lv3:ralt_switch` |
| `plasma-localerc` | `en_US.UTF-8` formats/language |
| `plasmarc` | wallpaper list placeholder |
| `powerdevilrc` | AC performance profile, no auto-suspend, lid action |
| `powermanagementprofilesrc` | Plasma 6 migration marker |
| `kcminputrc` | touchpad natural scrolling |
| `krunnerrc` | free-floating KRunner |
| `ksplashrc` | splash disabled (`Engine=none`) |
| `plasma-org.kde.plasma.desktop-appletsrc` | sanitize panel/dock layout; launcher contents removed and screen mappings cleared |

`kwinrc` deliberately has no `[Tiling]` groups: those are keyed by the UUIDs
of this machine's outputs and are meaningless on different hardware. Krohnkite
creates the correct per-output groups on first use.

`deploy.sh` still rewrites the important generated settings after the copy:
the Krohnkite layout cycle (Dwindle -> Columns -> Floating), disabled layouts,
gaps, focus isolation, focus policy, `BorderSizeAuto=false`, window rules,
animation switches, the decoration theme, and the shortcut map. The snapshot
is there to keep everything else (power, languages, input, extra hotkeys,
desktop names, a neutralized panel/dock layout) without copying machine-specific
display topology, desktop files, activity IDs, or launcher contents.

To skip the snapshot, run `./install.sh --skip-config`. A pre-install backup
is created by `create-backup.sh --tag pre-install` unless `--no-backup` is
passed.

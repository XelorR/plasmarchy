# Omarchy parity roadmap

Reference: [Omarchy hotkeys](https://omarchy.org/manual/hotkeys/) and the
default Omarchy Hyprland bindings.  This page tracks what Plasmarchy already
matches, what is deliberately different, and what is still worth building.

The applied shortcut map is always `manifests/shortcuts.tsv`.  `Meta+K` shows
the generated, categorized version of that map; this page only discusses the
gaps.

## Current state

Plasmarchy now covers the daily-driver shortcut set:

- window close, fullscreen, full width, tiled fullscreen, floating, pop-out,
  focus and swap directions;
- global desktops 1-9, next/previous desktop, move window with follow and
  silent move;
- moving a window between screens and walking through windows;
- Krohnkite layout cycling, resize and pointer-follow;
- terminal, tmux, Herdr, browser, private browser, files, editor, calculator,
  password manager, music, Docker and the main web apps;
- universal copy, cut, paste and select-all;
- screenshots, recording, color picker and OCR;
- audio, Bluetooth, network, display, power, calendar and world-clock panels;
- theme and wallpaper switching, emoji picker, display scaling and idle-lock
  toggling;
- Spotify, cliamp, keep-above pop-out windows and window-gap toggling;
- dictation, with `F9` push-to-talk and `Alt+Space` toggle.

The differences that remain are mostly not key-binding work.  They come from
Plasma and KWin having different primitives from Hyprland.

## Deliberate differences

| Area | Omarchy | Plasmarchy | Why |
| --- | --- | --- | --- |
| Push-to-talk key | Hold Right Alt | Hold `F9` | Hardware-independent and does not clash with the Right Alt input-method convention; `Alt+Space` still toggles. |
| Workspaces | Per-monitor workspaces 1-4/1-10 | Nine global virtual desktops | Plasma virtual desktops are global. Per-monitor workspaces need a custom window-management layer. |
| Layouts | Dwindle, scrolling, floating | Tile, Spiral, Floating (Krohnkite) | Krohnkite ships static layouts and has no layout plugin API. See the dwindle section below. |
| App choices | Nautilus, Omawrite, HEY web apps, 1Password, Omacalc | Dolphin, Kate, Thunderbird/kclock, KeePassXC, Qalculate | The Plasmarchy set is packaged on Arch/CachyOS and does not require an Omarchy account. |
| Shell | Omarchy bar and menu | Plasma panel and KRunner | Plasmarchy keeps Plasma's shell instead of replacing it. |
| Window grouping | Hyprland groups | KWin Grid View on `Meta+G` | KWin has no equivalent tabbed/grouped window model. |
| Dictation transport | Omarchy's Voxtype wrapper | Voxtype directly | Same daemon and models; Plasmarchy only owns the key bindings and config. |

## Shortcut gaps

### Next: low-risk additions

These have a direct KDE action or a small wrapper:

| Hotkey | Action | Implementation |
| --- | --- | --- |
| `Meta+M` | Minimize the active window | Bind KWin's existing `Window Minimize` action. |
| `Meta+Ctrl+Tab` | Return to the former desktop | A small KWin script records desktop changes; a command switches back to the recorded id. `previousDesktop()` is numeric, not history. |
| `Meta+Home` | Restore the saved window width | KWin script stores geometry per window class/window; restore resizes the active window. |
| `Meta+Alt+Home` | Save the active window width | Companion to the previous command. |
| `Ctrl+Alt+Del` | Close all windows | Dedicated KWin script that iterates windows and closes them, with a confirmation option. Keep `Meta+Escape` for logout. |
| `Meta+Shift+Ctrl+R` | Clear all KAlarm reminders | KAlarm DBus/CLI wrapper. |
| `Meta+Shift+Space` | Toggle the top panel | Plasma shell script through `evaluateScript`, with a state file so the toggle survives a reload. |
| `Meta+Ctrl+Alt+F` | Full-screen desktop | Combine panel hiding with the existing gaps toggle. |
| `Meta+Shift+Play` | Switch media source | Wrapper around the current MPRIS player (the audio-output switch already exists). |

### Next: window-state work

These need a KWin script because Plasma exposes no single action:

| Hotkey | Action | Notes |
| --- | --- | --- |
| `Meta+Backspace` | Toggle transparency on the active window | KWin has opacity actions but no toggle. A script can toggle the window's opacity between 1.0 and a configured value, and restore it when the window closes. |
| `Meta+Ctrl+Backspace` | Toggle a single-window square aspect | Resize and centre the floating/active window to a square while remembering its previous geometry. This is an approximation of Hyprland's pseudo-square mode. |
| `Meta+P` | Pseudo window (natural stretch) | Hyprland keeps the tile slot but stretches the content. KWin cannot scale an application's content inside a slot; the closest approximation is a fixed-size floating window. Put this behind a preference rather than pretending it is exact. |
| `Meta+S` / `Meta+Alt+S` | Scratchpad toggle / move window there | Emulate with a dedicated virtual desktop or a tag-like KWin script. A desktop is visible in the pager, so this needs care to feel hidden. |
| `Meta+Shift+grave` | Move window to Quake console | Move the window to the Yakuake-managed desktop or send it to Yakuake through its DBus interface; needs a safe fallback when Yakuake is not running. |

### Later: convenience and shell features

| Hotkey | Action | Feasibility |
| --- | --- | --- |
| `Meta+Alt+K` | Show tmux keybindings | A `kdialog` viewer generated from the installed tmux config. Low risk. |
| `Meta+Ctrl+K` | Show Herdr keybindings | Same pattern, generated from `herdr --default-config` when Herdr is installed. |
| `Meta+comma` and the comma modifiers | Act on, dismiss and browse notifications | Plasma exposes notification history and Do Not Disturb already; per-notification actions need the Plasma notification DBus API. |
| `Meta+Ctrl+1-9` | Toggle bar panels by position | No Omarchy bar in Plasmarchy. Could map to Plasma panel widgets, but the result is not the same feature. |
| `Meta+Ctrl+O` | Toggle menu | Omarchy-only menu. KRunner already covers app and command search. |
| `Meta+Ctrl+S` | Share menu | LocalSend is already bound directly; a menu adds little. |
| `Meta+Ctrl+period` | Transcode media | HandBrake is already bound directly. |
| `Meta+Shift+Ctrl+A` | AI-agent picker | Omarchy-specific agent list. Could become a configurable launcher later. |
| `Meta+Shift+Alt+F` | File manager in the terminal's cwd | Dolphin does not expose the focused terminal's cwd consistently; needs a per-terminal adapter. |
| `Meta+Minus/Equal` with Alt/Ctrl | Resize by small/large steps | Krohnkite exposes one grow/shrink step. Multiple steps need a patched layout or repeated synthetic actions. |
| `Meta+scroll` | Scroll workspaces | KGlobalAccel does not treat wheel events as global shortcuts; needs a KWin input filter. |

### Not planned

These are Omarchy-specific or would require replacing a large part of Plasma:

- window grouping, group navigation and moving windows into groups;
- per-monitor workspaces and moving a whole workspace to another monitor;
- Omarchy bar panel toggles and the Omarchy menu;
- webcam overlay resizing;
- Omarchy-specific agent and share menus;
- exact Hyprland `pseudo` content stretching;
- Omarchy's scrolling layout unless it is implemented as a custom Krohnkite
  layout.

## Dwindle layout: can Krohnkite be extended?

### What Krohnkite provides

Krohnkite 0.9.10.0 keeps every layout in `contents/code/script.js`.  The
layout registry is a hard-coded list:

```js
const layoutsList = [
  [TileLayout, true],
  [MonocleLayout, false],
  [ThreeColumnLayout, true],
  [SpiralLayout, true],
  // ...
];
```

`SpiralLayout` is built from `HalfSplitLayoutPart` and `FillLayoutPart`.  It
creates a fixed nested split for every window count.  For the common case of
opening windows one after another it looks close to Hyprland's dwindle layout:
the first window fills the screen, the next window splits the deepest area in
half, and the split direction rotates as the tree deepens.

It is not the same algorithm:

- Hyprland inserts a new window at the **focused leaf**, not at the deepest
  end of a fixed spiral.
- Hyprland chooses the split direction from the cursor position or the
  `force_split` setting, and `Super+J` changes the next split.
- Hyprland keeps the tree across window closes and focus changes.  Krohnkite
  rebuilds its spiral from the current window count.
- Krohnkite's `SpiralLayout` has no public extension point, so a new layout
  cannot be dropped into a config directory.

### Is a custom layout feasible?

Yes, but it is a fork/patch, not a configuration change.  The reusable
geometry primitives (`HalfSplitLayoutPart`, `StackLayoutPart`,
`LayoutUtils`) already do the hard pixel math, so a `DwindleLayout` class can
reuse them.  The work is in the tree state:

1. Pin/fork Krohnkite and add `DwindleLayout` (or replace the body of
   `SpiralLayout` to keep the KCM unchanged).
2. Keep a per-screen, per-desktop binary tree.  Each leaf owns one window;
   each internal node stores orientation, split ratio and children.
3. On a new window, insert it as a sibling of the focused leaf.  Choose the
   orientation from the cursor half or a configurable force-split mode.
   Collapse the parent when a window closes.
4. Reuse the existing split parts for geometry and implement `adjust`,
   `clone` and `handleShortcut` (for rotate/toggle-split).
5. Register the class in `layoutsList`, set its order key, and optionally add
   a KCM group so it can be ordered and disabled.
6. Add a pinned patched `.kwinscript` under `vendor/` with a checksum, and a
   deploy flag that selects it instead of the Codeberg latest release.

The configuration-only alternatives are cheaper:

- **Keep stock Krohnkite and use Spiral as the default.**  This is the
  closest existing approximation with zero fork maintenance.  It matches the
  sequential-open feel but not focus-aware insertion.
- **Use Tile as the default.**  Predictable master/stack tiling, but visibly
  different from Hyprland.

### Recommendation

Do not build a tiler from scratch.  If exact dwindle behaviour matters after
daily use, build a **pinned Krohnkite fork** with a `DwindleLayout` class and
ship it as a versioned vendored asset.  Keep stock Krohnkite selectable with
an explicit flag.  This keeps the geometry work small and the risk contained.

Rough effort:

- focus-aware prototype: 1-2 days;
- robust close/reopen, screen hotplug, resize and multi-desktop handling:
  4-7 days;
- KCM integration and upstream-quality review: 1-2 weeks.

Until that exists, the honest description is "dwindle-like" rather than
"Hyprland dwindle".  The current Tile -> Spiral -> Floating order is a useful
compromise: Tile for predictable master/stack work, Spiral for the closest
sequential split behaviour, Floating for free placement.

## Suggested milestones

1. **Shortcut polish** - `Meta+M`, former desktop, save/restore width, close
   all, clear reminders, panel/full-screen-desktop toggles.
2. **Window-state parity** - transparency, square aspect, scratchpad/Quake
   moves, split-step resizing.
3. **Dwindle prototype** - pinned fork, `DwindleLayout`, A/B against Spiral
   on a real session, then decide whether to make it the default.
4. **Shell parity** - notification actions, tmux/Herdr keybinding viewers,
   panel toggles where they make sense on Plasma.

Each milestone should keep `manifests/shortcuts.tsv` as the source of truth,
regenerate `docs/plasmarchy-shortcuts.{html,txt,pdf}`, and run:

```bash
python3 lib/shortcuts.py lint manifests/shortcuts.tsv
python3 lib/shortcuts.py check manifests/shortcuts.tsv --conflicts
./install.sh deploy --check
```

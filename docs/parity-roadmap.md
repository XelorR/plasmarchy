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
- focus-aware Dwindle tiling, the Dwindle -> Columns -> Floating layout
  cycle, resize and pointer-follow;
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
| Layouts | Dwindle, scrolling, floating | Dwindle, Columns, Floating (Krohnkite fork) | The Plasmarchy fork adds focus-aware Dwindle. Krohnkite has no scrolling layout. |
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

## Dwindle layout

Plasmarchy uses a pinned Krohnkite fork with a `DwindleLayout` class beside
the upstream layouts.  The reference implementation is Hyprland 0.56.2
(`src/layout/algorithm/tiled/dwindle/DwindleAlgorithm.cpp`); the fork keeps
the same tree, child-order and split semantics inside KWin.

### Implemented behavior

- Each workspace has a binary tree of window leaves.  Leaves hold window ids,
  so a floating, minimized or desktop-switched window keeps its slot.
- A new window splits the focused window's leaf.  It never appends to a global
  window sequence, so unrelated branches and their split ratios stay intact.
- With Hyprland's default `force_split = 0` and `use_active_for_splits = true`,
  the cursor's half of the focused tile decides whether the new window is the
  first or second child.  The focused window keeps the opposite child.
- The split is side-by-side when `width > height * split_width_multiplier` and
  top/bottom otherwise.  A square area is top/bottom, matching Hyprland's
  strict comparison with the default multiplier of 1.0.
- A new split uses the default 0.5 ratio and is unlocked, mirroring
  `default_split_ratio = 1.0` and `preserve_split = false`.  `Meta+J` and
  `RotatePart` lock an explicit orientation; an unlocked split reorients when
  its area changes shape.
- Closing a window replaces its parent with the sibling.  Resizing adjusts
  the nearest ancestor split that can consume the delta.
- `Meta+Left`/`Meta+Right` use the rendered geometry.  With all four
  `focusMoveScreens*`/`focusMoveVDesktops*` flags off, focus stops at the edge
  instead of wrapping or switching virtual desktops.

### Plasmarchy integration

- The layout cycle is `Dwindle -> Columns -> Floating`; every other Krohnkite
  layout is disabled.  `Floating` is the "window" state of the cycle.
- `screenDefaultLayout` is `:DwindleLayout`.
- The fork build is pinned as `vendor/krohnkite-0.9.11.1.kwinscript` with a
  SHA256 checksum.  The same fixed-path asset is published at
  `dist/krohnkite.kwinscript` on the fork's tag and `master`, so the deployer
  can download it without GitHub releases or API authentication.
- `DwindleLayout` shares the tree implementation with `BinaryTreeLayout`.
  The user-facing names and layout ids remain separate.
- Tests cover four-plus windows, root-adjacent and deeply nested focused
  leaves, unrelated-branch ratio preservation, subsequent insertions, and
  the unlocked/default-ratio behavior of new splits.

### Not implemented

- `force_split`, `smart_split`, `smart_resizing`, `split_width_multiplier`
  and `default_split_ratio` are not exposed as Krohnkite settings.  KWin
  scripting has no Hyprland-style cursor dispatcher or live layout messages,
  so the fork follows the defaults above instead of pretending to support
  every runtime mode.
- Hyprland's `scrolling` layout is a separate algorithm and is not planned.
- Exact Hyprland `pseudo` content stretching and window groups remain
  unavailable; see the sections above.

## Backlog

- Voice dictation hold-to-talk on **F9** has now been addressed.  The root cause
  was that Plasmarchy explicitly disabled Voxtype's own evdev hotkey listener:
  only `Meta+Ctrl+X`/`Alt+Space` called `voxtype record toggle`, while holding
  F9 arrived at KGlobalAccel and did not start or stop a recording.  The fix
  enables Voxtype's built-in F9 push-to-talk and uses the multilingual Parakeet
  v3 int8 model on the AVX2 ONNX backend; use `sudo voxtype setup onnx --enable`
  if the daemon is still the Whisper binary.

## Suggested milestones

1. **Shortcut polish** - `Meta+M`, former desktop, save/restore width, close
   all, clear reminders, panel/full-screen-desktop toggles.
2. **Window-state parity** - transparency, square aspect, scratchpad/Quake
   moves, split-step resizing.
3. **Dwindle hardening** - screen hotplug, dock/panel interactions, capacity
   changes, and multi-desktop restore paths on real hardware.
4. **Shell parity** - notification actions, tmux/Herdr keybinding viewers,
   panel toggles where they make sense on Plasma.

Each milestone should keep `manifests/shortcuts.tsv` as the source of truth,
regenerate `docs/plasmarchy-shortcuts.{html,txt,pdf}`, and run:

```bash
python3 lib/shortcuts.py lint manifests/shortcuts.tsv
python3 lib/shortcuts.py check manifests/shortcuts.tsv --conflicts
./install.sh deploy --check
```

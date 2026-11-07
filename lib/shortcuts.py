#!/usr/bin/env python3
"""Apply Plasmarchy shortcut maps through KGlobalAccel.

The map format is deliberately small and tab-separated so it can be reviewed
without a GUI:

    component<TAB>action<TAB>keys<TAB>note

`keys` is a semicolon-separated list of KDE key sequences.  An empty key field
clears the action.  The component is the exact KGlobalAccel component ID, for
example `kwin`, `plasmashell` or `plasmarchy-terminal.desktop`.

Shift+digit combinations are written naturally (`Meta+Shift+7`) but encoded
through their shifted symbol (`Meta+&`), because that is what KWin and
KGlobalAccel receive from the keyboard.
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

# Qt key codes, as used by KGlobalAccel.  These are stable across Qt 6.
MODIFIERS = {
    "shift": 0x02000000,
    "ctrl": 0x04000000,
    "control": 0x04000000,
    "alt": 0x08000000,
    "meta": 0x10000000,
    "super": 0x10000000,
    "win": 0x10000000,
    "keypad": 0x20000000,
}

KEYS = {
    "escape": 0x01000000,
    "esc": 0x01000000,
    "tab": 0x01000001,
    "backtab": 0x01000002,
    "backspace": 0x01000003,
    "return": 0x01000004,
    "enter": 0x01000004,
    "insert": 0x01000006,
    "delete": 0x01000007,
    "del": 0x01000007,
    "pause": 0x01000008,
    "print": 0x01000009,
    "printscreen": 0x01000009,
    "sysreq": 0x0100000a,
    "clear": 0x0100000b,
    "home": 0x01000010,
    "end": 0x01000011,
    "left": 0x01000012,
    "up": 0x01000013,
    "right": 0x01000014,
    "down": 0x01000015,
    "pageup": 0x01000016,
    "pagedown": 0x01000017,
    "prior": 0x01000016,
    "next": 0x01000017,
    "menu": 0x01000055,
    "help": 0x0100005a,
    "back": 0x01000061,
    "forward": 0x01000062,
    "stop": 0x01000063,
    "refresh": 0x01000064,
    "volumedown": 0x01000070,
    "volumemute": 0x01000071,
    "volumeup": 0x01000072,
    "mediaplay": 0x01000080,
    "mediastop": 0x01000081,
    "mediaprevious": 0x01000082,
    "mediaprev": 0x01000082,
    "medianext": 0x01000083,
    "mediarecord": 0x01000084,
    "homepage": 0x01000090,
    "favorites": 0x01000091,
    "search": 0x01000092,
    "standby": 0x01000093,
    "openurl": 0x01000094,
    "launchmail": 0x010000a0,
    "launchmedia": 0x010000a1,
    "monbrightnessup": 0x010000b2,
    "monbrightnessdown": 0x010000b3,
    "monitorbrightnessup": 0x010000b2,
    "monitorbrightnessdown": 0x010000b3,
    "keyboardlightonoff": 0x010000b4,
    "keyboardbrightnessup": 0x010000b5,
    "keyboardbrightnessdown": 0x010000b6,
    "micmute": 0x01000113,
    "microphonemute": 0x01000113,
    "poweroff": 0x010000b7,
    "wakeup": 0x010000b8,
    "eject": 0x010000b9,
    "screensaver": 0x010000ba,
    "calculator": 0x010000cb,
    "space": 0x20,
    "plus": 0x2b,
    "minus": 0x2d,
    "equal": 0x3d,
    "comma": 0x2c,
    "period": 0x2e,
    "slash": 0x2f,
    "semicolon": 0x3b,
    "apostrophe": 0x27,
    "quote": 0x27,
    "grave": 0x60,
    "backtick": 0x60,
    "tilde": 0x7e,
    "bracketleft": 0x5b,
    "bracketright": 0x5d,
    "backslash": 0x5c,
    "bar": 0x7c,
    "underscore": 0x5f,
    "colon": 0x3a,
    "asterisk": 0x2a,
    "question": 0x3f,
}

for _i in range(1, 36):
    KEYS[f"f{_i}"] = 0x01000030 + _i - 1
for _i in range(10):
    KEYS[f"launch{_i}"] = 0x010000a2 + _i
for _i in range(10):
    KEYS[str(_i)] = 0x30 + _i
for _c in "abcdefghijklmnopqrstuvwxyz":
    KEYS[_c] = ord(_c.upper())

# KDE/QKeySequence spellings that do not normalize to the same word.
KEYS.update(
    {
        "monitorbrightnessup": 0x010000b2,
        "monitorbrightnessdown": 0x010000b3,
        "keyboardlightonoff": 0x010000b4,
        "mediaplaypause": 0x01000080,
    }
)

SINGLE_CHAR_KEYS = {
    "`": 0x60,
    "~": 0x7e,
    "!": 0x21,
    "@": 0x40,
    "#": 0x23,
    "$": 0x24,
    "%": 0x25,
    "^": 0x5e,
    "&": 0x26,
    "*": 0x2a,
    "(": 0x28,
    ")": 0x29,
    "-": 0x2d,
    "=": 0x3d,
    "[": 0x5b,
    "]": 0x5d,
    "\\": 0x5c,
    ";": 0x3b,
    "'": 0x27,
    ",": 0x2c,
    ".": 0x2e,
    "/": 0x2f,
    "+": 0x2b,
    "_": 0x5f,
    ":": 0x3a,
    "?": 0x3f,
}

# KWin and KGlobalAccel match the key symbol, not the physical digit key.
# A real Meta+Shift+7 arrives as Meta+& (with Shift still held, but the
# shortcut itself must be registered as Meta+& without a Shift modifier).
# Keep the map readable as Meta+Shift+7 and normalise it here.
SHIFTED_DIGITS = {
    0x30: ")",
    0x31: "!",
    0x32: "@",
    0x33: "#",
    0x34: "$",
    0x35: "%",
    0x36: "^",
    0x37: "&",
    0x38: "*",
    0x39: "(",
}

GDBUS = ["gdbus", "call", "--session", "--dest", "org.kde.kglobalaccel",
         "--object-path", "/kglobalaccel", "--method"]
KGA = "org.kde.KGlobalAccel"


class MapError(Exception):
    pass


@dataclass(frozen=True)
class Entry:
    line: int
    component: str
    action: str
    keys: tuple[int, ...]
    key_text: str
    note: str
    friendly_component: str = ""
    friendly_action: str = ""


def norm(text: str) -> str:
    return "".join(ch for ch in text.lower() if ch.isalnum())


def parse_combo(combo: str) -> int:
    combo = combo.strip()
    if not combo:
        raise MapError("empty key sequence")
    parts = [p.strip() for p in combo.split("+") if p.strip()]
    if not parts:
        raise MapError(f"invalid key sequence: {combo!r}")
    mods = 0
    key = None
    for part in parts:
        n = norm(part)
        if n in MODIFIERS:
            mods |= MODIFIERS[n]
            continue
        if key is not None:
            raise MapError(f"more than one non-modifier key in {combo!r}")
        if part in SINGLE_CHAR_KEYS:
            key = SINGLE_CHAR_KEYS[part]
        elif n in KEYS:
            key = KEYS[n]
        elif len(part) == 1:
            key = ord(part.upper())
        else:
            raise MapError(f"unknown key name {part!r} in {combo!r}")
    if key is None:
        raise MapError(f"no non-modifier key in {combo!r}")
    if mods & MODIFIERS["shift"] and key in SHIFTED_DIGITS:
        key = SINGLE_CHAR_KEYS[SHIFTED_DIGITS[key]]
        mods &= ~MODIFIERS["shift"]
    return mods | key


def kde_combo(combo: str) -> str:
    """Return the spelling KDE uses for a combo (Shift+digit -> symbol)."""
    parts = [p.strip() for p in combo.split("+") if p.strip()]
    if any(p.lower() == "shift" for p in parts):
        for part in parts:
            if len(part) == 1 and part.isdigit():
                without_shift = [p for p in parts if p.lower() != "shift"]
                index = without_shift.index(part)
                without_shift[index] = SHIFTED_DIGITS[ord(part)]
                return "+".join(without_shift)
    return "+".join(parts)


def parse_keys(text: str) -> tuple[int, ...]:
    text = text.strip()
    if not text:
        return ()
    keys = []
    for raw in text.split(";"):
        raw = raw.strip()
        if not raw or raw.lower() == "none":
            continue
        keys.append(parse_combo(raw))
    if len(set(keys)) != len(keys):
        raise MapError(f"duplicate key in {text!r}")
    return tuple(keys)


def load_map(path: Path) -> list[Entry]:
    entries: list[Entry] = []
    seen_actions: dict[tuple[str, str], int] = {}
    seen_keys: dict[int, tuple[str, str, str, int]] = {}

    with path.open(encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) < 3:
                raise MapError(f"{path}:{lineno}: expected at least 3 tab-separated fields")
            component, action, key_text = fields[0].strip(), fields[1].strip(), fields[2].strip()
            note = fields[3].strip() if len(fields) > 3 else ""
            if not component or not action:
                raise MapError(f"{path}:{lineno}: empty component or action")
            try:
                keys = parse_keys(key_text)
            except MapError as exc:
                raise MapError(f"{path}:{lineno}: {exc}") from exc
            ident = (component, action)
            if ident in seen_actions:
                raise MapError(
                    f"{path}:{lineno}: action {component}/{action} already defined on line {seen_actions[ident]}"
                )
            seen_actions[ident] = lineno
            for key in keys:
                if key in seen_keys:
                    other = seen_keys[key]
                    raise MapError(
                        f"{path}:{lineno}: key {key_text!r} duplicates "
                        f"{other[2]!r} for {other[0]}/{other[1]} on line {other[3]}"
                    )
                seen_keys[key] = (component, action, key_text, lineno)
            entries.append(Entry(lineno, component, action, keys, key_text, note))
    if not entries:
        raise MapError(f"{path}: no entries")
    return entries


def split_groups(value: str | None) -> set[str] | None:
    if not value:
        return None
    groups = {x.strip().lower() for x in value.split(",") if x.strip()}
    return groups or None


def group_of(entry: Entry) -> str:
    # KWin QML ShortcutHandler actions (used by Krohnkite) are registered under
    # the "kwin" component because KGlobalAccel derives the component from the
    # KWin process, not from the script name.
    if entry.component == "kwin" and entry.action.startswith("Krohnkite"):
        return "krohnkite"
    if entry.component.startswith("plasmarchy-"):
        return "custom"
    return "native"


def selected(entry: Entry, groups: set[str] | None) -> bool:
    return groups is None or group_of(entry) in groups


def gdbus(method: str, *args: str, check: bool = True) -> str:
    cmd = [*GDBUS, f"{KGA}.{method}", *args]
    proc = subprocess.run(cmd, text=True, capture_output=True)
    if check and proc.returncode:
        raise RuntimeError(
            f"{' '.join(cmd)}\n{proc.stderr.strip() or proc.stdout.strip()}"
        )
    return proc.stdout.strip()


def dbus_quote(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def action_id(entry: Entry) -> str:
    return (
        "["
        + ", ".join(
            dbus_quote(x)
            for x in (
                entry.component,
                entry.action,
                entry.friendly_component,
                entry.friendly_action,
            )
        )
        + "]"
    )


def keys_variant(keys: tuple[int, ...]) -> str:
    return "[" + ", ".join(str(k) for k in keys) + "]"


def parse_all_actions(output: str) -> list[tuple[str, str, str, str]]:
    return [
        (m.group(1), m.group(2), m.group(3), m.group(4))
        for m in re.finditer(
            r"\['([^']*)', '([^']*)', '([^']*)', '([^']*)'\]", output
        )
    ]


_action_cache: dict[str, dict[str, tuple[str, str]]] = {}


def component_actions(component: str) -> dict[str, tuple[str, str]]:
    """Return {action: (friendly_component, friendly_action)}."""
    if component in _action_cache:
        return _action_cache[component]
    out = gdbus("allActionsForComponent", "[" + dbus_quote(component) + "]", check=False)
    actions: dict[str, tuple[str, str]] = {}
    for comp, action, friendly_comp, friendly_action in parse_all_actions(out):
        if comp == component:
            actions[action] = (friendly_comp, friendly_action)
    _action_cache[component] = actions
    return actions


def enrich(entries: list[Entry]) -> list[Entry]:
    result = []
    for entry in entries:
        actions = component_actions(entry.component)
        friendly = actions.get(entry.action, ("", ""))
        result.append(
            Entry(
                entry.line,
                entry.component,
                entry.action,
                entry.keys,
                entry.key_text,
                entry.note,
                friendly[0],
                friendly[1],
            )
        )
    return result


def get_keys(entry: Entry) -> tuple[int, ...]:
    out = gdbus("shortcutKeys", action_id(entry), check=False)
    sequences = []
    for match in re.finditer(r"\[([0-9][0-9,\s]*)\]", out):
        numbers = [int(x) for x in re.findall(r"\d+", match.group(1))]
        if numbers:
            sequences.append(numbers[0])
    return tuple(sequences)


def set_keys(entry: Entry, keys: tuple[int, ...], dry_run: bool) -> bool:
    current = get_keys(entry)
    if sorted(current) == sorted(keys):
        return False
    if dry_run:
        return True
    gdbus("setShortcut", action_id(entry), keys_variant(keys), "4")
    actual = get_keys(entry)
    if sorted(actual) != sorted(keys):
        raise RuntimeError(
            f"verification failed for {entry.component}/{entry.action}: "
            f"wanted {keys}, got {actual}"
        )
    return True


def fmt_keys(keys: tuple[int, ...]) -> str:
    return ", ".join(str(k) for k in keys) if keys else "none"


def conflict_actions(key: int) -> list[tuple[str, str, str, str]]:
    out = gdbus("getGlobalShortcutsByKey", str(key), check=False)
    found = []
    for match in re.finditer(
        r"\('([^']*)', '([^']*)', '([^']*)', '([^']*)', '[^']*', '[^']*'", out
    ):
        # KGlobalAccel returns (friendly action, friendly action, component,
        # friendly component).  Normalise to (component, action, ...).
        found.append((match.group(3), match.group(1), match.group(2), match.group(4)))
    return found


def apply_map(
    path: Path,
    dry_run: bool,
    groups: set[str] | None,
    quiet: bool,
    allow_missing: bool = False,
) -> int:
    try:
        entries = load_map(path)
    except MapError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    entries = [e for e in entries if selected(e, groups)]
    if not entries:
        print("error: no entries selected", file=sys.stderr)
        return 2
    entries = enrich(entries)

    missing = [
        e
        for e in entries
        if e.keys and e.action not in component_actions(e.component)
    ]
    for entry in missing:
        print(
            f"warning: action does not exist: {entry.component}/{entry.action} (line {entry.line})",
            file=sys.stderr,
        )
    if missing and not allow_missing:
        print(
            "error: refusing to apply a map with missing actions "
            "(use --allow-missing to skip them)",
            file=sys.stderr,
        )
        return 1
    keyed = [entry for entry in entries if entry.keys]
    if keyed and len(missing) == len(keyed):
        print(
            "error: none of the selected shortcut actions are registered; "
            "the component has not loaded yet",
            file=sys.stderr,
        )
        return 1

    changed = 0
    cleared = 0
    for entry in entries:
        if entry.keys:
            continue
        if entry.action not in component_actions(entry.component):
            if not quiet:
                print(f"skip (missing): {entry.component}/{entry.action}")
            continue
        try:
            if set_keys(entry, (), dry_run):
                cleared += 1
                if not quiet:
                    print(f"cleared: {entry.component}/{entry.action}")
        except Exception as exc:  # noqa: BLE001 - report and continue
            print(f"error clearing {entry.component}/{entry.action}: {exc}", file=sys.stderr)
            return 1

    for entry in entries:
        if not entry.keys:
            continue
        if entry.action not in component_actions(entry.component):
            continue
        try:
            if set_keys(entry, entry.keys, dry_run):
                changed += 1
                if not quiet:
                    print(f"{'would set' if dry_run else 'set'}: "
                          f"{entry.component}/{entry.action} -> {entry.key_text} "
                          f"[{fmt_keys(entry.keys)}]")
        except Exception as exc:  # noqa: BLE001
            print(f"error setting {entry.component}/{entry.action}: {exc}", file=sys.stderr)
            return 1

    if not quiet:
        print(
            f"\n{'DRY RUN: ' if dry_run else ''}"
            f"{changed} shortcut action(s) changed, {cleared} cleared, "
            f"{len(missing)} missing action(s)."
        )
    return 0


def check_map(
    path: Path,
    groups: set[str] | None,
    conflicts: bool,
    allow_missing: bool = False,
) -> int:
    try:
        entries = [e for e in load_map(path) if selected(e, groups)]
    except MapError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    entries = enrich(entries)
    problems = 0
    for entry in entries:
        exists = entry.action in component_actions(entry.component)
        current = get_keys(entry) if exists else ()
        state = "ok" if sorted(current) == sorted(entry.keys) else "diff"
        if not exists:
            state = "missing"
            if not allow_missing:
                problems += 1
        print(
            f"{state:7s} {entry.component}/{entry.action} "
            f"want={entry.key_text or 'none'} have={fmt_keys(current)}"
        )
    if conflicts:
        for entry in entries:
            for key in entry.keys:
                found = conflict_actions(key)
                others = [
                    x for x in found if (x[0], x[1]) != (entry.component, entry.action)
                ]
                if others:
                    problems += 1
                    print(
                        f"CONFLICT {entry.component}/{entry.action} key {key}: "
                        + ", ".join(f"{comp}/{act}" for comp, act, _t, _f in others)
                    )
    return 1 if problems else 0


def desktop_quote(value: str) -> str:
    if not re.search(r'[\s"\'\\`$]', value):
        return value
    escaped = (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("`", "\\`")
        .replace("$", "\\$")
    )
    return f'"{escaped}"'


def desktop_value(value: str) -> str:
    return value.replace("\\", "\\\\").replace("\n", " ")


def gen_desktops(commands: Path, map_path: Path, dest: Path, bindir: Path) -> int:
    try:
        entries = load_map(map_path)
    except MapError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    by_component: dict[str, list[str]] = {}
    declared: set[str] = set()
    for entry in entries:
        declared.add(entry.component)
        if entry.keys:
            by_component.setdefault(entry.component, []).append(entry.key_text)

    rows = []
    with commands.open(encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) < 4:
                print(f"error: {commands}:{lineno}: expected 4 tab-separated fields", file=sys.stderr)
                return 2
            rows.append(tuple(x.strip() for x in fields[:4]))

    dest.mkdir(parents=True, exist_ok=True)
    wanted = set()
    command_ids = {row[0] for row in rows}
    for ident, name, sub, icon in rows:
        wanted.add(f"plasmarchy-{ident}.desktop")
        component = f"plasmarchy-{ident}.desktop"
        keys = by_component.get(component, [])
        exec_line = f"{desktop_quote(str(bindir / 'plasmarchy-cmd'))} {sub}"
        lines = [
            "[Desktop Entry]",
            "Type=Application",
            f"Name={desktop_value(name)}",
            "Comment=Plasmarchy shortcut wrapper",
            f"Exec={exec_line}",
            f"Icon={desktop_value(icon)}",
            "Terminal=false",
            "StartupNotify=false",
            "NoDisplay=true",
            "X-Plasmarchy=true",
        ]
        if keys:
            # X-KDE-Shortcuts is comma-separated: a comma cannot be used inside
            # one sequence.  It is only the registration default; the final
            # binding is still written through KGlobalAccel below.  Keep the
            # first usable sequence so KGlobalAccel discovers the component.
            flat = [
                kde_combo(sequence.strip())
                for text in keys
                for sequence in text.split(";")
                if sequence.strip()
            ]
            safe = [sequence for sequence in flat if "," not in sequence]
            if safe:
                lines.append("X-KDE-Shortcuts=" + ",".join(safe))
            elif flat:
                print(
                    f"warning: {component} has only comma-containing sequences; "
                    "leaving X-KDE-Shortcuts empty",
                    file=sys.stderr,
                )
        target = dest / component
        target.write_text("\n".join(lines) + "\n", encoding="utf-8")
        target.chmod(0o644)

    # Remove stale wrappers from a previous deployment.
    for old in dest.glob("plasmarchy-*.desktop"):
        if old.name in wanted:
            continue
        try:
            text = old.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if "X-Plasmarchy=true" in text:
            old.unlink()

    # A command may be deliberately left unbound; only warn when the map does
    # not mention it at all.
    missing = sorted({f"plasmarchy-{i}.desktop" for i in command_ids} - declared)
    for component in missing:
        print(f"warning: no shortcut map entry for {component}", file=sys.stderr)
    extra = sorted(
        {
            component
            for component in by_component
            if component.startswith("plasmarchy-") and component not in wanted
        }
    )
    for component in extra:
        print(
            f"warning: shortcut map references an unknown command: {component}",
            file=sys.stderr,
        )
    print(f"Generated {len(wanted)} desktop wrapper(s) in {dest}.")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Plasmarchy KGlobalAccel helper")
    sub = parser.add_subparsers(dest="command", required=True)

    p_apply = sub.add_parser("apply", help="apply a shortcut map")
    p_apply.add_argument("map", type=Path)
    p_apply.add_argument("--dry-run", action="store_true")
    p_apply.add_argument("--only", help="native, custom, krohnkite (comma-separated)")
    p_apply.add_argument("--quiet", action="store_true")
    p_apply.add_argument(
        "--allow-missing",
        action="store_true",
        help="warn and skip actions that do not exist in this Plasma version",
    )

    p_check = sub.add_parser("check", help="compare map with the running session")
    p_check.add_argument("map", type=Path)
    p_check.add_argument("--only")
    p_check.add_argument("--conflicts", action="store_true")
    p_check.add_argument(
        "--allow-missing",
        action="store_true",
        help="do not fail when an action is missing",
    )

    p_gen = sub.add_parser("gen-desktops", help="generate custom .desktop wrappers")
    p_gen.add_argument("commands", type=Path)
    p_gen.add_argument("map", type=Path)
    p_gen.add_argument("dest", type=Path)
    p_gen.add_argument("bindir", type=Path)

    p_lint = sub.add_parser("lint", help="validate the map without D-Bus")
    p_lint.add_argument("map", type=Path)

    args = parser.parse_args(argv)
    if args.command == "apply":
        return apply_map(
            args.map,
            args.dry_run,
            split_groups(args.only),
            args.quiet,
            args.allow_missing,
        )
    if args.command == "check":
        return check_map(
            args.map,
            split_groups(args.only),
            args.conflicts,
            args.allow_missing,
        )
    if args.command == "gen-desktops":
        return gen_desktops(args.commands, args.map, args.dest, args.bindir)
    if args.command == "lint":
        try:
            entries = load_map(args.map)
        except MapError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2
        print(f"{len(entries)} entries, {sum(len(e.keys) for e in entries)} key sequences.")
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

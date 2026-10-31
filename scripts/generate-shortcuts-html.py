#!/usr/bin/env python3
"""Generate docs/plasmarchy-shortcuts.html from manifests/shortcuts.tsv."""

import html
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
TSV = ROOT / "manifests" / "shortcuts.tsv"
OUT = ROOT / "docs" / "plasmarchy-shortcuts.html"

SECTION_TITLES = {
    "KWin / session / shell actions": "Windows, desktops and session",
    "Plasma shell": "Plasma shell and clipboard",
    "Session": "Session control",
    "Power management": "Power and displays",
    "Audio and media": "Audio and media",
    "Keyboard layout: Right Ctrl is configured through kxkbrc (grp:rctrl_toggle).": "Keyboard layout and cleared defaults",
    "Third-party defaults that would steal our keys": "Keyboard layout and cleared defaults",
    "Krohnkite.  The layout order is configured separately:": "Krohnkite tiling",
    "Custom commands (desktop files generated from manifests/commands.tsv)": "Applications and commands",
}

def load():
    rows = []
    section = "Other"
    with TSV.open(encoding="utf-8") as f:
        for raw in f:
            raw = raw.rstrip("\n")
            if not raw.strip():
                continue
            if raw.lstrip().startswith("#"):
                title = raw.strip("# ").strip()
                section = SECTION_TITLES.get(title, section)
                continue
            fields = raw.split("\t")
            if len(fields) < 4:
                continue
            component, action, keys, note = (f.strip() for f in fields[:4])
            if not keys:
                continue
            purpose = action
            if note:
                purpose = f"{action}: {note}"
            rows.append((section, keys.replace(";", ", "), purpose, component))
    return rows

def build():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    grouped = {}
    order = []
    for section, keys, purpose, component in load():
        grouped.setdefault(section, []).append((keys, purpose, component))
        if section not in order:
            order.append(section)
    parts = [
        "<!DOCTYPE html><html><head><meta charset='utf-8'><style>",
        "body { font-family: sans-serif; font-size: 10pt; margin: 12px; }",
        "h1 { font-size: 16pt; margin: 0 0 6px 0; }",
        "h2 { font-size: 12pt; margin: 12px 0 4px 0; }",
        "p { margin: 0 0 8px 0; color: #454545; }",
        "table { border-collapse: collapse; table-layout: fixed; width: 100%; }",
        "th, td { border-bottom: 1px solid #d8d8d8; padding: 4px 8px 4px 0; vertical-align: top; }",
        "th.shortcut, td.shortcut { font-family: monospace; width: 35%; }",
        "th { text-align: left; background: #262626; color: #ffffff; padding: 6px 8px; }",
        "tr:nth-child(even) { background: #f3f3f3; }",
        "a { color: #2070d0; }",
        "</style></head><body>",
        "<h1>Plasmarchy keyboard shortcuts</h1>",
        '<p>Working shortcuts from the KGlobalAccel map. Reference: '
        '<a href="https://omarchy.org/manual/hotkeys/">Omarchy hotkeys</a>.</p>',
    ]
    for section in order:
        parts.append(f"<h2>{section}</h2>")
        parts.append("<table><thead><tr><th class='shortcut'>Shortcut</th><th>What it does</th></tr></thead><tbody>")
        for shortcut, what, component in grouped[section]:
            what_html = html.escape(f"{what} ({component})")
            shortcut_html = html.escape(shortcut)
            parts.append(f"<tr><td class='shortcut'><strong>{shortcut_html}</strong></td><td>{what_html}</td></tr>")
        parts.append("</tbody></table>")
    parts.append("</body></html>")
    OUT.write_text("\n".join(parts), encoding="utf-8")
    print(f"Wrote {OUT} with {sum(map(len, grouped.values()))} shortcuts in {len(order)} groups")

if __name__ == "__main__":
    build()

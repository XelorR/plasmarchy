#!/usr/bin/env python3
"""Generate docs/plasmarchy-shortcuts.html from manifests/shortcuts.tsv."""

import html
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
TSV = ROOT / "manifests" / "shortcuts.tsv"
OUT = ROOT / "docs" / "plasmarchy-shortcuts.html"

def rows():
    result = []
    for raw in TSV.read_text(encoding="utf-8").splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
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
        result.append((keys.replace(";", ", "), purpose, component))
    result.sort(key=lambda r: (r[2], r[1]))
    return result

def build():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    parts = [
        "<!DOCTYPE html><html><head><meta charset='utf-8'><style>",
        "body { font-family: sans-serif; font-size: 10pt; margin: 12px; }",
        "h1 { font-size: 16pt; margin: 0 0 6px 0; }",
        "p { margin: 0 0 10px 0; color: #454545; }",
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
        "<table><thead><tr><th class='shortcut'>Shortcut</th><th>What it does</th></tr></thead><tbody>",
    ]
    for shortcut, purpose, component in rows():
        purpose_html = html.escape(f"{purpose} ({component})")
        shortcut_html = html.escape(shortcut)
        parts.append(f"<tr><td class='shortcut'><strong>{shortcut_html}</strong></td><td>{purpose_html}</td></tr>")
    parts.append("</tbody></table></body></html>")
    OUT.write_text("\n".join(parts), encoding="utf-8")
    print(f"Wrote {OUT} with {len(rows())} shortcuts")

if __name__ == "__main__":
    build()

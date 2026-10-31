#!/usr/bin/env python3
"""Generate docs/plasmarchy-shortcuts.txt from manifests/shortcuts.tsv."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TSV = ROOT / "manifests" / "shortcuts.tsv"
OUT = ROOT / "docs" / "plasmarchy-shortcuts.txt"

def rows():
    lines = []
    lines.append("Plasmarchy keyboard shortcuts")
    lines.append("=" * 33)
    lines.append("")
    lines.append("Reference: https://omarchy.org/manual/hotkeys/")
    lines.append("")
    current_section = ""
    with TSV.open(encoding="utf-8") as f:
        for raw in f:
            raw = raw.rstrip("\n")
            if not raw.strip():
                continue
            if raw.lstrip().startswith("#"):
                continue
            fields = raw.split("\t")
            if len(fields) < 4:
                continue
            component, action, keys, note = (f.strip() for f in fields[:4])
            if not keys.strip():
                continue
            shortcut = keys.replace(";", ", ")
            purpose = action
            if note:
                purpose = f"{action}: {note}"
            lines.append(f"{shortcut}\t\t\t{purpose}")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {OUT}: {sum(1 for x in lines if x.strip())} lines")

if __name__ == "__main__":
    rows()

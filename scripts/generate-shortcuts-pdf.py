#!/usr/bin/env python3
"""Generate docs/plasmarchy-shortcuts.pdf from manifests/shortcuts.tsv."""

import csv
import os
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import landscape, A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

ROOT = Path(__file__).resolve().parent.parent
TSV = ROOT / "manifests" / "shortcuts.tsv"
OUT = ROOT / "docs" / "plasmarchy-shortcuts.pdf"

def shortcut_text(keys):
    return ", ".join(keys).replace(";", ", ")

def load_rows():
    rows = []
    with TSV.open(encoding="utf-8") as f:
        for raw in f:
            raw = raw.rstrip("\n")
            if not raw.strip() or raw.lstrip().startswith("#"):
                continue
            fields = raw.split("\t")
            if len(fields) < 4:
                continue
            component, action, keys, note = fields[0], fields[1], fields[2], fields[3]
            if not keys.strip():
                continue
            description = action
            if note.strip():
                description = f"{action} — {note.strip()}"
            rows.append((keys.strip(), description, component))
    rows.sort(key=lambda r: (r[2], r[1]))
    return rows

def build():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(
        str(OUT),
        pagesize=landscape(A4),
        leftMargin=15 * mm,
        rightMargin=15 * mm,
        topMargin=15 * mm,
        bottomMargin=15 * mm,
    )
    styles = getSampleStyleSheet()
    title_style = styles["Title"]
    title_style.spaceAfter = 8
    small = ParagraphStyle("small", parent=styles["BodyText"], fontSize=7.5, leading=9)
    h = [Paragraph("Plasmarchy keyboard shortcuts", title_style)]
    h.append(Paragraph(
        "Working shortcuts from the KGlobalAccel map. "
        "Reference: https://omarchy.org/manual/hotkeys/.",
        small,
    ))
    h.append(Spacer(1, 4 * mm))

    body_style = ParagraphStyle("body", parent=styles["BodyText"], fontSize=7.5, leading=9)
    data = [["Shortcut", "What it does"]]
    for shortcut, description, component in load_rows():
        data.append([Paragraph(f"<b>{shortcut}</b>", body_style),
                     Paragraph(f"{description} ({component})", body_style)])

    table = Table(data, colWidths=[70 * mm, 180 * mm])
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#202020")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, 0), 9),
        ("GRID", (0, 0), (-1, -1), 0.25, colors.grey),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f3f3f3")]),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 2),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
    ]))
    h.append(table)
    doc.build(h)
    print(f"Wrote {OUT} with {len(data) - 1} shortcuts")

if __name__ == "__main__":
    build()

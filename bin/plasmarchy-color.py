#!/usr/bin/env python3
"""Pick a screen colour with KWin and copy it to the Wayland clipboard."""

from __future__ import annotations

import re
import shutil
import subprocess
import sys


def notify(title: str, body: str) -> None:
    if shutil.which("notify-send"):
        subprocess.run(
            ["notify-send", "-a", "Plasmarchy", "--", title, body], check=False
        )


def pick_argb() -> int:
    """Run KWin's graphical colour picker and return the selected ARGB value."""
    proc = subprocess.run(
        [
            "gdbus",
            "call",
            "--session",
            "--dest",
            "org.kde.KWin",
            "--object-path",
            "/ColorPicker",
            "--method",
            "org.kde.kwin.ColorPicker.pick",
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode:
        raise RuntimeError(proc.stderr.strip() or "KWin colour picker failed")
    match = re.search(r"uint32\s+(\d+)", proc.stdout)
    if not match:
        raise RuntimeError(f"unexpected KWin reply: {proc.stdout.strip()}")
    return int(match.group(1))


def copy_to_clipboard(text: str) -> None:
    if shutil.which("wl-copy"):
        proc = subprocess.run(
            ["wl-copy"], input=text, text=True, capture_output=True, check=False
        )
        if not proc.returncode:
            return
    if shutil.which("xclip"):
        proc = subprocess.run(
            ["xclip", "-selection", "clipboard"],
            input=text,
            text=True,
            capture_output=True,
            check=False,
        )
        if not proc.returncode:
            return
    raise RuntimeError("install wl-clipboard (Wayland) or xclip")


def main() -> int:
    try:
        argb = pick_argb()
    except Exception as exc:  # noqa: BLE001 - report through a notification
        notify("Colour picker", str(exc))
        print(str(exc), file=sys.stderr)
        return 1

    # KWin returns 0 when the user presses Escape.
    if argb == 0:
        return 0

    alpha = (argb >> 24) & 0xFF
    red = (argb >> 16) & 0xFF
    green = (argb >> 8) & 0xFF
    blue = argb & 0xFF

    if alpha == 0xFF:
        text = f"#{red:02x}{green:02x}{blue:02x}"
    else:
        text = f"#{red:02x}{green:02x}{blue:02x}{alpha:02x}"

    try:
        copy_to_clipboard(text)
    except Exception as exc:  # noqa: BLE001
        notify("Colour picker", str(exc))
        print(str(exc), file=sys.stderr)
        return 1

    notify("Colour picked", f"{text} copied to clipboard")
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())

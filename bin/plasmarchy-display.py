#!/usr/bin/env python3
"""Small kscreen-doctor helpers used by Plasmarchy shortcuts."""

from __future__ import annotations

import json
import subprocess
import sys


def notify(title: str, body: str) -> None:
    subprocess.run(["notify-send", "-a", "Plasmarchy", "--", title, body], check=False)


def kscreen_json() -> dict:
    proc = subprocess.run(
        ["kscreen-doctor", "-j"], text=True, capture_output=True, check=False
    )
    if proc.returncode:
        raise RuntimeError(proc.stderr.strip() or "kscreen-doctor -j failed")
    return json.loads(proc.stdout)


def outputs() -> list[dict]:
    return kscreen_json().get("outputs", [])


def active_name(all_outputs: list[dict]) -> str:
    proc = subprocess.run(
        ["qdbus6", "org.kde.KWin", "/KWin", "org.kde.KWin.activeOutputName"],
        text=True,
        capture_output=True,
        check=False,
    )
    name = proc.stdout.strip().strip('"')
    if name and any(o.get("name") == name for o in all_outputs):
        return name
    enabled = [o for o in all_outputs if o.get("enabled")]
    if enabled:
        return str(sorted(enabled, key=lambda o: o.get("priority", 999))[0]["name"])
    raise RuntimeError("No active output")


def run_kscreen(*args: str) -> None:
    proc = subprocess.run(
        ["kscreen-doctor", *args], text=True, capture_output=True, check=False
    )
    if proc.returncode:
        raise RuntimeError(proc.stderr.strip() or "kscreen-doctor failed")


def is_internal(output: dict) -> bool:
    name = str(output.get("name", ""))
    return name.startswith(("eDP", "LVDS", "DSI", "edp", "lvds", "dsi"))


def logical_size(output: dict) -> tuple[int, int]:
    """Return the output's mode size in logical (compositor) pixels."""
    size = output.get("size") or {}
    scale = float(output.get("scale") or 1.0)
    return (
        round(int(size.get("width", 0)) / scale),
        round(int(size.get("height", 0)) / scale),
    )


def scale_next(direction: int) -> int:
    all_outputs = outputs()
    name = active_name(all_outputs)
    current = next((o for o in all_outputs if o.get("name") == name), None)
    if current is None:
        notify("Display scale", "Active output was not found")
        return 1
    scales = [1.0, 1.25, 1.5, 1.75, 2.0]
    value = float(current.get("scale", 1.0))
    nearest = min(range(len(scales)), key=lambda i: abs(scales[i] - value))
    new_value = scales[(nearest + direction) % len(scales)]
    text = f"{new_value:g}"
    run_kscreen(f"output.{name}.scale.{text}")
    notify("Display scale", f"{name}: {text}")
    return 0


def toggle_display() -> int:
    all_outputs = outputs()
    internal = [o for o in all_outputs if o.get("connected") and is_internal(o)]
    if not internal:
        notify("Displays", "No internal display found")
        return 0
    enabled_internal = [o for o in internal if o.get("enabled")]
    if enabled_internal:
        others = [
            o
            for o in all_outputs
            if o.get("connected") and o.get("enabled") and not is_internal(o)
        ]
        if not others:
            notify("Displays", "Refusing to disable the only active display")
            return 0
        run_kscreen(*[f"output.{o['name']}.disable" for o in enabled_internal])
        notify("Displays", "Internal display disabled")
    else:
        external = [
            o for o in all_outputs if o.get("connected") and o.get("enabled") and not is_internal(o)
        ]
        args = [f"output.{o['name']}.enable" for o in internal]
        if external:
            # Extend the desktop to the right of the external outputs instead of
            # stacking the internal panel at 0,0 (which makes KWin report two
            # screens in the same region and breaks tiling).
            right = max(
                int(o.get("pos", {}).get("x", 0)) + logical_size(o)[0] for o in external
            )
            top = min(int(o.get("pos", {}).get("y", 0)) for o in external)
            y = top
            for output in internal:
                args.append(f"output.{output['name']}.position.{right},{y}")
                y += logical_size(output)[1]
        run_kscreen(*args)
        notify("Displays", "Internal display enabled")
    return 0


def enabled_rectangles(all_outputs: list[dict]) -> list[tuple[str, int, int, int, int]]:
    """Enabled, non-mirrored outputs as (name, x, y, width, height)."""
    rects = []
    for output in all_outputs:
        if not output.get("enabled"):
            continue
        # Mirrored outputs deliberately occupy the same rectangle; skip them.
        if output.get("replicationSource") or output.get("clones"):
            continue
        width, height = logical_size(output)
        if width <= 0 or height <= 0:
            continue
        pos = output.get("pos") or {}
        rects.append(
            (
                str(output.get("name")),
                int(pos.get("x", 0)),
                int(pos.get("y", 0)),
                width,
                height,
            )
        )
    return rects


def check_layout() -> int:
    """Warn when enabled outputs overlap; this breaks per-screen tiling."""
    rects = enabled_rectangles(outputs())
    problems = 0
    for index, first in enumerate(rects):
        for second in rects[index + 1 :]:
            ax, ay, aw, ah = first[1:]
            bx, by, bw, bh = second[1:]
            if ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah:
                problems += 1
                print(
                    f"enabled displays overlap: {first[0]} ({ax},{ay} {aw}x{ah}) "
                    f"and {second[0]} ({bx},{by} {bw}x{bh})"
                )
    return 1 if problems else 0


def toggle_mirror() -> int:
    all_outputs = outputs()
    internal = next(
        (o for o in all_outputs if o.get("connected") and is_internal(o)), None
    )
    if internal is None:
        notify("Displays", "No internal display found")
        return 0
    if not internal.get("enabled"):
        notify("Displays", "Enable the internal display before mirroring")
        return 0
    external = next(
        (
            o
            for o in all_outputs
            if o.get("connected") and not is_internal(o) and o.get("name") != internal.get("name")
        ),
        None,
    )
    if external is None:
        notify("Displays", "No external display found")
        return 0
    mirrored = external.get("replicationSource") == internal.get("id")
    if mirrored:
        run_kscreen(f"output.{external['name']}.mirror.none")
        notify("Displays", f"{external['name']} no longer mirrors {internal['name']}")
    else:
        run_kscreen(f"output.{external['name']}.mirror.{internal['name']}")
        notify("Displays", f"{external['name']} mirrors {internal['name']}")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(
            "usage: plasmarchy-display.py toggle|mirror|scale-next|scale-prev|check",
            file=sys.stderr,
        )
        return 2
    command = argv[1]
    try:
        if command == "scale-next":
            return scale_next(1)
        if command == "scale-prev":
            return scale_next(-1)
        if command == "toggle":
            return toggle_display()
        if command == "mirror":
            return toggle_mirror()
        if command == "check":
            return check_layout()
    except Exception as exc:  # noqa: BLE001 - show a desktop notification
        notify("Plasmarchy", str(exc))
        print(str(exc), file=sys.stderr)
        return 1
    print(f"unknown command: {command}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))

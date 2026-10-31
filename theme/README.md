# Plasmarchy window decoration

A minimal Aurorae theme for the Plasmarchy setup:

- no titlebar (the top border is only 2 px high);
- 2 px border on all sides;
- active border: cyan `#33ccff` → green `#00ff99` gradient approximation;
- inactive border: solid `#595959`;
- no rounding, padding or shadow.

## Files

- `plasmarchy/metadata.desktop` — theme metadata.
- `plasmarchy/plasmarchyrc` — Aurorae layout and color settings.
- `plasmarchy/decoration.svg` — 9-slice border artwork.

## Install (does not activate)

```bash
./install-theme.sh
```

## Activate

```bash
/usr/lib/plasma-apply-aurorae __aurorae__svg__plasmarchy
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key BorderSize Tiny
qdbus6 org.kde.KWin /KWin reconfigure
```

`BorderSize=Tiny` is required: with `BorderSize=None`, KWin discards the side and
bottom borders. The theme keeps `Padding*=0`, so Aurorae does not generate a
shadow.

## Roll back

```bash
/usr/lib/plasma-apply-aurorae org.kde.breeze
```

## Limitation

Aurorae draws the frame as nine separate SVG fragments, so it cannot render one
continuous 45-degree gradient across the whole window. The theme approximates
it per edge: top/left go from cyan to an intermediate teal, bottom/right go from
teal to green, with matching corner colors. An exact single gradient would need
a custom QML decoration.

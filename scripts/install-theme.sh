#!/usr/bin/env bash
# Install the Plasmarchy Aurorae window decoration into the user's theme directory.
# This does not activate it: run the "apply" command printed at the end when ready.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$ROOT/theme/plasmarchy"
DEST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/aurorae/themes/plasmarchy"

if [[ ! -f "${SRC_DIR}/plasmarchyrc" || ! -f "${SRC_DIR}/decoration.svg" || ! -f "${SRC_DIR}/metadata.desktop" ]]; then
    echo "error: theme source files are missing in ${SRC_DIR}" >&2
    exit 1
fi

mkdir -p "${DEST_DIR}"
install -m 0644 "${SRC_DIR}/plasmarchyrc" "${DEST_DIR}/plasmarchyrc"
install -m 0644 "${SRC_DIR}/decoration.svg" "${DEST_DIR}/decoration.svg"
install -m 0644 "${SRC_DIR}/metadata.desktop" "${DEST_DIR}/metadata.desktop"

echo "Installed Plasmarchy decoration to ${DEST_DIR}"
echo
echo "Activate it with:"
echo "  /usr/lib/plasma-apply-aurorae __aurorae__svg__plasmarchy"
echo "  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key BorderSize Tiny"
echo "  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key BorderSizeAuto --type bool false"
echo "  qdbus6 org.kde.KWin /KWin reconfigure"
echo
echo "Roll back with:"
echo "  /usr/lib/plasma-apply-aurorae org.kde.breeze"

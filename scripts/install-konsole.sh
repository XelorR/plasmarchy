#!/usr/bin/env bash
# Install the Plasmarchy Konsole profile and make it the default.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
KONSOLE_DIR="$DATA_HOME/konsole"
KONSOLE_PROFILE="$KONSOLE_DIR/Plasmarchy.profile"
KONSOLE_RC="$CONFIG_HOME/konsolerc"

if ! command -v konsole >/dev/null 2>&1; then
    echo "konsole is not installed; skipping Konsole defaults"
    exit 0
fi

install -d "$KONSOLE_DIR"
install -m 0644 "$ROOT/config/konsole/Plasmarchy.profile" "$KONSOLE_PROFILE"
if [[ ! -f "$KONSOLE_RC" ]]; then
    install -m 0644 "$ROOT/config/konsole/konsolerc" "$KONSOLE_RC"
else
    # Keep the user's Konsole UI customizations and simply select Plasmarchy as
    # the default profile for new windows.  Konsole reads DefaultProfile from
    # [Desktop Entry]; writing it to [General] is silently ignored.  Remove the
    # old misplaced key when upgrading an earlier Plasmarchy installation.
    kwriteconfig6 --file "$KONSOLE_RC" --group "Desktop Entry" --key DefaultProfile Plasmarchy.profile >/dev/null 2>&1 || true
    kwriteconfig6 --file "$KONSOLE_RC" --group General --key DefaultProfile --delete >/dev/null 2>&1 || true
fi

echo "Installed Konsole defaults to $KONSOLE_PROFILE"

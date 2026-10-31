#!/usr/bin/env bash
# Install the Plasmarchy tmux configuration and shell helper functions.
#
# Usage:
#   ./config/install-tmux.sh [--dry-run]
#
# Existing files are backed up to *.plasmarchy-backup before being replaced.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
TMUX_DIR="$CONFIG_HOME/tmux"
BASHRC="$HOME/.bashrc"
DRY_RUN=0

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "error: unknown option: $1" >&2; exit 2 ;;
    esac
done

[[ $EUID -ne 0 ]] || { echo "error: run as your desktop user, not root" >&2; exit 1; }
[[ -f "$ROOT/tmux/tmux.conf" ]] || { echo "error: missing $ROOT/tmux/tmux.conf" >&2; exit 1; }
[[ -f "$ROOT/tmux/functions.sh" ]] || { echo "error: missing $ROOT/tmux/functions.sh" >&2; exit 1; }
command -v tmux >/dev/null 2>&1 || {
    echo "error: tmux is not installed (pacman -S tmux)" >&2
    exit 1
}

install_file() {
    local src="$1" dest="$2" mode="$3"
    if [[ -f "$dest" ]] && ! cmp -s "$src" "$dest"; then
        if ((DRY_RUN)); then
            echo "would back up $dest -> $dest.plasmarchy-backup"
        else
            cp -p "$dest" "$dest.plasmarchy-backup"
        fi
    fi
    if ((DRY_RUN)); then
        echo "would install $dest"
    else
        install -Dm"$mode" "$src" "$dest"
        echo "installed $dest"
    fi
}

install_file "$ROOT/tmux/tmux.conf" "$TMUX_DIR/tmux.conf" 0644
install_file "$ROOT/tmux/functions.sh" "$TMUX_DIR/functions.sh" 0644

BLOCK_START="# >>> plasmarchy tmux functions >>>"
BLOCK_END="# <<< plasmarchy tmux functions <<<"
if ! grep -Fqs "$BLOCK_START" "$BASHRC" 2>/dev/null; then
    if ((DRY_RUN)); then
        echo "would add tmux functions source block to $BASHRC"
    else
        mkdir -p "$(dirname "$BASHRC")"
        {
            echo
            echo "$BLOCK_START"
            echo 'if [[ -f "$HOME/.config/tmux/functions.sh" ]]; then'
            echo '    source "$HOME/.config/tmux/functions.sh"'
            echo 'fi'
            echo "$BLOCK_END"
        } >> "$BASHRC"
        echo "added tmux functions source block to $BASHRC"
    fi
else
    echo "tmux functions already sourced from $BASHRC"
fi

if ((DRY_RUN)); then
    echo
    echo "Dry run: no files changed."
    exit 0
fi

if tmux list-sessions >/dev/null 2>&1; then
    tmux source-file "$TMUX_DIR/tmux.conf" 2>/dev/null || true
    echo "reloaded the running tmux server"
fi

cat <<EOF

tmux configuration installed.

  Prefix:  Ctrl+Space (Ctrl+B also works)
  Reload:  Prefix q
  Help:    Prefix ?
  Session: Meta+Alt+Return opens the Work session

Open a new shell (or run: source ~/.bashrc) to load tdl/tds/tdlm/tsl.
EOF

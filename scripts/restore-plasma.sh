#!/usr/bin/env bash
# Restore a KDE Plasma / KWin snapshot created by create-backup.sh.
#
# Usage:
#   ./restore-plasma.sh [options] [SNAPSHOT]
#
# SNAPSHOT may be a directory name under ./backups, a full path, or "latest".
# With no argument, "latest" is used.
#
# Options:
#   --list               List available snapshots and exit
#   --dry-run            Show what would be copied/removed, change nothing
#   --yes                Do not ask for confirmation
#   --no-delete          Do not remove files that did not exist in the snapshot
#   --reload             Restart plasmashell and ask KWin to reconfigure afterwards
#   --skip-verify        Do not verify manifest.sha256
#   --no-safety-backup   Do not snapshot the current state before restoring
#   -h, --help           Show this help

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_ROOT="$ROOT/backups"

LIST=0
DRY_RUN=0
ASSUME_YES=0
DELETE=1
RELOAD=0
VERIFY=1
SAFETY_BACKUP=1
SNAPSHOT_ARG=""

while (($#)); do
    case "$1" in
        --list) LIST=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        --no-delete) DELETE=0; shift ;;
        --reload) RELOAD=1; shift ;;
        --skip-verify) VERIFY=0; shift ;;
        --no-safety-backup) SAFETY_BACKUP=0; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        --*) echo "error: unknown option: $1" >&2; exit 2 ;;
        *)
            [[ -z "$SNAPSHOT_ARG" ]] || { echo "error: only one snapshot may be given" >&2; exit 2; }
            SNAPSHOT_ARG="$1"
            shift
            ;;
    esac
done

[[ $EUID -ne 0 ]] || {
    echo "error: run this as your desktop user, not as root" >&2
    exit 1
}

if (( LIST )); then
    [[ -d "$BACKUP_ROOT" ]] || { echo "No snapshots in $BACKUP_ROOT"; exit 0; }
    latest="$(readlink "$BACKUP_ROOT/latest" 2>/dev/null || true)"
    while IFS= read -r d; do
        name="$(basename "$d")"
        if [[ "$name" == "$latest" ]]; then
            printf '* %s (latest)\n' "$name"
        else
            printf '  %s\n' "$name"
        fi
    done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'plasma-*' | sort -r)
    exit 0
fi

if [[ -z "$SNAPSHOT_ARG" || "$SNAPSHOT_ARG" == "latest" ]]; then
    if [[ -L "$BACKUP_ROOT/latest" ]]; then
        SNAP="$(readlink -f "$BACKUP_ROOT/latest")"
    else
        SNAP="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'plasma-*' 2>/dev/null | sort -r | head -n1)"
    fi
elif [[ -d "$SNAPSHOT_ARG" ]]; then
    SNAP="$(readlink -f "$SNAPSHOT_ARG")"
elif [[ -d "$BACKUP_ROOT/$SNAPSHOT_ARG" ]]; then
    SNAP="$(readlink -f "$BACKUP_ROOT/$SNAPSHOT_ARG")"
else
    echo "error: snapshot not found: $SNAPSHOT_ARG" >&2
    echo "Use --list to see available snapshots." >&2
    exit 1
fi

[[ -d "$SNAP/home" ]] || { echo "error: $SNAP does not look like a snapshot (missing home/)" >&2; exit 1; }
[[ -f "$SNAP/included.txt" ]] || { echo "error: $SNAP is missing included.txt" >&2; exit 1; }

if (( VERIFY )) && [[ -f "$SNAP/manifest.sha256" ]]; then
    echo "Verifying snapshot checksums..."
    if ! (cd "$SNAP" && sha256sum -c --quiet manifest.sha256); then
        echo "error: checksum verification failed; refusing to restore." >&2
        echo "Use --skip-verify only if you understand the risk." >&2
        exit 1
    fi
fi

echo
echo "Snapshot: $SNAP"
echo "Created:  $(stat -c %y "$SNAP" 2>/dev/null || true)"
echo "Size:     $(du -sh "$SNAP" | cut -f1)"
echo
if [[ -f "$SNAP/meta/system-info.txt" ]]; then
    sed -n '1,20p' "$SNAP/meta/system-info.txt"
    echo
fi
echo "This will restore these paths into $HOME:"
sed 's/^/  /' "$SNAP/included.txt"
if (( DELETE )) && [[ -s "$SNAP/skipped.txt" ]]; then
    echo
    echo "And remove these paths that did not exist when the snapshot was made:"
    sed 's/^/  /' "$SNAP/skipped.txt"
fi
if (( DELETE )); then
    echo
    echo "Extra files inside restored directories will be deleted (use --no-delete to keep them)."
fi
echo
echo "A full KWin/Plasma restart (log out and back in) is recommended after restoring."

if (( DRY_RUN )); then
    echo
    echo "DRY RUN: no changes made."
    exit 0
fi

if (( ! ASSUME_YES )); then
    if [[ ! -t 0 ]]; then
        echo "error: no terminal for confirmation; re-run with --yes" >&2
        exit 1
    fi
    read -r -p "Restore this snapshot? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

if (( SAFETY_BACKUP )) && [[ -x "$ROOT/scripts/create-backup.sh" ]]; then
    echo
    echo "Creating a safety snapshot of the current state..."
    "$ROOT/scripts/create-backup.sh" --tag pre-restore
fi

restore_one() {
    local rel="$1"
    local src="$SNAP/home/$rel"
    local dst="$HOME/$rel"

    if [[ -L "$src" ]]; then
        mkdir -p "$(dirname "$dst")"
        rsync -a "$src" "$dst"
    elif [[ -d "$src" ]]; then
        mkdir -p "$dst"
        if (( DELETE )); then
            rsync -a --delete "$src/" "$dst/"
        else
            rsync -a "$src/" "$dst/"
        fi
    elif [[ -e "$src" ]]; then
        mkdir -p "$(dirname "$dst")"
        rsync -a "$src" "$dst"
    fi
}

echo
echo "Restoring..."
while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    restore_one "$rel"
done < "$SNAP/included.txt"

if (( DELETE )) && [[ -s "$SNAP/skipped.txt" ]]; then
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        # Safety guard: only ever remove paths under the two snapshot roots
        # plus .bashrc (which the tmux installer may create).
        case "$rel" in
            .config/*|.local/share/*|.bashrc) ;;
            *) echo "warning: refusing to remove unexpected path: $rel" >&2; continue ;;
        esac
        rm -rf -- "$HOME/$rel"
    done < "$SNAP/skipped.txt"
fi

# Refresh desktop/application caches after replacing config/theme files.
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
fi

if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
fi

if (( RELOAD )); then
    echo
    echo "Reloading Plasma shell..."
    if systemctl --user restart plasma-plasmashell.service 2>/dev/null; then
        echo "plasmashell restarted."
    else
        echo "warning: could not restart plasma-plasmashell.service" >&2
    fi
    qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
fi

# Make "latest" point at the snapshot that is now active.
if [[ "$(dirname "$SNAP")" == "$BACKUP_ROOT" ]]; then
    ln -sfn "$(basename "$SNAP")" "$BACKUP_ROOT/latest"
fi

echo
echo "Restore complete."
echo "Log out and back in for all KWin, shortcut, and panel changes to take full effect."

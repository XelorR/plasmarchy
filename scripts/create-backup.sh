#!/usr/bin/env bash
# Create a snapshot of the current KDE Plasma / KWin configuration.
#
# Usage:
#   ./create-backup.sh [--tag NAME]
#
# The snapshot is written to ./backups/plasma-YYYY-MM-DD_HH-MM-SS[-NAME]/
# and ./backups/latest is updated to point at it.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_ROOT="$ROOT/backups"
TAG=""

while (($#)); do
    case "$1" in
        --tag)
            [[ $# -ge 2 ]] || { echo "error: --tag requires a value" >&2; exit 2; }
            TAG="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,18p' "$0"
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

[[ $EUID -ne 0 ]] || {
    echo "error: run this as your desktop user, not as root" >&2
    exit 1
}

STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
SNAP_NAME="plasma-$STAMP"
[[ -n "$TAG" ]] && SNAP_NAME="$SNAP_NAME-$TAG"
DEST="$BACKUP_ROOT/$SNAP_NAME"

# Do not silently overwrite a snapshot created in the same second.
if [[ -e "$DEST" ]]; then
    DEST="${DEST}-$$"
fi

mkdir -p "$DEST/home" "$DEST/meta"
: > "$DEST/included.txt"
: > "$DEST/skipped.txt"

# Everything here is Plasma/KWin state: shortcuts, panels, window rules,
# decorations/themes, monitor layout, activities, input, and KWin scripts.
CONFIG_PATHS=(
    ".config/kdeglobals"
    ".config/kglobalshortcutsrc"
    ".config/kwinrc"
    ".config/kwinoutputconfig.json"
    ".config/kwinrulesrc"
    ".config/kscreenlockerrc"
    ".config/ksmserverrc"
    ".config/plasmarc"
    ".config/plasmashellrc"
    ".config/plasma-org.kde.plasma.desktop-appletsrc"
    ".config/plasma-org.kde.plasma.notificationsrc"
    ".config/kactivitymanagerdrc"
    ".config/kactivitymanagerd-statsrc"
    ".config/kaccessrc"
    ".config/kcminputrc"
    ".config/kxkbrc"
    ".config/ktimezonedrc"
    ".config/krunnerrc"
    ".config/klipperrc"
    ".config/ksplashrc"
    ".config/powerdevilrc"
    ".config/powermanagementprofilesrc"
    ".config/kdedefaults"
    ".config/autostart"
    ".config/plasma-workspace"
    ".config/khotkeysrc"
    ".config/tmux"
    ".config/voxtype"
    ".config/systemd/user"
    ".bashrc"
)

LOCAL_PATHS=(
    ".local/share/kwin/scripts"
    ".local/share/kwin/effects"
    ".local/share/kscreen"
    ".local/share/khotkeys"
    ".local/share/plasma"
    ".local/share/aurorae"
    ".local/share/color-schemes"
    ".local/share/wallpapers"
    ".local/share/icons"
    ".local/share/plasma-systemmonitor"
    ".local/share/applications"
    ".local/share/plasmarchy"
)

copy_path() {
    local rel="$1"
    local src="$HOME/$rel"
    if [[ -e "$src" || -L "$src" ]]; then
        tar -C "$HOME" -cf - -- "$rel" | tar -C "$DEST/home" -xpf -
        printf '%s\n' "$rel" >> "$DEST/included.txt"
    else
        printf '%s\n' "$rel" >> "$DEST/skipped.txt"
    fi
}

for rel in "${CONFIG_PATHS[@]}" "${LOCAL_PATHS[@]}"; do
    copy_path "$rel"
done

# Metadata useful when deciding whether a snapshot can be restored safely.
{
    echo "snapshot: $SNAP_NAME"
    echo "created: $(date -Is)"
    echo "hostname: $(hostname 2>/dev/null || true)"
    echo "user: ${USER:-$(id -un)}"
    echo "home: $HOME"
    echo "session: ${XDG_SESSION_TYPE:-unknown}"
    echo "desktop: ${XDG_CURRENT_DESKTOP:-unknown}"
    echo
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "distro: ${PRETTY_NAME:-unknown}"
    fi
    echo "plasmashell: $(plasmashell --version 2>/dev/null || echo unknown)"
    echo "kwin: $(kwin_wayland --version 2>/dev/null || kwin_x11 --version 2>/dev/null || echo unknown)"
    echo
    echo "screens:"
    if command -v kscreen-doctor >/dev/null 2>&1; then
        kscreen-doctor -o 2>/dev/null | sed 's/^/  /' || true
    fi
    echo
    echo "virtual desktops (kwinrc):"
    sed -n '/^\[Desktops\]/,/^\[/p' "$HOME/.config/kwinrc" 2>/dev/null | sed 's/^/  /' || true
    echo
    echo "activities:"
    qdbus6 org.kde.ActivityManager /ActivityManager/Activities \
        org.kde.ActivityManager.Activities.ListActivities 2>/dev/null | sed 's/^/  /' || true
} > "$DEST/meta/system-info.txt"

{
    echo "# Enabled KWin scripts (Plugins group in kwinrc)"
    sed -n '/^\[Plugins\]/,/^\[/p' "$HOME/.config/kwinrc" 2>/dev/null || true
    echo
    echo "# User KWin scripts"
    if [[ -d "$HOME/.local/share/kwin/scripts" ]]; then
        find "$HOME/.local/share/kwin/scripts" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort
    fi
    echo
    echo "# System KWin scripts"
    if [[ -d /usr/share/kwin/scripts ]]; then
        find /usr/share/kwin/scripts -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort
    fi
} > "$DEST/meta/kwin-scripts.txt"

{
    echo "# Explicitly installed pacman packages"
    pacman -Qqe 2>/dev/null || true
    echo
    echo "# Flatpak applications"
    flatpak list --app --columns=application,name 2>/dev/null || true
} > "$DEST/meta/packages.txt"

{
    echo "Restore this snapshot with:"
    echo "  $ROOT/restore-plasma.sh $SNAP_NAME"
    echo
    echo "The restore script also creates a safety snapshot of the state it replaces."
} > "$DEST/README.txt"

# Checksums make accidental corruption detectable before a restore.
(
    cd "$DEST"
    find home -type f -print0 | sort -z | xargs -0 --no-run-if-empty sha256sum > manifest.sha256
)

ln -sfn "$SNAP_NAME" "$BACKUP_ROOT/latest"

echo "Snapshot created: $DEST"
echo "Included paths: $(wc -l < "$DEST/included.txt")"
echo "Skipped (not present): $(wc -l < "$DEST/skipped.txt")"
echo "Size: $(du -sh "$DEST" | cut -f1)"
echo
echo "Restore with: $ROOT/restore-plasma.sh $SNAP_NAME"

#!/usr/bin/env bash
# Install and configure Voxtype dictation on Arch/CachyOS KDE Plasma.
#
# Usage:
#   ./scripts/install-dictation.sh [--dry-run] [--skip-packages] [--no-download]
#
# Voxtype is an AUR package (voxtype-bin).  The installer:
#   - installs voxtype-bin, ydotool, wl-clipboard and libnotify;
#   - writes ~/.config/voxtype/config.toml (Parakeet v3 int8, F9 push-to-talk);
#   - binds F9 as push-to-talk in Voxtype and leaves Alt+Space to KGlobalAccel;
#   - adds the user to the input group and enables ydotool;
#   - downloads the Whisper base model and enables voxtype.service.
#
# A logout/login is required once for the input group and udev permissions.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
VOXTYPE_DIR="$CONFIG_HOME/voxtype"
DRY_RUN=0
INSTALL_PACKAGES=1
DOWNLOAD_MODEL=1
NEED_RELOGIN=0
LANGUAGES=""

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --skip-packages) INSTALL_PACKAGES=0; shift ;;
        --no-download) DOWNLOAD_MODEL=0; shift ;;
        --languages)
            [[ $# -ge 2 ]] || { echo "error: --languages requires a comma-separated list" >&2; exit 2; }
            LANGUAGES="$2"
            shift 2
            ;;
        -h|--help) awk 'NR > 1 && /^#/ { print; next } NR > 1 { exit }' "$0"; exit 0 ;;
        *) echo "error: unknown option: $1" >&2; exit 2 ;;
    esac
done

[[ $EUID -ne 0 ]] || { echo "error: run as your desktop user, not root" >&2; exit 1; }
[[ -f "$ROOT/config/voxtype/config.toml" ]] || {
    echo "error: missing $ROOT/config/voxtype/config.toml" >&2
    exit 1
}

log() { printf '\n==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

aur_helper() {
    if command -v paru >/dev/null 2>&1; then
        echo paru
    elif command -v yay >/dev/null 2>&1; then
        echo yay
    fi
}

sudo_cmd() {
    if ((DRY_RUN)); then
        printf 'would run: sudo %s\n' "$*"
        return 0
    fi
    sudo "$@"
}

if [[ -z "$LANGUAGES" ]]; then
    if [[ -f "$CONFIG_HOME/kxkbrc" ]]; then
        LANGUAGES="$(sed -n 's/^LayoutList=//p' "$CONFIG_HOME/kxkbrc" | tr ',' '\n' | sed -e 's/^ *//; s/ *$//' | awk '
        $0 == "us" { print "en" }
        $0 == "gb" { print "en" }
        $0 == "ru" { print "ru" }
        $0 == "de" { print "de" }
        $0 == "fr" { print "fr" }
        $0 == "es" { print "es" }
        $0 == "it" { print "it" }
        $0 == "pt" { print "pt" }
        ' | sort -u | paste -sd, -)"
    fi
    [[ -n "$LANGUAGES" ]] || LANGUAGES="en,ru"
fi

if ((DRY_RUN)); then
    log "Dry run"
    echo "would install packages: ydotool wl-clipboard libnotify voxtype-bin (AUR)"
    echo "would write $VOXTYPE_DIR/config.toml (F9 push-to-talk)"
    echo "would add $USER to the input group"
    echo "would enable ydotool.service and voxtype.service"
    ((DOWNLOAD_MODEL)) && echo "would download the Parakeet v3 int8 model"
    echo "dictation languages: $LANGUAGES"
    exit 0
fi

if ((INSTALL_PACKAGES)); then
    log "Installing dictation packages"
    command -v sudo >/dev/null 2>&1 || {
        echo "error: sudo is required (or rerun with --skip-packages)" >&2
        exit 1
    }
    sudo -v
    sudo pacman -S --needed --noconfirm ydotool wl-clipboard libnotify

    if ! command -v voxtype >/dev/null 2>&1; then
        helper="$(aur_helper)"
        [[ -n "$helper" ]] || {
            echo "error: voxtype-bin is in the AUR; install paru or yay first" >&2
            exit 1
        }
        "$helper" -S --needed --noconfirm voxtype-bin
    fi
fi

command -v voxtype >/dev/null 2>&1 || {
    echo "error: voxtype is not installed (AUR package: voxtype-bin)" >&2
    exit 1
}
command -v ydotoold >/dev/null 2>&1 || {
    echo "error: ydotool is not installed (pacman -S ydotool)" >&2
    exit 1
}

log "Writing Voxtype configuration"
lang_json="$(printf '%s' "$LANGUAGES" | tr ',' '\n' | sed -e 's/^ *//; s/ *$//' | awk 'BEGIN{printf "["} {if(NR>1)printf ","; printf "\"%s\"", $0} END{printf "]"}')"
tmp_config="$(mktemp)"
sed 's/^language = .*/language = '"$lang_json"'/' "$ROOT/config/voxtype/config.toml" > "$tmp_config"

mkdir -p "$VOXTYPE_DIR"
if [[ -f "$VOXTYPE_DIR/config.toml" ]] && ! cmp -s "$tmp_config" "$VOXTYPE_DIR/config.toml"; then
    cp -p "$VOXTYPE_DIR/config.toml" "$VOXTYPE_DIR/config.toml.plasmarchy-backup"
    echo "backed up the previous config to $VOXTYPE_DIR/config.toml.plasmarchy-backup"
fi
install -m 0644 "$tmp_config" "$VOXTYPE_DIR/config.toml"
rm -f "$tmp_config"
echo "installed $VOXTYPE_DIR/config.toml with languages: $LANGUAGES"

log "Configuring uinput access"
if getent group input | cut -d: -f4 | tr ',' '\n' | grep -qx "$USER"; then
    echo "$USER is already listed in the input group"
    if ! id -nG "$USER" | tr ' ' '\n' | grep -qx input; then
        NEED_RELOGIN=1
        echo "the current session does not have the input group yet; log out and back in"
    fi
else
    sudo usermod -aG input "$USER"
    NEED_RELOGIN=1
    echo "added $USER to the input group"
fi

if [[ ! -e /dev/uinput ]]; then
    sudo modprobe uinput 2>/dev/null || warn "could not load the uinput module"
fi
if [[ -e /dev/uinput ]]; then
    ls -l /dev/uinput
else
    warn "/dev/uinput is missing; ydotool will not work until the module is loaded"
fi

log "Enabling ydotool"
systemctl --user daemon-reload
systemctl --user enable ydotool.service >/dev/null 2>&1 || warn "could not enable ydotool.service"
if id -nG | tr ' ' '\n' | grep -qx input; then
    systemctl --user restart ydotool.service || warn "ydotool.service failed to start"
else
    echo "ydotool.service will start after you log out and back in (input group)"
fi

if ((DOWNLOAD_MODEL)); then
    log "Downloading the multilingual Parakeet v3 (int8) model"
    if [[ -x /usr/lib/voxtype/voxtype-onnx-avx2 ]]; then
        /usr/lib/voxtype/voxtype-onnx-avx2 setup --download --model parakeet-tdt-0.6b-v3-int8 --no-post-install ||
            warn "model download failed; run '/usr/lib/voxtype/voxtype-onnx-avx2 setup --download --model parakeet-tdt-0.6b-v3-int8 --no-post-install' later"
    else
        warn "the ONNX variant is missing; Parakeet dictation will be unavailable until voxtype-bin is installed"
    fi
fi

log "Installing the Voxtype user service"
voxtype setup systemd || warn "voxtype setup systemd failed"
systemctl --user daemon-reload
systemctl --user enable voxtype.service >/dev/null 2>&1 || warn "could not enable voxtype.service"
systemctl --user restart voxtype.service || warn "voxtype.service failed to start"

cat <<EOF

Voxtype dictation installed.

  Push-to-talk:     hold F9 while speaking, release to transcribe
  Toggle dictation: Alt+Space (also Meta+Ctrl+X)
  Config:           $VOXTYPE_DIR/config.toml
  Service:          systemctl --user status voxtype.service

The Alt+Space shortcut is registered by deploy.sh.  F9 is read directly by
Voxtype through /dev/input.  If the input group was just added, log out and
back in once before testing dictation.
EOF

if ((NEED_RELOGIN)); then
    echo
    echo "Logout/login is required: your session does not have the input group yet."
fi

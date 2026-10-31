#!/usr/bin/env bash
# Root-side package setup for Plasmarchy.
#
# Usage:
#   sudo ./root-setup.sh [--user NAME] [--packages required|all]
#                        [--with-dictation] [--no-aur] [--dry-run]
#
# Run this once as root.  It installs official packages, LocalSend and (with
# --with-dictation) the voxtype-bin AUR package, then configures /dev/uinput and
# adds the desktop user to the input group (needed by ydotool for Super+C/V).
#
# Afterwards log out and back in, then run as the desktop user:
#   ./deploy.sh --skip-packages --with-dictation --yes
# (drop --with-dictation if you did not install dictation).
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_USER="${SUDO_USER:-${USER:-}}"
PACKAGES="required"
WITH_DICTATION=0
ALLOW_AUR=1
NEED_RELOGIN=0
DRY_RUN=0

log() { printf '\n==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,14p' "$0"
}

while (($#)); do
    case "$1" in
        --user)
            [[ $# -ge 2 ]] || die "--user requires a value"
            TARGET_USER="$2"
            shift 2
            ;;
        --packages)
            [[ $# -ge 2 ]] || die "--packages requires a value"
            PACKAGES="$2"
            shift 2
            ;;
        --with-dictation) WITH_DICTATION=1; shift ;;
        --no-aur) ALLOW_AUR=0; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

case "$PACKAGES" in
    required|all) ;;
    *) die "invalid --packages value: $PACKAGES (use required or all)" ;;
esac

[[ $EUID -eq 0 ]] || ((DRY_RUN)) || die "run this as root: sudo $0 --user $USER"
[[ -n "$TARGET_USER" && "$TARGET_USER" != "root" ]] ||
    die "could not determine the desktop user; pass --user NAME"
id "$TARGET_USER" >/dev/null 2>&1 || die "unknown user: $TARGET_USER"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "$TARGET_USER")"
[[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] ||
    die "cannot determine the home directory of $TARGET_USER"
command -v pacman >/dev/null 2>&1 || die "pacman not found; this targets Arch/CachyOS"
command -v runuser >/dev/null 2>&1 || die "runuser not found (util-linux)"

[[ -f "$ROOT/manifests/packages-required.txt" ]] ||
    die "manifests/packages-required.txt is missing"

log "Root setup for $TARGET_USER"
printf 'Packages:   %s\n' "$PACKAGES"
printf 'Dictation:  %s\n' "$([[ $WITH_DICTATION == 1 ]] && echo yes || echo no)"
printf 'AUR builds: %s\n' "$([[ $ALLOW_AUR == 1 ]] && echo yes || echo no)"

# A fresh Arch install may not have synced package databases yet.
if ! compgen -G '/var/lib/pacman/sync/*.db' >/dev/null; then
    if ((DRY_RUN)); then
        log "Would sync package databases"
    else
        log "Syncing package databases"
        pacman -Sy --noconfirm
    fi
fi

read_packages() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    awk 'NF && $1 !~ /^#/ {print $1}' "$file"
}

install_official() {
    local mode="$1"
    shift
    local pkg missing=()
    local -a available=()
    for pkg in "$@"; do
        if pacman -Si "$pkg" >/dev/null 2>&1; then
            available+=("$pkg")
        else
            missing+=("$pkg")
        fi
    done
    if ((${#missing[@]})); then
        if [[ "$mode" == "required" ]]; then
            die "package(s) not found in configured repositories: ${missing[*]}"
        fi
        warn "skipping optional package(s) unavailable in the repositories: ${missing[*]}"
    fi
    ((${#available[@]})) || return 0
    local -a needed=()
    for pkg in "${available[@]}"; do
        pacman -Q "$pkg" >/dev/null 2>&1 || needed+=("$pkg")
    done
    ((${#needed[@]})) || {
        log "All requested packages are already installed"
        return 0
    }
    if ((DRY_RUN)); then
        printf 'would install: %s\n' "${needed[*]}"
        return 0
    fi
    pacman -S --needed --noconfirm "${needed[@]}"
}

install_aur() {
    local pkg="$1"
    local check_cmd="${2:-}"
    if pacman -Q "$pkg" >/dev/null 2>&1; then
        log "$pkg is already installed"
        return 0
    fi
    if [[ -n "$check_cmd" ]] && command -v "$check_cmd" >/dev/null 2>&1; then
        log "$check_cmd is already available; not installing $pkg"
        return 0
    fi
    ((ALLOW_AUR)) ||
        die "$pkg is in the AUR; rerun without --no-aur or install it manually"
    command -v git >/dev/null 2>&1 || die "git is required to build AUR packages"

    if ((DRY_RUN)); then
        printf 'would build and install AUR package: %s\n' "$pkg"
        return 0
    fi

    local build_root="/var/tmp/plasmarchy-aur"
    local dir="$build_root/$pkg"
    install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$build_root"
    rm -rf -- "$dir"

    log "Cloning AUR package $pkg"
    runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" \
        git clone --depth=1 "https://aur.archlinux.org/$pkg.git" "$dir"

    # Install official dependencies declared in .SRCINFO.  These packages are
    # binary releases with no AUR dependencies; fail clearly if that changes.
    local dep
    while IFS= read -r dep; do
        [[ -n "$dep" ]] || continue
        pacman -Q "$dep" >/dev/null 2>&1 && continue
        if pacman -Si "$dep" >/dev/null 2>&1; then
            pacman -S --needed --noconfirm "$dep"
        else
            die "$pkg needs $dep, which is not in the configured repositories"
        fi
    done < <(
        awk -F' = ' '/^[[:space:]]*(depends|makedepends) = / {print $2}' "$dir/.SRCINFO" |
            sed -E 's/[<>=].*$//' | sort -u
    )

    # Use a dedicated GnuPG home for AUR signing keys instead of polluting the
    # user's keyring.  If the keyserver is unreachable, makepkg can still fall
    # back to the SHA-256-verified build below.
    local gnupg_home="$build_root/gnupg"
    install -d -m 0700 -o "$TARGET_USER" -g "$TARGET_GROUP" "$gnupg_home"
    local -a pgp_keys=()
    mapfile -t pgp_keys < <(
        awk -F' = ' '/^[[:space:]]*validpgpkeys = / {print $2}' "$dir/.SRCINFO"
    )
    if ((${#pgp_keys[@]})) && command -v gpg >/dev/null 2>&1; then
        log "Importing AUR signing key(s) for $pkg"
        runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" GNUPGHOME="$gnupg_home" \
            gpg --batch --keyserver-options timeout=20 \
                --keyserver hkps://keyserver.ubuntu.com \
                --recv-keys "${pgp_keys[@]}" ||
            warn "could not import PGP keys; the SHA-256-verified fallback will be used if needed"
    fi

    log "Building $pkg as $TARGET_USER"
    if ! runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" GNUPGHOME="$gnupg_home" \
        bash -c "cd $(printf '%q' "$dir") && makepkg -f --noconfirm --nodeps --nocheck"; then
        warn "makepkg failed for $pkg; retrying without PGP signature checks"
        runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" GNUPGHOME="$gnupg_home" \
            bash -c "cd $(printf '%q' "$dir") && makepkg -f --noconfirm --nodeps --nocheck --skippgpcheck"
    fi

    local -a built=()
    mapfile -t built < <(
        find "$dir" -maxdepth 1 -type f -name '*.pkg.tar.*' ! -name '*.sig' -print
    )
    ((${#built[@]})) || die "makepkg produced no package for $pkg"
    log "Installing $pkg"
    pacman -U --noconfirm "${built[@]}"
}

install_localsend() {
    if pacman -Q localsend >/dev/null 2>&1 ||
        pacman -Q localsend-bin >/dev/null 2>&1 ||
        command -v localsend >/dev/null 2>&1; then
        log "LocalSend is already installed"
        return 0
    fi
    if ((DRY_RUN)); then
        if pacman -Si localsend >/dev/null 2>&1; then
            log "Would install LocalSend from the repositories"
        else
            log "Would build and install AUR package localsend-bin"
        fi
        return 0
    fi
    if pacman -Si localsend >/dev/null 2>&1; then
        log "Installing LocalSend from the repositories"
        pacman -S --needed --noconfirm localsend
    else
        install_aur localsend-bin localsend
    fi
}

mapfile -t REQUIRED_PACKAGES < <(read_packages "$ROOT/manifests/packages-required.txt")
mapfile -t OPTIONAL_PACKAGES < <(read_packages "$ROOT/manifests/packages-optional.txt")

(( ${#REQUIRED_PACKAGES[@]} )) || die "the required package list is empty"

log "Installing required packages"
install_official required "${REQUIRED_PACKAGES[@]}"

if [[ "$PACKAGES" == "all" ]] && ((${#OPTIONAL_PACKAGES[@]})); then
    log "Installing optional packages"
    install_official optional "${OPTIONAL_PACKAGES[@]}"
fi

# AUR builds run as the desktop user and need a working base-devel toolchain.
log "Ensuring AUR build tools"
if ((DRY_RUN)); then
    echo "would ensure: base-devel git gnupg"
else
    pacman -S --needed --noconfirm base-devel git gnupg
fi

if ((WITH_DICTATION)); then
    log "Installing dictation packages"
    install_aur voxtype-bin voxtype
fi

install_localsend

# /dev/uinput is needed by ydotool for the Super+C/V clipboard shortcuts and
# by Voxtype.  Configure it even when dictation is not requested.
if ((DRY_RUN)); then
    log "Would add $TARGET_USER to the input group and load uinput"
    NEED_RELOGIN=1
else
    log "Configuring input device access for keyboard emulation"
    getent group input >/dev/null 2>&1 || groupadd input

    if getent group input | cut -d: -f4 | tr ',' '\n' | grep -qx "$TARGET_USER"; then
        echo "$TARGET_USER is already listed in the input group"
        if ! id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx input; then
            NEED_RELOGIN=1
        fi
    else
        usermod -aG input "$TARGET_USER"
        NEED_RELOGIN=1
        echo "added $TARGET_USER to the input group"
    fi

    install -Dm644 /dev/stdin /etc/modules-load.d/plasmarchy-uinput.conf <<'EOF'
uinput
EOF
    # Give the active user access to /dev/uinput without relying only on the
    # input group.  The group rule also helps after a fresh login.
    install -Dm644 /dev/stdin /etc/udev/rules.d/99-plasmarchy-uinput.rules <<'EOF'
KERNEL=="uinput", SUBSYSTEM=="misc", MODE="0660", GROUP="input", TAG+="uaccess"
EOF
    modprobe uinput || warn "could not load the uinput module"
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --subsystem-match=misc 2>/dev/null || true
    udevadm trigger --sysname-match=uinput 2>/dev/null || true
    udevadm trigger --name-match=uinput 2>/dev/null || true
    udevadm settle 2>/dev/null || true

    if [[ -e /dev/uinput ]]; then
        ls -l /dev/uinput
    else
        warn "/dev/uinput is still missing; Super+C/V and dictation will not work until it appears"
    fi
fi

cat <<EOF

$([[ $DRY_RUN == 1 ]] && echo "Root package setup dry run finished; nothing changed." || echo "Root package setup finished.")

Next:
  1. Log out and back in as $TARGET_USER.
     $( ((NEED_RELOGIN)) && echo "This is required for the new input group membership." || echo "This refreshes the session after package installation." )
  2. Run as $TARGET_USER (not root):
     cd $(printf '%q' "$ROOT")
     ./deploy.sh --skip-packages$([[ $WITH_DICTATION == 1 ]] && echo ' --with-dictation') --yes

The user-side deployment does not call sudo.  If it still asks for a password,
check that the step above was run after a fresh login.
EOF

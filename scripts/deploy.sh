#!/usr/bin/env bash
# Deploy Plasmarchy on an Arch/CachyOS KDE Plasma 6 machine.
#
# Usage:
#   ./deploy.sh [options]
#
# Options:
#   --dry-run             Show what would happen, change nothing
#   --yes                 Do not ask for confirmation
#   --check               Run preflight checks and exit
#   --packages MODE       required (default), all, or none
#   --skip-packages       Alias for --packages none
#   --no-backup           Do not create a pre-deploy snapshot
#   --skip-krohnkite      Do not install/enable/configure Krohnkite
#   --krohnkite-version V Tag to download, default latest
#   --krohnkite-bundled   Use the copy shipped in vendor/ instead of downloading
#   --skip-theme          Do not install/activate the Plasmarchy decoration
#   --skip-focus          Do not configure focus-follows-mouse / pointer follow
#   --skip-shortcuts      Do not change any shortcuts
#   --skip-tmux           Do not install the Omarchy tmux configuration
#   --skip-konsole          Do not install the Plasmarchy Konsole profile
#   --install-software    Install distro, AUR and third-party applications too
#   --with-dictation      Install Voxtype dictation (AUR + model download)
#   --dictation-languages  Comma-separated list (auto-detected by default)
#   --restore-backup SNAP Restore a Plasma/KWin snapshot and exit
#   --force               Continue even if the session checks are unusual
#   -h, --help            Show this help
#
# The script is intentionally idempotent.  It backs up the Plasma/KWin state,
# installs packages (optional), installs the pinned Krohnkite release, writes
# Krohnkite/KWin configuration, installs the custom decoration, generates the
# command wrappers, and applies the shortcut map through KGlobalAccel.
#
# It never runs as root.  Package installation uses sudo only for pacman.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
RUNTIME="$DATA_HOME/plasmarchy"
APPLICATIONS="$DATA_HOME/applications"
FOCUS_SCRIPT_DIR="$DATA_HOME/kwin/scripts/plasmarchy-focus"

DRY_RUN=0
ASSUME_YES=0
CHECK_ONLY=0
PACKAGES="none"
BACKUP=1
SKIP_KROHNKITE=0
SKIP_THEME=0
SKIP_FOCUS=0
SKIP_SHORTCUTS=0
SKIP_TMUX=0
SKIP_KONSOLE=0
WITH_DICTATION=0
FORCE=0
INSTALL_SOFTWARE=0
RESTORE_BACKUP=0
RESTORE_SNAPSHOT=""
DICTATION_LANGS=""

KROHNKITE_REF="${KROHNKITE_REF:-latest}"
KROHNKITE_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/plasmarchy"
KROHNKITE_VERSION="$KROHNKITE_REF"
KROHNKITE_ASSET=""
KROHNKITE_DIR="$DATA_HOME/kwin/scripts/krohnkite"
AURORAE_THEME="__aurorae__svg__plasmarchy"

# Effects disabled by configure_animations.  KWin's reconfigure does not
# unload effects that were already active at login, so reload_desktop also
# unloads them explicitly for the current session.
ANIMATION_EFFECTS=(
    blur contrast diminactive translucency
    slide slideback fade fadedesktop glide
    scale squash maximize fullscreen windowaperture
    magiclamp sheet fallapart wobblywindows
    login logout sessionquit
    slidingpopups slidingnotifications fadingpopups
    startupfeedback blendchanges
)

usage() {
    sed -n '2,28p' "$0"
}

log() { printf '\n==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        --check) CHECK_ONLY=1; shift ;;
        --packages)
            [[ $# -ge 2 ]] || die "--packages requires required, all, or none"
            PACKAGES="$2"
            shift 2
            ;;
        --skip-packages) PACKAGES="none"; shift ;;
        --no-backup) BACKUP=0; shift ;;
        --skip-krohnkite) SKIP_KROHNKITE=1; shift ;;
        --krohnkite-version)
            [[ $# -ge 2 ]] || die "--krohnkite-version requires latest or a tag"
            KROHNKITE_REF="$2"; KROHNKITE_VERSION="$2"; shift 2
            ;;
        --krohnkite-bundled) KROHNKITE_REF="bundled"; KROHNKITE_VERSION="bundled"; shift ;;
        --skip-theme) SKIP_THEME=1; shift ;;
        --skip-focus) SKIP_FOCUS=1; shift ;;
        --skip-shortcuts) SKIP_SHORTCUTS=1; shift ;;
        --skip-tmux) SKIP_TMUX=1; shift ;;
        --skip-konsole) SKIP_KONSOLE=1; shift ;;
        --with-dictation)
            WITH_DICTATION=1
            if [[ $# -ge 2 && "$2" != -* ]]; then
                DICTATION_LANGS="$2"
                shift
            fi
            shift
            ;;
        --dictation-languages)
            [[ $# -ge 2 ]] || die "--dictation-languages requires a comma-separated list"
            DICTATION_LANGS="$2"
            WITH_DICTATION=1
            shift 2
            ;;
        --restore-backup)
            [[ $# -ge 2 ]] || die "--restore-backup requires a snapshot name or path"
            RESTORE_BACKUP=1
            RESTORE_SNAPSHOT="$2"
            shift 2
            ;;
        --install-software) INSTALL_SOFTWARE=1; PACKAGES="required"; shift ;;
        --force) FORCE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

case "$PACKAGES" in
    required|all|none) ;;
    *) die "invalid --packages value: $PACKAGES (use required, all, none)" ;;
esac

[[ $EUID -ne 0 ]] || die "run this as your desktop user, not as root"
[[ -f "$ROOT/lib/shortcuts.py" ]] || die "lib/shortcuts.py is missing"
[[ -f "$ROOT/manifests/shortcuts.tsv" ]] || die "manifests/shortcuts.tsv is missing"
[[ -f "$ROOT/manifests/commands.tsv" ]] || die "manifests/commands.tsv is missing"
[[ -f "$ROOT/bin/plasmarchy-color.py" ]] || die "bin/plasmarchy-color.py is missing"
[[ -f "$ROOT/theme/plasmarchy/plasmarchyrc" ]] || die "theme/plasmarchy is missing"
[[ -f "$ROOT/config/kwin/plasmarchy-focus/contents/code/main.js" ]] ||
    die "config/kwin/plasmarchy-focus is missing"
if ! command -v pacman >/dev/null 2>&1; then
    die "pacman not found; this script targets Arch/CachyOS"
fi
if (( ! CHECK_ONLY )) && [[ "$PACKAGES" != "none" ]] && ! command -v sudo >/dev/null 2>&1; then
    die "sudo not found; install sudo or rerun with --skip-packages"
fi

if ((RESTORE_BACKUP)); then
    if ((DRY_RUN)); then
        log "Would restore Plasma/KWin snapshot: $RESTORE_SNAPSHOT"
        exit 0
    fi
    [[ -x "$ROOT/scripts/restore-plasma.sh" ]] || die "restore-plasma.sh is missing"
    exec "$ROOT/scripts/restore-plasma.sh" --yes --reload "$RESTORE_SNAPSHOT"
fi


read_packages() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    awk 'NF && $1 !~ /^#/ {print $1}' "$file"
}

aur_helper() {
    if command -v paru >/dev/null 2>&1; then
        echo paru
    elif command -v yay >/dev/null 2>&1; then
        echo yay
    fi
}

mapfile -t REQUIRED_PACKAGES < <(read_packages "$ROOT/manifests/packages-required.txt")
mapfile -t OPTIONAL_PACKAGES < <(read_packages "$ROOT/manifests/packages-optional.txt")

count_map_entries() {
    awk 'NF && $1 !~ /^#/ {n++} END {print n+0}' "$ROOT/manifests/shortcuts.tsv"
}

session_ok() {
    command -v qdbus6 >/dev/null 2>&1 || return 1
    command -v gdbus >/dev/null 2>&1 || return 1
    qdbus6 org.kde.KWin /KWin >/dev/null 2>&1 || return 1
    qdbus6 org.kde.plasmashell /PlasmaShell >/dev/null 2>&1 || return 1
    return 0
}

preflight() {
    log "Preflight"
    printf 'Repository: %s\n' "$ROOT"
    printf 'Krohnkite:  %s (downloaded on demand, cached locally)\n' "$KROHNKITE_REF"
    printf 'Shortcut map entries: %s\n' "$(count_map_entries)"
    printf 'Packages:   %s\n' "$PACKAGES"
    printf 'Focus:      %s\n' "$([[ $SKIP_FOCUS == 1 ]] && echo skip || echo 'focus-follows-mouse + Krohnkite pointer follow')"
    printf 'tmux:       %s\n' "$([[ $SKIP_TMUX == 1 ]] && echo skip || echo yes)"
    printf 'Dictation:  %s\n' "$([[ $WITH_DICTATION == 1 ]] && echo yes || echo no)"

    local missing=()
    local cmd
    for cmd in qdbus6 gdbus kwriteconfig6 kreadconfig6 kbuildsycoca6 python3 kpackagetool6 curl; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if ((${#missing[@]})); then
        warn "missing commands: ${missing[*]} (will be installed unless --skip-packages)"
    fi

    if [[ "$PACKAGES" == "none" ]]; then
        local missing_pkgs=()
        local pkg
        for pkg in "${REQUIRED_PACKAGES[@]}"; do
            pacman -Q "$pkg" >/dev/null 2>&1 || missing_pkgs+=("$pkg")
        done
        if ((${#missing_pkgs[@]})); then
            warn "missing required packages: ${missing_pkgs[*]}"
            warn "run 'sudo ./root-setup.sh' first, or deploy without --skip-packages"
        fi
        command -v ydotool >/dev/null 2>&1 ||
            warn "ydotool is missing; Super+C/V/X will not work (run root-setup.sh)"
        if ((WITH_DICTATION)); then
            command -v voxtype >/dev/null 2>&1 ||
                warn "voxtype is missing; run root-setup.sh --with-dictation"
        fi
    fi

    if [[ ! -e /dev/uinput ]]; then
        warn "/dev/uinput is missing; Super+C/V and dictation need it (run root-setup.sh, then log in again)"
    elif [[ ! -r /dev/uinput || ! -w /dev/uinput ]]; then
        warn "no read/write access to /dev/uinput; Super+C/V will not work until you log in again"
    fi

    # Two enabled outputs at the same origin make KWin expose two screens in
    # one region; Krohnkite then tiles within the smaller one.
    if command -v kscreen-doctor >/dev/null 2>&1 && [[ -f "$ROOT/bin/plasmarchy-display.py" ]]; then
        local layout_msg
        if ! layout_msg=$(python3 "$ROOT/bin/plasmarchy-display.py" check 2>&1); then
            while IFS= read -r line; do
                [[ -n "$line" ]] && warn "$line"
            done <<< "$layout_msg"
            warn "enabled displays overlap; tiling may be limited to the smaller region"
            warn "fix: kscreen-doctor output.eDP-1.disable, or arrange the outputs side by side"
        fi
    fi

    if [[ "${XDG_SESSION_TYPE:-}" != "wayland" ]]; then
        warn "XDG_SESSION_TYPE is '${XDG_SESSION_TYPE:-unset}', not wayland"
        ((FORCE)) || warn "continuing anyway; test the result on your actual session"
    fi
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" && "${XDG_CURRENT_DESKTOP}" != *KDE* ]]; then
        warn "XDG_CURRENT_DESKTOP is '${XDG_CURRENT_DESKTOP}'"
        ((FORCE)) || true
    fi
}

install_packages() {
    [[ "$PACKAGES" == "none" ]] && { log "Skipping package installation"; return; }

    local list=("${REQUIRED_PACKAGES[@]}")
    if [[ "$PACKAGES" == "all" ]]; then
        list+=("${OPTIONAL_PACKAGES[@]}")
    fi

    if ((DRY_RUN)); then
        log "Would install ${#list[@]} package(s)"
        printf '  %s\n' "${list[@]}"
        printf '  localsend (if missing)\n'
        return
    fi

    log "Installing ${#list[@]} package(s)"
    sudo -v
    if ((${#REQUIRED_PACKAGES[@]})); then
        sudo pacman -S --needed --noconfirm "${REQUIRED_PACKAGES[@]}"
    fi
    if [[ "$PACKAGES" == "all" ]] && ((${#OPTIONAL_PACKAGES[@]})); then
        # Optional packages must not abort the deployment if one is unavailable.
        local pkg helper
        for pkg in "${OPTIONAL_PACKAGES[@]}"; do
            if pacman -Si "$pkg" >/dev/null 2>&1; then
                sudo pacman -S --needed --noconfirm "$pkg" || warn "optional package failed: $pkg"
                continue
            fi
            helper="$(aur_helper)"
            if [[ -n "$helper" ]]; then
                "$helper" -S --needed --noconfirm "$pkg" || warn "optional AUR package failed: $pkg"
            else
                warn "optional package is in the AUR and no helper is installed: $pkg"
            fi
        done
    fi

    # LocalSend is an Omarchy default app.  It is in the CachyOS repository and
    # in the AUR on vanilla Arch, so install it explicitly when it is missing.
    if ! command -v localsend >/dev/null 2>&1; then
        log "Installing LocalSend"
        if pacman -Si localsend >/dev/null 2>&1; then
            sudo pacman -S --needed --noconfirm localsend || warn "LocalSend installation failed"
        else
            local helper
            helper="$(aur_helper)"
            if [[ -n "$helper" ]]; then
                "$helper" -S --needed --noconfirm localsend || warn "LocalSend installation failed"
            else
                warn "LocalSend is in the AUR; install paru/yay or add it manually"
            fi
        fi
    fi
}

create_backup() {
    ((BACKUP)) || { log "Skipping pre-deploy backup (--no-backup)"; return; }
    if ((DRY_RUN)); then
        log "Would create backup with tag pre-deploy"
        return
    fi
    [[ -x "$ROOT/scripts/create-backup.sh" ]] || die "create-backup.sh is missing"
    log "Creating pre-deploy backup"
    "$ROOT/scripts/create-backup.sh" --tag pre-deploy
}

install_runtime_files() {
    if ((DRY_RUN)); then
        log "Would install runtime files into $RUNTIME"
        return
    fi
    log "Installing runtime files into $RUNTIME"
    mkdir -p "$RUNTIME/bin" "$RUNTIME/lib" "$RUNTIME/manifests"
    install -m 0644 "$ROOT/lib/shortcuts.py" "$RUNTIME/lib/shortcuts.py"
    install -m 0755 "$ROOT/bin/plasmarchy-cmd" "$RUNTIME/bin/plasmarchy-cmd"
    install -m 0755 "$ROOT/bin/plasmarchy-display.py" "$RUNTIME/bin/plasmarchy-display.py"
    install -m 0755 "$ROOT/bin/plasmarchy-color.py" "$RUNTIME/bin/plasmarchy-color.py"
    install -d "$RUNTIME/docs"
    for html in plasmarchy-shortcuts.html; do
        if [[ -f "$ROOT/docs/$html" ]]; then
            install -m 0644 "$ROOT/docs/$html" "$RUNTIME/docs/$html"
        fi
    done
    install -m 0755 "$ROOT/bin/plasmarchy-apply-krohnkite" "$RUNTIME/bin/plasmarchy-apply-krohnkite"
    install -m 0644 "$ROOT/manifests/shortcuts.tsv" "$RUNTIME/shortcuts.tsv"
    install -m 0644 "$ROOT/manifests/commands.tsv" "$RUNTIME/commands.tsv"
    install -m 0644 "$ROOT/manifests/packages-required.txt" "$RUNTIME/manifests/packages-required.txt"
    install -m 0644 "$ROOT/manifests/packages-optional.txt" "$RUNTIME/manifests/packages-optional.txt"
}

install_krohnkite() {
    ((SKIP_KROHNKITE)) && { log "Skipping Krohnkite"; return; }
    if ((DRY_RUN)); then
        log "Would install Krohnkite from $KROHNKITE_REF"
        return
    fi

    if [[ "$KROHNKITE_REF" == "bundled" ]]; then
        KROHNKITE_VERSION="0.9.10.0"
        KROHNKITE_ASSET="$ROOT/vendor/krohnkite-$KROHNKITE_VERSION.kwinscript"
        [[ -f "$KROHNKITE_ASSET" ]] || die "missing vendored Krohnkite asset: $KROHNKITE_ASSET"
        (cd "$ROOT/vendor" && sha256sum -c SHA256SUMS)
    else
        local api_url
        if [[ "$KROHNKITE_REF" == "latest" ]]; then
            api_url="https://codeberg.org/api/v1/repos/anametologin/Krohnkite/releases/latest"
        else
            api_url="https://codeberg.org/api/v1/repos/anametologin/Krohnkite/releases/tags/$KROHNKITE_REF"
        fi

        log "Resolving Krohnkite release: $KROHNKITE_REF"
        local meta
        if ! meta="$(curl -fsSL --max-time 20 "$api_url" | python3 - <<'PY'
import json, sys
try:
    d = json.load(sys.stdin)
    if isinstance(d, list):
        if not d:
            raise ValueError("no releases")
        d = d[0]
    tag = d.get("tag_name", "").strip()
    asset = None
    url = None
    for item in d.get("assets", []):
        name = item.get("name", "")
        if name.endswith(".kwinscript"):
            asset = name
            url = item.get("browser_download_url") or item.get("download_url")
            break
    if not tag or not asset or not url:
        raise ValueError("Krohnkite release did not expose a .kwinscript asset")
    print(tag)
    print(asset)
    print(url)
except Exception as exc:
    sys.stderr.write(str(exc) + "\n")
    raise SystemExit(1)
PY
        )"; then
            if [[ -f "$ROOT/vendor/krohnkite-0.9.10.0.kwinscript" ]]; then
                warn "network resolution failed; falling back to vendored Krohnkite 0.9.10.0"
                KROHNKITE_VERSION="0.9.10.0"
                KROHNKITE_ASSET="$ROOT/vendor/krohnkite-$KROHNKITE_VERSION.kwinscript"
            else
                die "could not resolve or download Krohnkite"
            fi
        else
            local tag asset url
            tag="$(printf '%s\n' "$meta" | sed -n '1p')"
            asset="$(printf '%s\n' "$meta" | sed -n '2p')"
            url="$(printf '%s\n' "$meta" | sed -n '3p')"
            KROHNKITE_VERSION="$tag"
            mkdir -p "$KROHNKITE_CACHE_DIR"
            KROHNKITE_ASSET="$KROHNKITE_CACHE_DIR/krohnkite-$tag-$asset"
            if [[ ! -f "$KROHNKITE_ASSET" ]]; then
                log "Downloading Krohnkite $tag"
                [[ -n "$url" ]] || die "Krohnkite download URL is empty"
                if ! curl -fsSL "$url" -o "$KROHNKITE_ASSET"; then
                    if [[ -f "$ROOT/vendor/krohnkite-0.9.10.0.kwinscript" ]]; then
                        warn "download failed; falling back to vendored Krohnkite 0.9.10.0"
                        KROHNKITE_VERSION="0.9.10.0"
                        KROHNKITE_ASSET="$ROOT/vendor/krohnkite-$KROHNKITE_VERSION.kwinscript"
                    else
                        die "could not download Krohnkite"
                    fi
                fi
            fi
        fi
    fi

    [[ -f "$KROHNKITE_ASSET" ]] || die "Krohnkite asset is missing: $KROHNKITE_ASSET"

    local installed=""
    if [[ -f "$KROHNKITE_DIR/metadata.json" ]]; then
        installed="$(python3 - "$KROHNKITE_DIR/metadata.json" <<'PY'
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("KPlugin", {}).get("Version", ""))
except Exception:
    print("")
PY
)"
    fi

    log "Krohnkite asset: $KROHNKITE_ASSET"
    if [[ "$installed" == "$KROHNKITE_VERSION" ]]; then
        log "Krohnkite $KROHNKITE_VERSION is already installed"
    elif [[ -n "$installed" ]]; then
        log "Upgrading Krohnkite $installed -> $KROHNKITE_VERSION"
        kpackagetool6 --type KWin/Script --upgrade "$KROHNKITE_ASSET" ||
            kpackagetool6 --type KWin/Script --install "$KROHNKITE_ASSET"
    else
        log "Installing Krohnkite $KROHNKITE_VERSION"
        kpackagetool6 --type KWin/Script --install "$KROHNKITE_ASSET"
    fi
}


write_krohnkite_config() {
    ((SKIP_KROHNKITE)) && return
    if ((DRY_RUN)); then
        log "Would write Krohnkite config (Tile -> Spiral -> Floating, gaps 10/5)"
        return
    fi
    log "Writing Krohnkite config"

    kc() {
        kwriteconfig6 --file kwinrc --group Script-krohnkite --key "$1" "$2"
    }
    kcb() {
        kwriteconfig6 --file kwinrc --group Script-krohnkite --key "$1" --type bool "$2"
    }

    # Only three layouts are enabled, in this order.  Its layout list is what
    # KrohnkiteNextLayout cycles through.
    kc tileLayoutOrder 1
    kc spiralLayoutOrder 2
    kc floatingLayoutOrder 3
    kc monocleLayoutOrder 0
    kc threeColumnLayoutOrder 0
    kc quarterLayoutOrder 0
    kc stackedLayoutOrder 0
    kc columnsLayoutOrder 0
    kc spreadLayoutOrder 0
    kc stairLayoutOrder 0
    kc binaryTreeLayoutOrder 0
    kc cascadeLayoutOrder 0
    kc screenDefaultLayout ":Tile"

    kc screenGapLeft 10
    kc screenGapRight 10
    kc screenGapTop 10
    kc screenGapBottom 10
    kc screenGapBetween 5
    kcb noTileBorder false
    kcb tileNothing false

    kwriteconfig6 --file kwinrc --group Plugins --key krohnkiteEnabled --type bool true
}

configure_focus() {
    ((SKIP_FOCUS)) && { log "Skipping focus configuration"; return; }
    if ((DRY_RUN)); then
        log "Would set immediate focus-follows-mouse and enable Krohnkite pointer follow"
        return
    fi

    log "Setting focus policy to focus-follows-mouse"
    kwriteconfig6 --file kwinrc --group Windows --key FocusPolicy FocusFollowsMouse
    # KWin delays hover focus by 300 ms by default.  Zero makes it immediate.
    kwriteconfig6 --file kwinrc --group Windows --key DelayFocusInterval 0
    kwriteconfig6 --file kwinrc --group Windows --key AutoRaise --type bool false

    # Krohnkite already knows when focus changed because of a keyboard action
    # (FocusLeft/Right/..., new window, output switch).  Its own option warps
    # the pointer only on those paths -- never on hover -- so no extra KWin
    # script is needed.  The option is read at reconfigure time.
    kwriteconfig6 --file kwinrc --group Script-krohnkite --key movePointerOnFocus --type bool true

    # Remove the old standalone Mouse Follows Focus script if a previous
    # Plasmarchy version installed it.  Leaving it enabled would fight
    # Krohnkite and reintroduce pointer jumps on hover.
    local old_script="$DATA_HOME/kwin/scripts/mouse-follows-focus"
    if [[ -d "$old_script" ]]; then
        log "Removing obsolete Mouse Follows Focus script"
        qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript mouse-follows-focus \
            >/dev/null 2>&1 || true
        if ! kpackagetool6 --type KWin/Script --remove mouse-follows-focus >/dev/null 2>&1; then
            rm -rf "$old_script"
        fi
    fi
    kwriteconfig6 --file kwinrc --group Plugins --key mouse-follows-focusEnabled --type bool false

    # Apply the policy and let Krohnkite reload its config in the running
    # session, so a logout is only needed for the final visual check.
    qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
}

install_theme() {
    ((SKIP_THEME)) && { log "Skipping theme"; return; }
    if ((DRY_RUN)); then
        log "Would install and activate the Plasmarchy Aurorae theme"
        return
    fi
    log "Installing Plasmarchy decoration"
    "$ROOT/scripts/install-theme.sh"

    log "Activating Plasmarchy decoration"
    if command -v plasma-apply-aurorae >/dev/null 2>&1; then
        plasma-apply-aurorae "$AURORAE_THEME"
    elif [[ -x /usr/lib/plasma-apply-aurorae ]]; then
        /usr/lib/plasma-apply-aurorae "$AURORAE_THEME"
    else
        warn "plasma-apply-aurorae not found; writing decoration config directly"
        kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae
        kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme "$AURORAE_THEME"
    fi

    # BorderSize=None removes the side and bottom borders in KWin.  Tiny gives
    # the 2 px frame that the SVG theme expects.
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key BorderSize Tiny
    # KWin otherwise reserves a 4 px frame while the theme paints 2 px, which
    # leaves a transparent gap between the border and the window content.
    kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key BorderSizeAuto --type bool false

    # Omarchy look: no blur, no contrast, no translucency, no dim-inactive.
    local key
    for key in blurEnabled contrastEnabled translucencyEnabled kwin4_effect_translucencyEnabled \
               diminactiveEnabled kwin4_effect_diminactiveEnabled; do
        kwriteconfig6 --file kwinrc --group Plugins --key "$key" --type bool false
    done
}

configure_window_rules() {
    if ((DRY_RUN)); then
        log "Would write KWin window rules: server-side borders and browser fixes"
        return
    fi
    log "Writing KWin window rules"

    # KWin 6.8 stores the active/ordered rule list in [General] Order; older
    # releases use [General] rules.  Write both when a legacy list exists so
    # the same file works on both, and put Plasmarchy rules first: the first
    # matching rule wins, ahead of the system Steam shadow rule.
    local ssd=plasmarchy-ssd browsers=plasmarchy-browsers

    kwriteconfig6 --file kwinrulesrc --group "$ssd" --key Description \
        "Plasmarchy: server-side border for all normal windows"
    kwriteconfig6 --file kwinrulesrc --group "$ssd" --key types 1
    kwriteconfig6 --file kwinrulesrc --group "$ssd" --key decorationpolicy server
    kwriteconfig6 --file kwinrulesrc --group "$ssd" --key decorationpolicyrule 2

    # Chromium/Brave (and other browsers) occasionally restore themselves as
    # fullscreen or always-on-top; both states make Krohnkite ignore them.
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key Description \
        "Plasmarchy: keep browsers tiled"
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key types 1
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key wmclass \
        '^(chromium|chromium-browser|google-chrome|google-chrome-stable|google-chrome-beta|google-chrome-unstable|brave|brave-browser|brave-browser-beta|microsoft-edge|microsoft-edge-stable|microsoft-edge-beta|vivaldi|vivaldi-stable|opera|opera-stable|zen|zen-browser|firefox|firefox-esr|librewolf|floorp|waterfox)([.-].*)?$'
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key wmclassmatch 3
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key wmclasscomplete --type bool false
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key decorationpolicy server
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key decorationpolicyrule 2
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key above --type bool false
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key aboverule 2
    # ApplyInitially: clear a restored fullscreen state at startup but still
    # allow the user to press F11 or use Meta+F later.
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key fullscreen --type bool false
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key fullscreenrule 1
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key noborder --type bool false
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key noborderrule 2
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key skiptaskbar --type bool false
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key skiptaskbarrule 2
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key skippager --type bool false
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key skippagerrule 2
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key skipswitcher --type bool false
    kwriteconfig6 --file kwinrulesrc --group "$browsers" --key skipswitcherrule 2

    local order legacy combined entry
    order="$(kreadconfig6 --file kwinrulesrc --group General --key Order --default '' 2>/dev/null || true)"
    legacy="$(kreadconfig6 --file kwinrulesrc --group General --key rules --default '' 2>/dev/null || true)"
    combined="$ssd,$browsers"
    local -A seen=()
    seen[$ssd]=1
    seen[$browsers]=1
    for entry in ${order//,/ } ${legacy//,/ }; do
        [[ -n "$entry" && -z "${seen[$entry]:-}" ]] || continue
        seen[$entry]=1
        combined+=",$entry"
    done
    kwriteconfig6 --file kwinrulesrc --group General --key Order "$combined"
    if [[ -n "$legacy" ]]; then
        # A stale non-empty legacy list takes precedence on 6.8; keep it in
        # sync so our rules are not silently dropped.
        kwriteconfig6 --file kwinrulesrc --group General --key rules "$combined"
    fi
}

configure_animations() {
    if ((DRY_RUN)); then
        log "Would disable desktop switching and all window animations"
        return
    fi
    log "Disabling desktop and window animations"

    local effect
    for effect in "${ANIMATION_EFFECTS[@]}"; do
        kwriteconfig6 --file kwinrc --group Plugins --key "${effect}Enabled" --type bool false
    done
    # Older KWin releases stored the same switches under kwin4_effect_*.
    for effect in "${ANIMATION_EFFECTS[@]}"; do
        kwriteconfig6 --file kwinrc --group Plugins --key "kwin4_effect_${effect}Enabled" --type bool false
    done

    # Global animation duration.  KWin and Plasma both honour this value.
    kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor 0

    # Belt and braces: if a Plasma component re-enables sliding popups, keep
    # their slide duration at zero instead of the default 50 ms.
    kwriteconfig6 --file kwinrc --group Effect-slidingpopups --key slideInDuration 0
    kwriteconfig6 --file kwinrc --group Effect-slidingpopups --key slideOutDuration 0

    # Native edge tiling/maximize live under [Windows] in KWin 6.x.
    # [ElectricBorders] only holds edge-activation and timing options, so
    # writing these keys there is a no-op.
    kwriteconfig6 --file kwinrc --group Windows --key ElectricBorderTiling --type bool false
    kwriteconfig6 --file kwinrc --group Windows --key ElectricBorderMaximize --type bool false
    kwriteconfig6 --file kwinrc --group ElectricBorders --key ElectricBorderTiling --delete 2>/dev/null || true
    kwriteconfig6 --file kwinrc --group ElectricBorders --key ElectricBorderMaximize --delete 2>/dev/null || true

    # Skip the Plasma splash screen; it is pure startup latency.
    kwriteconfig6 --file ksplashrc --group KSplash --key Engine none
}

install_focus_logger() {
    if ((DRY_RUN)); then
        log "Would install the Plasmarchy focus logger KWin script"
        return
    fi
    log "Installing Plasmarchy focus logger"
    install -d "$FOCUS_SCRIPT_DIR/contents/code"
    install -m 0644 "$ROOT/config/kwin/plasmarchy-focus/metadata.json" \
        "$FOCUS_SCRIPT_DIR/metadata.json"
    install -m 0644 "$ROOT/config/kwin/plasmarchy-focus/contents/code/main.js" \
        "$FOCUS_SCRIPT_DIR/contents/code/main.js"
    kwriteconfig6 --file kwinrc --group Plugins --key plasmarchy-focusEnabled --type bool true
}

load_focus_logger() {
    ((DRY_RUN)) && return 0
    log "Loading Plasmarchy focus logger in the running KWin"
    local loaded since i
    loaded="$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmarchy-focus 2>/dev/null || true)"
    if [[ "$loaded" == "true" ]]; then
        return 0
    fi

    since="$(date '+%Y-%m-%d %H:%M:%S.%N')"
    qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript \
        "$FOCUS_SCRIPT_DIR/contents/code/main.js" plasmarchy-focus >/dev/null 2>&1 || true
    qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1 || true

    for i in $(seq 1 10); do
        if journalctl --user --since "$since" --no-pager -o cat _COMM=kwin_wayland 2>/dev/null |
            grep -q 'PLASMARCHY-FOCUS-LOADED'; then
            return 0
        fi
        sleep 0.2
    done
    warn "focus logger did not report startup; Super+C/V will fall back to a slower query"
}

configure_ydotool() {
    if ((DRY_RUN)); then
        log "Would enable/start ydotoold and check /dev/uinput"
        return
    fi
    log "Configuring ydotool for Super+C/V"

    if ! command -v ydotool >/dev/null 2>&1; then
        warn "ydotool is not installed; Super+C/V/X will not work"
        return 0
    fi

    local unit=""
    if systemctl --user list-unit-files --no-legend 2>/dev/null | awk '{print $1}' |
        grep -qx 'ydotoold.service'; then
        unit=ydotoold.service
    elif systemctl --user list-unit-files --no-legend 2>/dev/null | awk '{print $1}' |
        grep -qx 'ydotool.service'; then
        unit=ydotool.service
    fi

    if [[ -n "$unit" ]]; then
        systemctl --user enable "$unit" >/dev/null 2>&1 ||
            warn "could not enable $unit"
        systemctl --user start "$unit" >/dev/null 2>&1 ||
            warn "could not start $unit"
    else
        warn "no ydotoold/ydotool user service found; start ydotoold manually"
    fi

    if [[ ! -e /dev/uinput ]]; then
        warn "/dev/uinput is missing; run 'sudo ./root-setup.sh' and log in again"
    elif [[ ! -r /dev/uinput || ! -w /dev/uinput ]]; then
        warn "current user cannot read/write /dev/uinput; run 'sudo ./root-setup.sh' and log in again"
    fi
}

install_konsole_config() {
    if ((SKIP_KONSOLE)); then
        log "Skipping Konsole configuration"
        return
    fi
    if ((DRY_RUN)); then
        log "Would install the Plasmarchy Konsole profile"
        return
    fi
    if ! command -v konsole >/dev/null 2>&1; then
        log "Konsole is not installed; skipping Konsole defaults"
        return
    fi
    log "Installing Konsole defaults"
    "$ROOT/scripts/install-konsole.sh" || warn "Konsole profile installation failed"
}

install_tmux_config() {
    ((SKIP_TMUX)) && { log "Skipping tmux configuration"; return; }
    if ((DRY_RUN)); then
        log "Would install the Omarchy tmux configuration"
        return
    fi
    if ! command -v tmux >/dev/null 2>&1; then
        warn "tmux is not installed; skipping tmux configuration"
        return
    fi
    log "Installing tmux configuration"
    "$ROOT/scripts/install-tmux.sh" || warn "tmux configuration failed"
}

install_dictation() {
    ((WITH_DICTATION)) || return 0
    if ((DRY_RUN)); then
        log "Would install Voxtype dictation (AUR + Whisper model)"
        return
    fi
    log "Installing Voxtype dictation"
    local args=()
    [[ "$PACKAGES" == "none" && "$INSTALL_SOFTWARE" == 0 ]] && args+=(--skip-packages)
    [[ -n "$DICTATION_LANGS" ]] && args+=(--languages "$DICTATION_LANGS")
    if ((DRY_RUN)); then
        args+=(--dry-run)
    fi
    "$ROOT/scripts/install-dictation.sh" "${args[@]}" ||
        warn "dictation installation failed; see the messages above"
}

write_xkb_layout_option() {
    if ((DRY_RUN)); then
        log "Would make Right Ctrl the only keyboard-layout switch in kxkbrc"
        return
    fi
    local options new option
    local -a kept parts
    options="$(kreadconfig6 --file kxkbrc --group Layout --key Options --default '' 2>/dev/null || true)"

    # Right Ctrl is the only layout switch.  Remove every other grp:* option
    # while preserving options such as lv3:ralt_switch (AltGr on Right Alt).
    IFS=',' read -r -a parts <<< "$options"
    for option in "${parts[@]}"; do
        [[ -n "$option" ]] || continue
        [[ "$option" == grp:* ]] && continue
        kept+=("$option")
    done
    kept+=("grp:rctrl_toggle")
    new="$(IFS=,; printf '%s' "${kept[*]}")"

    if [[ "$options" != "$new" ]]; then
        log "Setting kxkbrc layout options to: $new"
        kwriteconfig6 --file kxkbrc --group Layout --key Options "$new"
    fi
}

generate_desktops() {
    if ((SKIP_SHORTCUTS)); then return; fi
    if ((DRY_RUN)); then
        log "Would generate command .desktop wrappers"
        return
    fi
    log "Generating command wrappers"
    python3 "$RUNTIME/lib/shortcuts.py" gen-desktops \
        "$RUNTIME/commands.tsv" "$RUNTIME/shortcuts.tsv" \
        "$APPLICATIONS" "$RUNTIME/bin"
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    sleep 2
}

krohnkite_actions_loaded() {
    # Krohnkite's QML ShortcutHandler actions live in the "kwin" component.
    gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
        --method org.kde.KGlobalAccel.allActionsForComponent "['kwin']" 2>/dev/null |
        grep -q "'Krohnkite"
}

load_krohnkite() {
    ((SKIP_KROHNKITE)) && return 1
    ((DRY_RUN)) && return 1

    log "Loading Krohnkite in the running KWin"
    local loaded
    loaded="$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded krohnkite 2>/dev/null || true)"
    if [[ "$loaded" != "true" ]]; then
        qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript \
            "$KROHNKITE_DIR/contents/ui/main.qml" krohnkite >/dev/null 2>&1 || true
        qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null 2>&1 || true
    fi

    local i
    for i in $(seq 1 15); do
        if krohnkite_actions_loaded; then
            log "Krohnkite actions are registered"
            return 0
        fi
        sleep 1
    done
    warn "Krohnkite did not register its actions yet; a logout/login is required"
    return 1
}

install_krohnkite_fallback() {
    ((DRY_RUN)) && return
    log "Installing one-shot login fallback for Krohnkite shortcuts"
    mkdir -p "$CONFIG_HOME/autostart"
    cat > "$CONFIG_HOME/autostart/plasmarchy-apply-krohnkite.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Plasmarchy: apply Krohnkite shortcuts
Comment=One-shot fallback installed by deploy.sh
Exec=$RUNTIME/bin/plasmarchy-apply-krohnkite
Terminal=false
NoDisplay=true
StartupNotify=false
OnlyShowIn=KDE;
EOF
}

apply_shortcuts() {
    ((SKIP_SHORTCUTS)) && { log "Skipping shortcuts"; return; }
    if ((DRY_RUN)); then
        log "Would apply shortcut map"
        python3 "$ROOT/lib/shortcuts.py" lint "$ROOT/manifests/shortcuts.tsv"
        return
    fi

    log "Applying native and session shortcuts"
    python3 "$RUNTIME/lib/shortcuts.py" apply "$RUNTIME/shortcuts.tsv" --only native --allow-missing

    if ((SKIP_KROHNKITE)); then
        :
    elif krohnkite_actions_loaded; then
        log "Applying Krohnkite shortcuts"
        python3 "$RUNTIME/lib/shortcuts.py" apply "$RUNTIME/shortcuts.tsv" --only krohnkite --allow-missing
        rm -f "$CONFIG_HOME/autostart/plasmarchy-apply-krohnkite.desktop"
    else
        install_krohnkite_fallback
    fi

    log "Applying custom command shortcuts"
    local attempt
    for attempt in 1 2 3 4 5; do
        if python3 "$RUNTIME/lib/shortcuts.py" apply "$RUNTIME/shortcuts.tsv" --only custom --allow-missing; then
            break
        fi
        ((attempt < 5)) || die "could not register custom command shortcuts"
        sleep 2
        kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    done
}

unload_animation_effects() {
    ((DRY_RUN)) && return 0
    command -v qdbus6 >/dev/null 2>&1 || return 0
    local loaded effect
    loaded="$(qdbus6 org.kde.KWin /Effects \
        org.freedesktop.DBus.Properties.Get \
        org.kde.kwin.Effects loadedEffects 2>/dev/null || true)"
    [[ -n "$loaded" ]] || return 0
    for effect in "${ANIMATION_EFFECTS[@]}"; do
        if grep -qxF "$effect" <<<"$loaded"; then
            qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect \
                "$effect" >/dev/null 2>&1 || true
        fi
    done
}

reload_desktop() {
    ((DRY_RUN)) && return
    log "Reloading KWin configuration"
    qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
    unload_animation_effects
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
}

summary() {
    log "Done"
    cat <<EOF

Applied:
  - Krohnkite:  $([[ $SKIP_KROHNKITE == 1 ]] && echo skipped || echo "$KROHNKITE_VERSION, Tile -> Spiral -> Floating, gaps 10/5")
  - Theme:      $([[ $SKIP_THEME == 1 ]] && echo skipped || echo "plasmarchy (2 px border, no titlebar, server-side decoration)")
  - Rules:      server-side borders for normal windows; browser tiling fix
  - Focus:      $([[ $SKIP_FOCUS == 1 ]] && echo skipped || echo "focus follows mouse + mouse follows focus")
  - Animations: disabled (0 duration, no slide/fade/scale)
  - Clipboard:  Meta+C/X/V via ydotool, terminal-aware
  - Shortcuts:  $([[ $SKIP_SHORTCUTS == 1 ]] && echo skipped || echo "see manifests/shortcuts.tsv")
  - tmux:       $([[ $SKIP_TMUX == 1 ]] && echo skipped || echo "Omarchy config + tdl/tds/tdlm/tsl")
  - Dictation:  $([[ $WITH_DICTATION == 1 ]] && echo "Voxtype (hold F9 / Alt+Space toggle)" || echo "not installed; rerun with --with-dictation")
  - Runtime:    $RUNTIME
  - Backup:     $([[ $BACKUP == 1 ]] && echo "backups/plasma-*-pre-deploy" || echo "skipped")

Next steps:
  1. Log out and back in once.  This is required for the Aurorae theme,
     Right Ctrl layout switching, the input group, and (if it did not load
     live) Krohnkite.
  2. After login, test: Meta+Space, Meta+Return, Meta+Left/Right,
     Meta+L, Meta+T, Meta+1..9, Alt+Tab, Print, Meta+Ctrl+C.
  3. Test clipboard: Meta+C / Meta+V in a GUI app and in Konsole.  The
     focus logger is installed as the plasmarchy-focus KWin script.
  4. If Krohnkite shortcuts were deferred, the one-shot autostart applies
     them automatically at login.
  5. $([[ $WITH_DICTATION == 1 ]] && echo "Dictation is installed. Hold F9 to dictate, or press Alt+Space to toggle." || echo "Dictation is opt-in: rerun ./deploy.sh --with-dictation.")

Rollback:
  - Shortcuts/theme/config: ./install.sh restore latest --reload
  - Theme only:             /usr/lib/plasma-apply-aurorae org.kde.breeze
  - Krohnkite only:         kwriteconfig6 --file kwinrc --group Plugins --key krohnkiteEnabled --type bool false

EOF
}

preflight
if ((CHECK_ONLY)); then
    log "Preflight complete (--check); no changes made"
    exit 0
fi

log "Plan"
printf '  packages:     %s\n' "$PACKAGES"
printf '  backup:       %s\n' "$([[ $BACKUP == 1 ]] && echo yes || echo no)"
printf '  Krohnkite:    %s\n' "$([[ $SKIP_KROHNKITE == 1 ]] && echo skip || echo yes)"
printf '  theme:        %s\n' "$([[ $SKIP_THEME == 1 ]] && echo skip || echo yes)"
printf '  focus:        %s\n' "$([[ $SKIP_FOCUS == 1 ]] && echo skip || echo yes)"
printf '  shortcuts:    %s\n' "$([[ $SKIP_SHORTCUTS == 1 ]] && echo skip || echo yes)"
printf '  tmux:         %s\n' "$([[ $SKIP_TMUX == 1 ]] && echo skip || echo yes)"
printf '  dictation:    %s\n' "$([[ $WITH_DICTATION == 1 ]] && echo yes || echo no)"

if ((!ASSUME_YES)); then
    [[ -t 0 ]] || die "no terminal for confirmation; rerun with --yes"
    read -r -p "Apply this plan? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

create_backup
install_packages
install_runtime_files
install_krohnkite
write_krohnkite_config
configure_window_rules
configure_animations
configure_focus
install_theme
install_focus_logger
write_xkb_layout_option
install_tmux_config
install_konsole_config
install_dictation
generate_desktops

if ((SKIP_KROHNKITE)); then
    :
elif load_krohnkite; then
    :
else
    install_krohnkite_fallback
fi

load_focus_logger
configure_ydotool
apply_shortcuts
reload_desktop
summary

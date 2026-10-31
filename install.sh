#!/usr/bin/env bash
# One-command Plasmarchy entry point for Arch/CachyOS + KDE Plasma 6.
#
# Usage:
#   ./install.sh [command] [options]
#
# Commands:
#   install   run the full guided installation (default)
#   backup    run scripts/create-backup.sh
#   restore   run scripts/restore-plasma.sh
#   deploy    run scripts/deploy.sh in the current Plasma session
#
# install options:
#   --dry-run             Show what would happen, change nothing
#   --yes, -y             Do not ask for confirmation
#   --packages MODE       required or all
#   --with-dictation      Install and configure Voxtype
#   --dictation-languages LANGS
#                         Auto-detected by default
#   --restore-backup SNAP Restore a Plasma/KWin snapshot before deploy
#   --skip-root           Do not run root-setup.sh (packages already installed)
#   --skip-config         Do not copy config/plasma/ into ~/.config
#   --skip-deploy         Do not run deploy.sh
#   --skip-software       Alias for --packages none
#   --no-backup           Do not create a pre-install snapshot
#   --reset-plasma        Remove core Plasma configs so KDE regenerates defaults on next login
#   -h, --help            Show this help
#
# The script must run as the desktop user.  Subcommands pass their
# arguments through unchanged, e.g.:
#   ./install.sh backup --tag before-experiment
#   ./install.sh restore latest --reload
#   ./install.sh deploy --check

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
PLASMA_SNAPSHOT="$ROOT/config/plasma"

DRY_RUN=0
ASSUME_YES=0
PACKAGES="required"
WITH_DICTATION=0
DICTATION_LANGUAGES=""
SKIP_ROOT=0
SKIP_CONFIG=0
SKIP_DEPLOY=0
BACKUP=1
RESET_PLASMA=0
PRESERVE_DOCK_LAUNCHERS=1
EXTRACTED_DOCK_LAUNCHERS=""
OVERWRITE_PANEL_LAYOUT=0

log() { printf '\n==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,48p' "$0"
}

COMMAND="install"
if (($#)) && [[ "$1" == "install" || "$1" == "backup" || "$1" == "restore" || "$1" == "deploy" ]]; then
    COMMAND="$1"
    shift
fi

case "$COMMAND" in
    backup)
        [[ -x "$ROOT/scripts/create-backup.sh" ]] || die "create-backup.sh is missing"
        exec "$ROOT/scripts/create-backup.sh" "$@"
        ;;
    restore)
        [[ -x "$ROOT/scripts/restore-plasma.sh" ]] || die "restore-plasma.sh is missing"
        exec "$ROOT/scripts/restore-plasma.sh" "$@"
        ;;
    deploy)
        [[ -x "$ROOT/scripts/deploy.sh" ]] || die "deploy.sh is missing"
        exec "$ROOT/scripts/deploy.sh" "$@"
        ;;
esac

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        --packages)
            [[ $# -ge 2 ]] || die "--packages requires required or all"
            PACKAGES="$2"
            shift 2
            ;;
        --skip-software) PACKAGES="none"; shift ;;
        --with-dictation) WITH_DICTATION=1; shift ;;
        --dictation-languages)
            [[ $# -ge 2 ]] || die "--dictation-languages requires a value"
            DICTATION_LANGUAGES="$2"; WITH_DICTATION=1; shift 2
            ;;
        --restore-backup)
            [[ $# -ge 2 ]] || die "--restore-backup requires a snapshot name or path"
            RESTORE_BACKUP_SNAPSHOT="$2"; shift 2
            ;;
        --skip-root) SKIP_ROOT=1; shift ;;
        --skip-config) SKIP_CONFIG=1; shift ;;
        --no-preserve-dock) PRESERVE_DOCK_LAUNCHERS=0; shift ;;
        --overwrite-panel-layout) PRESERVE_DOCK_LAUNCHERS=0; shift ;;
        --skip-deploy) SKIP_DEPLOY=1; shift ;;
        --no-backup) BACKUP=0; shift ;;
        --reset-plasma) RESET_PLASMA=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

case "$PACKAGES" in
    required|all|none) ;;
    *) die "invalid --packages value: $PACKAGES (use required, all or none)" ;;
esac

if ((RESET_PLASMA)); then
    if ((!ASSUME_YES && !DRY_RUN)); then
        [[ -t 0 ]] || die "no terminal for confirmation; rerun with --yes"
        read -r -p "Reset Plasma settings to defaults? [y/N] " reply
        [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
    fi
    if ((BACKUP && !DRY_RUN)); then
        log "Creating a safety backup before resetting"
        "$ROOT/scripts/create-backup.sh" --tag pre-reset
    elif ((DRY_RUN)); then
        log "Would create a safety backup before resetting"
    fi
    if ((DRY_RUN)); then
        log "Would remove core Plasma settings; KDE will regenerate defaults on the next login"
        exit 0
    fi
    log "Removing core Plasma settings"
    rm -f         "$CONFIG_HOME/kdeglobals"         "$CONFIG_HOME/kwinrc"         "$CONFIG_HOME/kglobalshortcutsrc"         "$CONFIG_HOME/kxkbrc"         "$CONFIG_HOME/plasma-localerc"         "$CONFIG_HOME/plasmarc"         "$CONFIG_HOME/powerdevilrc"         "$CONFIG_HOME/powermanagementprofilesrc"         "$CONFIG_HOME/kcminputrc"         "$CONFIG_HOME/krunnerrc"         "$CONFIG_HOME/ksplashrc"         "$CONFIG_HOME/plasma-org.kde.plasma.desktop-appletsrc"         "$CONFIG_HOME/konsolerc"
    rm -rf "$CONFIG_HOME/plasma" "$HOME/.cache/plasmashell" "$HOME/.cache/ksycoca*" 2>/dev/null || true
    echo "Plasma defaults will be regenerated after you log out and log in again."
    exit 0
fi

[[ $EUID -ne 0 ]] || die "run this as your desktop user, not as root"
[[ -f "$ROOT/scripts/root-setup.sh" ]] || die "root-setup.sh is missing"
[[ -f "$ROOT/scripts/deploy.sh" ]] || die "deploy.sh is missing"
[[ -d "$PLASMA_SNAPSHOT" ]] || die "config/plasma/ is missing"
[[ "$PACKAGES" == "required" || "$PACKAGES" == "all" ]] && INSTALL_SOFTWARE=1

if (( ! SKIP_ROOT )) && ! command -v sudo >/dev/null 2>&1; then
    die "sudo not found; install sudo or rerun with --skip-root"
fi

log "Plasmarchy install plan"
printf '  repository:  %s\n' "$ROOT"
printf '  packages:    %s\n' "$PACKAGES"
printf '  dictation:   %s\n' "$([[ $WITH_DICTATION == 1 ]] && echo yes || echo no)"
printf '  root setup:  %s\n' "$([[ $SKIP_ROOT == 1 ]] && echo skip || echo yes)"
printf '  config copy: %s\n' "$([[ $SKIP_CONFIG == 1 ]] && echo skip || echo yes)"
printf '  deploy:      %s\n' "$([[ $SKIP_DEPLOY == 1 ]] && echo skip || echo yes)"
printf '  backup:      %s\n' "$([[ $BACKUP == 1 ]] && echo yes || echo no)"

if ((!ASSUME_YES && !DRY_RUN)); then
    [[ -t 0 ]] || die "no terminal for confirmation; rerun with --yes"
    read -r -p "Apply this plan? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

if ((SKIP_ROOT)); then
    log "Skipping root setup"
else
    root_args=(--user "$USER" --packages "$PACKAGES")
    ((WITH_DICTATION)) && root_args+=(--with-dictation)
    [[ -n "$DICTATION_LANGUAGES" ]] && root_args+=(--dictation-languages "$DICTATION_LANGUAGES")
    ((DRY_RUN)) && root_args+=(--dry-run)

    if ((DRY_RUN)); then
        log "Would run root setup"
        printf '  sudo %q' "$ROOT/scripts/root-setup.sh"
        printf ' %q' "${root_args[@]}"
        printf '\n'
    else
        log "Running root setup (packages, LocalSend, /dev/uinput)"
        sudo "$ROOT/scripts/root-setup.sh" "${root_args[@]}"
    fi
fi

if ((SKIP_CONFIG)); then
    log "Skipping Plasma config snapshot"
else
    if ((BACKUP && !DRY_RUN)); then
        log "Creating pre-install backup"
        "$ROOT/scripts/create-backup.sh" --tag pre-install
    elif ((DRY_RUN)); then
        log "Would create pre-install backup"
    fi

    log "Copying Plasma config snapshot"
    config_files=(
        kdeglobals
        plasma-org.kde.plasma.desktop-appletsrc
        kwinrc
        kglobalshortcutsrc
        kxkbrc
        plasma-localerc
        plasmarc
        powerdevilrc
        powermanagementprofilesrc
        kcminputrc
        krunnerrc
        ksplashrc
    )
    for file in "${config_files[@]}"; do
        if [[ ! -f "$PLASMA_SNAPSHOT/$file" ]]; then
            warn "snapshot file is missing: $file"
            continue
        fi
        if ((DRY_RUN)); then
            if [[ "$file" == "plasma-org.kde.plasma.desktop-appletsrc" && -f "$CONFIG_HOME/$file" && "$PRESERVE_DOCK_LAUNCHERS" == "1" ]]; then
                printf '  would install %s -> %s, preserving dock apps from the existing layout\n' "$file" "$CONFIG_HOME/$file"
            else
                printf '  would install %s -> %s\n' "$file" "$CONFIG_HOME/$file"
            fi
            continue
        fi

        if [[ "$file" == "plasma-org.kde.plasma.desktop-appletsrc" && -f "$CONFIG_HOME/$file" && "$PRESERVE_DOCK_LAUNCHERS" == "1" ]]; then
            cp -p "$CONFIG_HOME/$file" "$CONFIG_HOME/$file.plasmarchy-user-backup" 2>/dev/null || true
            EXTRACTED_DOCK_LAUNCHERS="$(grep '^launchers=' "$CONFIG_HOME/$file.plasmarchy-user-backup" | tail -n 1 || true)"
        else
            EXTRACTED_DOCK_LAUNCHERS=""
        fi

        mkdir -p "$CONFIG_HOME"
        install -m 0644 "$PLASMA_SNAPSHOT/$file" "$CONFIG_HOME/$file"

        if [[ "$file" == "plasma-org.kde.plasma.desktop-appletsrc" && "$PRESERVE_DOCK_LAUNCHERS" == "1" && -n "$EXTRACTED_DOCK_LAUNCHERS" ]]; then
            python3 - "$CONFIG_HOME/$file" "$EXTRACTED_DOCK_LAUNCHERS" <<'PYTHON'
import sys
path, value = sys.argv[1], sys.argv[2]
lines = open(path).read().splitlines(keepends=True)
done = False
for i, line in enumerate(lines):
    if line.startswith('launchers='):
        lines[i] = value + ('' if value.endswith('\n') else '\n')
        done = True
        break
if not done:
    lines.append(value + ('' if value.endswith('\n') else '\n'))
open(path, 'w').write(''.join(lines))
PYTHON
            printf '  preserved dock apps: %s\n' "$EXTRACTED_DOCK_LAUNCHERS"
        fi

        printf '  %s\n' "$file"
    done
fi

if (( ! SKIP_DEPLOY )); then
    if ! command -v qdbus6 >/dev/null 2>&1 ||
        ! qdbus6 org.kde.KWin /KWin >/dev/null 2>&1; then
        warn "Plasma/KWin session not detected; skipping deploy.sh"
        warn "log in to Plasma and run: ./install.sh deploy --skip-packages --yes"
        SKIP_DEPLOY=1
    fi
fi

if (( ! SKIP_DEPLOY )); then
    deploy_args=(--skip-packages --no-backup --yes)
    ((WITH_DICTATION)) && deploy_args+=(--with-dictation)
    [[ -n "$DICTATION_LANGUAGES" ]] && deploy_args+=(--dictation-languages "$DICTATION_LANGUAGES")
    [[ -n "${RESTORE_BACKUP_SNAPSHOT:-}" ]] && deploy_args+=(--restore-backup "$RESTORE_BACKUP_SNAPSHOT")
    ((DRY_RUN)) && deploy_args+=(--dry-run)

    if ((DRY_RUN)); then
        log "Would run deploy.sh"
        printf '  %q' "$ROOT/scripts/deploy.sh"
        printf ' %q' "${deploy_args[@]}"
        printf '\n'
    else
        log "Deploying user configuration"
        "$ROOT/scripts/deploy.sh" "${deploy_args[@]}"
    fi
fi

log "Install complete"
cat <<'EOF'

Log out and back in once.  This applies the input group for ydotool,
the Aurorae theme, the focus logger, and any shortcuts that could not
be registered in the current session.

Commands after login:
  ./install.sh deploy --check
  ./install.sh backup --tag before-experiment
  ./install.sh restore latest --reload
EOF

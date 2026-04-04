#!/usr/bin/env bash
# uninstall.sh - Remove Brik CLI from the system
# Usage: bash scripts/uninstall.sh [--force]
set -euo pipefail

BRIK_HOME="${BRIK_HOME:-${HOME}/.brik}"
FORCE=false

for arg in "$@"; do
    case "$arg" in
        --force) FORCE=true ;;
        *) printf 'unknown option: %s\n' "$arg" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info() {
    printf '  %s\n' "$1"
}

confirm() {
    if [ "$FORCE" = true ]; then
        return 0
    fi
    printf '%s [y/N] ' "$1"
    local answer=""
    read -r answer
    case "$answer" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Find and remove shim
# ---------------------------------------------------------------------------

remove_shim() {
    local shim_path=""
    local found=false

    for candidate in "/usr/local/bin/brik" "${HOME}/.local/bin/brik"; do
        if [ -f "$candidate" ]; then
            # Check if it is the shim (contains "brik-shim" or BRIK_HOME reference, not a symlink to bin/brik)
            if [ -L "$candidate" ]; then
                info "skipping symlink at ${candidate} (contributor install)"
                continue
            fi
            shim_path="$candidate"
            found=true
            break
        fi
    done

    if [ "$found" = true ]; then
        info "removing shim: ${shim_path}"
        rm -f "$shim_path"
    else
        info "no shim found in /usr/local/bin or ~/.local/bin"
    fi
}

# ---------------------------------------------------------------------------
# Remove runtime
# ---------------------------------------------------------------------------

remove_runtime() {
    if [ -d "$BRIK_HOME" ]; then
        info "removing runtime: ${BRIK_HOME}"
        rm -rf "$BRIK_HOME"
    else
        info "runtime directory not found: ${BRIK_HOME}"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    printf 'brik uninstaller\n'
    printf '================\n'

    if ! confirm "Remove Brik from your system?"; then
        info "cancelled"
        exit 0
    fi

    remove_shim
    remove_runtime

    info ""
    info "brik has been removed"
}

main

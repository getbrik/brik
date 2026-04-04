#!/usr/bin/env bash
# install.sh - Universal installer for Brik CLI
# Usage: curl -fsSL https://raw.githubusercontent.com/getbrik/brik/main/scripts/install.sh | bash
#
# Environment variables:
#   BRIK_HOME       Override installation directory (default: ~/.brik)
#   BRIK_VERSION    Install a specific version tag (default: latest)
set -euo pipefail

BRIK_REPO="https://github.com/getbrik/brik.git"
BRIK_HOME="${BRIK_HOME:-${HOME}/.brik}"
BRIK_VERSION="${BRIK_VERSION:-}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info() {
    printf '  %s\n' "$1"
}

error() {
    printf 'error: %s\n' "$1" >&2
}

die() {
    error "$1"
    exit 1
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

check_prerequisites() {
    local missing=0

    if ! command -v git >/dev/null 2>&1; then
        error "git is required but not found"
        missing=1
    fi

    if ! command -v bash >/dev/null 2>&1; then
        error "bash is required but not found"
        missing=1
    fi

    if [ "$missing" -ne 0 ]; then
        die "install the missing prerequisites and try again"
    fi
}

# ---------------------------------------------------------------------------
# Detect install directory for the shim
# ---------------------------------------------------------------------------

detect_shim_dir() {
    if [ -w "/usr/local/bin" ]; then
        printf '/usr/local/bin'
    else
        local local_bin="${HOME}/.local/bin"
        mkdir -p "$local_bin"
        printf '%s' "$local_bin"
    fi
}

# ---------------------------------------------------------------------------
# Resolve latest tag from remote
# ---------------------------------------------------------------------------

resolve_version() {
    local version="$1"

    if [ -n "$version" ]; then
        printf '%s' "$version"
        return
    fi

    # Fetch latest tag from the remote (or local clone)
    local latest=""
    if [ -d "${BRIK_HOME}/.git" ]; then
        latest="$(git -C "${BRIK_HOME}" describe --tags --abbrev=0 origin/main 2>/dev/null)" || true
    fi

    if [ -z "$latest" ]; then
        # Fallback: list remote tags and pick the latest semver
        latest="$(git ls-remote --tags --sort=-v:refname "$BRIK_REPO" 'v*' 2>/dev/null \
            | head -n 1 \
            | sed 's|.*refs/tags/||; s|\^{}||')" || true
    fi

    if [ -z "$latest" ]; then
        printf 'main'
    else
        printf '%s' "$latest"
    fi
}

# ---------------------------------------------------------------------------
# Clone or update
# ---------------------------------------------------------------------------

install_runtime() {
    local version="$1"

    if [ -d "${BRIK_HOME}/.git" ]; then
        info "updating existing installation in ${BRIK_HOME}..."
        git -C "${BRIK_HOME}" fetch --depth 1 --tags origin 2>/dev/null || true
        git -C "${BRIK_HOME}" fetch --depth 1 origin main 2>/dev/null || true
    else
        if [ -d "${BRIK_HOME}" ]; then
            die "${BRIK_HOME} exists but is not a git repository. Remove it first or set BRIK_HOME."
        fi
        info "cloning brik into ${BRIK_HOME}..."
        git clone --depth 1 "$BRIK_REPO" "$BRIK_HOME"
    fi

    # Checkout the target version
    if [ "$version" != "main" ]; then
        git -C "${BRIK_HOME}" checkout "$version" 2>/dev/null \
            || die "version ${version} not found. Check available tags with: git ls-remote --tags ${BRIK_REPO}"
    fi
}

# ---------------------------------------------------------------------------
# Install shim
# ---------------------------------------------------------------------------

install_shim() {
    local shim_dir="$1"
    local shim_path="${shim_dir}/brik"
    local source_shim="${BRIK_HOME}/bin/brik-shim"

    if [ -L "$shim_path" ]; then
        info "replacing existing symlink at ${shim_path}"
    fi

    cp "$source_shim" "$shim_path"
    chmod +x "$shim_path"

    info "shim installed to ${shim_path}"

    # Warn if shim_dir is not in PATH
    case ":${PATH}:" in
        *":${shim_dir}:"*) ;;
        *)
            info ""
            info "WARNING: ${shim_dir} is not in your PATH"
            info "Add this to your shell profile:"
            info "  export PATH=\"${shim_dir}:\$PATH\""
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    printf 'brik installer\n'
    printf '==============\n'

    check_prerequisites

    local version=""
    version="$(resolve_version "$BRIK_VERSION")"
    info "version: ${version}"

    install_runtime "$version"

    local shim_dir=""
    shim_dir="$(detect_shim_dir)"
    install_shim "$shim_dir"

    printf '\n'

    # Verify installation
    local installed_version=""
    installed_version="$("${shim_dir}/brik" version 2>/dev/null | head -n 1)" || true

    if [ -n "$installed_version" ]; then
        info "installed: ${installed_version}"
    else
        info "installed brik to ${BRIK_HOME}"
    fi

    info ""
    info "run 'brik doctor' to check stack prerequisites"
}

main

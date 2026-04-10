#!/usr/bin/env bash
# @module _deps
# @description Centralized dependency installation for stages.
# Provides _brik.install_deps to avoid duplicating install logic in each stage.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_DEPS_LOADED:-}" ]] && return 0
_BRIK_CORE_DEPS_LOADED=1

# Install project dependencies for a given stage mode.
# Usage: _brik.install_deps <workspace> <mode>
# Modes:
#   test - dev extras with fallback to runtime deps (for test stage)
#   dev  - dev dependencies only (for lint/format tools)
#   scan - runtime dependencies only (for security scanning)
_brik.install_deps() {
    local workspace="$1"
    local mode="${2:-scan}"
    local stack="${BRIK_BUILD_STACK:-}"

    case "$stack" in
        node)
            _brik._install_deps_node "$workspace"
            ;;
        python)
            _brik._install_deps_python "$workspace" "$mode"
            ;;
        rust)
            [[ "$mode" == "dev" ]] && _brik._install_deps_rust
            ;;
        dotnet)
            [[ "$mode" == "test" ]] && _brik._install_deps_dotnet "$workspace"
            ;;
    esac
}

_brik._install_deps_node() {
    local workspace="$1"
    if [[ ! -d "${workspace}/node_modules" ]]; then
        log.info "installing node dependencies"
        # best-effort: install may fail if package.json missing or network down
        (cd "$workspace" && npm ci --ignore-scripts 2>/dev/null) || true
    fi
}

_brik._install_deps_python() {
    local workspace="$1" mode="$2"
    export PATH="${HOME}/.local/bin:${PATH}"
    local pip_flags="--quiet"
    if pip install --help 2>&1 | grep -q -- '--break-system-packages'; then
        pip_flags="$pip_flags --break-system-packages"
    fi

    # best-effort: pip install may fail (missing extras, network, etc.)
    case "$mode" in
        test)
            if [[ -f "${workspace}/pyproject.toml" ]]; then
                log.info "installing python dependencies for test"
                # shellcheck disable=SC2086
                (cd "$workspace" && pip install -e ".[dev]" $pip_flags 2>/dev/null) || \
                (cd "$workspace" && pip install -e . $pip_flags 2>/dev/null) || true
            elif [[ -f "${workspace}/requirements.txt" ]]; then
                log.info "installing python dependencies for test"
                # shellcheck disable=SC2086
                (cd "$workspace" && pip install -r requirements.txt $pip_flags 2>/dev/null) || true
            fi
            ;;
        dev)
            if [[ -f "${workspace}/pyproject.toml" ]]; then
                log.info "installing python dev dependencies"
                # shellcheck disable=SC2086
                (cd "$workspace" && pip install -e ".[dev]" $pip_flags 2>/dev/null) || true
            elif [[ -f "${workspace}/requirements-dev.txt" ]]; then
                log.info "installing python dev dependencies"
                # shellcheck disable=SC2086
                (cd "$workspace" && pip install -r requirements-dev.txt $pip_flags 2>/dev/null) || true
            fi
            ;;
        scan)
            if [[ -f "${workspace}/pyproject.toml" ]]; then
                # shellcheck disable=SC2086
                (cd "$workspace" && pip install . $pip_flags 2>/dev/null) || true
            elif [[ -f "${workspace}/requirements.txt" ]]; then
                # shellcheck disable=SC2086
                (cd "$workspace" && pip install -r requirements.txt $pip_flags 2>/dev/null) || true
            fi
            ;;
    esac
}

_brik._install_deps_rust() {
    if command -v rustup >/dev/null 2>&1; then
        if ! command -v cargo-clippy >/dev/null 2>&1; then
            log.info "installing rustup component: clippy"
            # best-effort: component may already be installed or unavailable
            rustup component add clippy 2>/dev/null || true
        fi
        if ! command -v rustfmt >/dev/null 2>&1; then
            log.info "installing rustup component: rustfmt"
            rustup component add rustfmt 2>/dev/null || true  # same as clippy above
        fi
    fi
}

_brik._install_deps_dotnet() {
    local workspace="$1"
    log.info "restoring dotnet dependencies"
    # best-effort: restore may fail if no .csproj found
    (cd "$workspace" && dotnet restore --verbosity quiet 2>/dev/null) || true
}

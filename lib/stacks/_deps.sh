#!/usr/bin/env bash
# @module _deps
# @description Centralized dependency installation for stages.
# Provides stacks.install_deps to avoid duplicating install logic in each stage.

# Guard against double-sourcing
[[ -n "${_BRIK_STACKS_DEPS_LOADED:-}" ]] && return 0
_BRIK_STACKS_DEPS_LOADED=1

# Install project dependencies for a given stage mode.
# Usage: stacks.install_deps <workspace> <mode>
# Modes:
#   test - dev extras with fallback to runtime deps (for test stage)
#   dev  - dev dependencies only (for lint/format tools)
#   scan - runtime dependencies only (for security scanning)
stacks.install_deps() {
    local workspace="$1"
    local mode="${2:-scan}"
    local stack="${BRIK_BUILD_STACK:-}"

    case "$stack" in
        node)
            _brik._install_deps_node "$workspace" || return $?
            ;;
        python)
            _brik._install_deps_python "$workspace" "$mode" || return $?
            ;;
        rust)
            [[ "$mode" == "dev" ]] && { _brik._install_deps_rust || return $?; }
            ;;
        dotnet)
            [[ "$mode" == "test" ]] && { _brik._install_deps_dotnet "$workspace" || return $?; }
            ;;
    esac
    return 0
}

# Per-stack helpers below propagate exit codes:
#   - skip silently (return 0) when there is nothing to install (no package
#     manifest, mode irrelevant, etc.).
#   - return BRIK_EXIT_MISSING_DEP when the install command itself fails so
#     the caller (lint/test/scan) surfaces a real failure instead of
#     continuing with broken dependencies.
# Output (stdout/stderr) of the install command is left visible so the user
# sees the native error message; we do not redirect it to /dev/null.

_brik._install_deps_node() {
    local workspace="$1"
    [[ -f "${workspace}/package.json" ]] || return 0
    [[ -d "${workspace}/node_modules" ]] && return 0
    # Some runner images (scanner, analysis) do not ship npm. Skip silently
    # when the tool is missing -- those stages do not need installed deps.
    command -v npm >/dev/null 2>&1 || return 0

    log.info "installing node dependencies"
    if (cd "$workspace" && npm ci --ignore-scripts); then
        return 0
    fi
    log.error "npm ci failed in $workspace"
    return "$BRIK_EXIT_MISSING_DEP"
}

_brik._install_deps_python() {
    local workspace="$1" mode="$2"
    export PATH="${HOME}/.local/bin:${PATH}"
    local pip_flags="--quiet"
    if pip install --help 2>&1 | grep -q -- '--break-system-packages'; then
        pip_flags="$pip_flags --break-system-packages"
    fi

    case "$mode" in
        test)
            if [[ -f "${workspace}/pyproject.toml" ]]; then
                log.info "installing python dependencies for test"
                # Try dev extras first; fall back to plain install when [dev]
                # is not declared. Only the second attempt failing is fatal.
                # shellcheck disable=SC2086
                (cd "$workspace" && pip install -e ".[dev]" $pip_flags) && return 0
                # shellcheck disable=SC2086
                if (cd "$workspace" && pip install -e . $pip_flags); then
                    return 0
                fi
                log.error "pip install failed in $workspace"
                return "$BRIK_EXIT_MISSING_DEP"
            elif [[ -f "${workspace}/requirements.txt" ]]; then
                log.info "installing python dependencies for test"
                # shellcheck disable=SC2086
                if (cd "$workspace" && pip install -r requirements.txt $pip_flags); then
                    return 0
                fi
                log.error "pip install -r requirements.txt failed in $workspace"
                return "$BRIK_EXIT_MISSING_DEP"
            fi
            return 0
            ;;
        dev)
            if [[ -f "${workspace}/pyproject.toml" ]]; then
                log.info "installing python dev dependencies"
                # shellcheck disable=SC2086
                if (cd "$workspace" && pip install -e ".[dev]" $pip_flags); then
                    return 0
                fi
                log.error "pip install -e .[dev] failed in $workspace"
                return "$BRIK_EXIT_MISSING_DEP"
            elif [[ -f "${workspace}/requirements-dev.txt" ]]; then
                log.info "installing python dev dependencies"
                # shellcheck disable=SC2086
                if (cd "$workspace" && pip install -r requirements-dev.txt $pip_flags); then
                    return 0
                fi
                log.error "pip install -r requirements-dev.txt failed in $workspace"
                return "$BRIK_EXIT_MISSING_DEP"
            fi
            return 0
            ;;
        scan)
            if [[ -f "${workspace}/pyproject.toml" ]]; then
                # shellcheck disable=SC2086
                if (cd "$workspace" && pip install . $pip_flags); then
                    return 0
                fi
                log.error "pip install . failed in $workspace"
                return "$BRIK_EXIT_MISSING_DEP"
            elif [[ -f "${workspace}/requirements.txt" ]]; then
                # shellcheck disable=SC2086
                if (cd "$workspace" && pip install -r requirements.txt $pip_flags); then
                    return 0
                fi
                log.error "pip install -r requirements.txt failed in $workspace"
                return "$BRIK_EXIT_MISSING_DEP"
            fi
            return 0
            ;;
    esac
    return 0
}

_brik._install_deps_rust() {
    command -v rustup >/dev/null 2>&1 || return 0
    local rc=0
    if ! command -v cargo-clippy >/dev/null 2>&1; then
        log.info "installing rustup component: clippy"
        rustup component add clippy || rc="$BRIK_EXIT_MISSING_DEP"
    fi
    if ! command -v rustfmt >/dev/null 2>&1; then
        log.info "installing rustup component: rustfmt"
        rustup component add rustfmt || rc="$BRIK_EXIT_MISSING_DEP"
    fi
    if [[ "$rc" -ne 0 ]]; then
        log.error "rustup component add failed"
        return "$rc"
    fi
    return 0
}

_brik._install_deps_dotnet() {
    local workspace="$1"
    log.info "restoring dotnet dependencies"
    if (cd "$workspace" && dotnet restore --verbosity quiet); then
        return 0
    fi
    log.error "dotnet restore failed in $workspace"
    return "$BRIK_EXIT_MISSING_DEP"
}

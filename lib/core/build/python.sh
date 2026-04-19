#!/usr/bin/env bash
# @module build.python
# @requires pip or poetry or pipenv or uv
# @description Build Python projects (pip, poetry, pipenv, uv).

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_BUILD_PYTHON_LOADED:-}" ]] && return 0
_BRIK_CORE_BUILD_PYTHON_LOADED=1

# Detect the package manager from marker files.
# Prints uv, pip, poetry, or pipenv on stdout.
_build.python._detect_pm() {
    local workspace="$1"

    if [[ -f "${workspace}/uv.lock" ]]; then
        printf 'uv'
    elif [[ -f "${workspace}/poetry.lock" ]]; then
        printf 'poetry'
    elif grep -q '\[tool\.poetry\]' "${workspace}/pyproject.toml" 2>/dev/null; then
        printf 'poetry'
    elif [[ -f "${workspace}/Pipfile" ]]; then
        printf 'pipenv'
    else
        printf 'pip'
    fi
}

# Install dependencies and build.
# Usage: build.python.run <workspace> [--tool <uv|pip|poetry|pipenv>]
build.python.run() {
    local workspace="$1"
    shift
    local pm=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tool) pm="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    runtime.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    # Need at least one Python project marker
    if [[ ! -f "${workspace}/pyproject.toml" && ! -f "${workspace}/setup.py" && ! -f "${workspace}/Pipfile" ]]; then
        log.error "no Python project file found in workspace: $workspace"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    # Auto-detect package manager if not specified
    [[ -z "$pm" ]] && pm="$(_build.python._detect_pm "$workspace")"

    case "$pm" in
        uv)
            runtime.require_tool uv || return "$BRIK_EXIT_MISSING_DEP"
            log.info "building with uv"
            (cd "$workspace" && uv sync && uv build) || {
                log.error "build failed"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
            ;;
        pip)
            runtime.require_tool pip || return "$BRIK_EXIT_MISSING_DEP"
            log.info "building with pip"
            # Install project + deps so test/quality stages have them available
            local pip_install_flags="--quiet"
            if pip install --help 2>&1 | grep -q -- '--break-system-packages'; then
                pip_install_flags="$pip_install_flags --break-system-packages"
            fi
            # shellcheck disable=SC2086
            (cd "$workspace" && pip install . $pip_install_flags) || log.warn "pip install . failed (non-fatal)"
            if (cd "$workspace" && python -m build) 2>/dev/null; then
                : # python -m build succeeded
            elif (cd "$workspace" && pip wheel . -w dist/) 2>/dev/null; then
                : # pip wheel fallback succeeded
            else
                log.error "build failed"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            fi
            ;;
        poetry)
            runtime.require_tool poetry || return "$BRIK_EXIT_MISSING_DEP"
            log.info "building with poetry"
            (cd "$workspace" && poetry install && poetry build) || {
                log.error "build failed"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
            ;;
        pipenv)
            runtime.require_tool pipenv || return "$BRIK_EXIT_MISSING_DEP"
            log.info "building with pipenv"
            (cd "$workspace" && pipenv install) || {
                log.error "dependency install failed"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
            if (cd "$workspace" && pipenv run python -m build) 2>/dev/null; then
                : # pipenv run python -m build succeeded
            elif (cd "$workspace" && pipenv run pip wheel . -w dist/) 2>/dev/null; then
                : # pipenv run pip wheel fallback succeeded
            else
                log.error "build failed"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            fi
            ;;
        *)
            log.error "unsupported Python package manager: $pm"
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac

    log.info "build completed successfully"
    return 0
}

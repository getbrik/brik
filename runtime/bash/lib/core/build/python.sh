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
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    runtime.require_dir "$workspace" || return 6

    # Need at least one Python project marker
    if [[ ! -f "${workspace}/pyproject.toml" && ! -f "${workspace}/setup.py" && ! -f "${workspace}/Pipfile" ]]; then
        log.error "no Python project file found in workspace: $workspace"
        return 6
    fi

    # Auto-detect package manager if not specified
    [[ -z "$pm" ]] && pm="$(_build.python._detect_pm "$workspace")"

    case "$pm" in
        uv)
            runtime.require_tool uv || return 3
            log.info "building with uv"
            (cd "$workspace" && uv sync && uv build) || {
                log.error "build failed"
                return 5
            }
            ;;
        pip)
            runtime.require_tool pip || return 3
            log.info "building with pip"
            if [[ -f "${workspace}/pyproject.toml" ]]; then
                (cd "$workspace" && pip install -e .) || {
                    log.error "build failed"
                    return 5
                }
            else
                (cd "$workspace" && pip install .) || {
                    log.error "build failed"
                    return 5
                }
            fi
            ;;
        poetry)
            runtime.require_tool poetry || return 3
            log.info "building with poetry"
            (cd "$workspace" && poetry install && poetry build) || {
                log.error "build failed"
                return 5
            }
            ;;
        pipenv)
            runtime.require_tool pipenv || return 3
            log.info "building with pipenv"
            (cd "$workspace" && pipenv install) || {
                log.error "build failed"
                return 5
            }
            ;;
        *)
            log.error "unsupported Python package manager: $pm"
            return 7
            ;;
    esac

    log.info "build completed successfully"
    return 0
}

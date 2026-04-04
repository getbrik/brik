#!/usr/bin/env bash
# @module config.python
# @description Python stack defaults and version export.
#
# Loaded via: brik.use config.python

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_CONFIG_PYTHON_LOADED:-}" ]] && return 0
_BRIK_CORE_CONFIG_PYTHON_LOADED=1

# Return the default value for a Python setting.
# Usage: config.python.default <setting>
config.python.default() {
    local setting="$1"

    case "$setting" in
        build_command)  printf '' ;;
        build_tool)     printf 'auto' ;;
        test_framework) printf 'pytest' ;;
        lint_tool)      printf 'ruff' ;;
        format_tool)    printf 'ruff format' ;;
        *) return 1 ;;
    esac
    return 0
}

# Export Python version pinning.
# Sets: BRIK_BUILD_PYTHON_VERSION (if configured)
config.python.export_build_vars() {
    local python_version
    python_version="$(config.get '.build.python_version' '')"
    [[ -n "$python_version" ]] && export BRIK_BUILD_PYTHON_VERSION="$python_version"
    return 0
}

# Validate Python build tool coherence.
# If build tool is explicitly set, verify the matching project file exists.
# Usage: config.python.validate_coherence <workspace>
config.python.validate_coherence() {
    local workspace="$1"
    local tool="${BRIK_BUILD_TOOL:-}"

    # Only validate when tool is explicitly set (not auto)
    [[ -z "$tool" || "$tool" == "auto" ]] && return 0

    case "$tool" in
        uv)
            if [[ ! -f "${workspace}/pyproject.toml" ]] && [[ ! -f "${workspace}/uv.lock" ]]; then
                log.error "config mismatch: build.tool is 'uv' but neither pyproject.toml nor uv.lock found"
                log.error "fix: create a pyproject.toml, or change build.tool in brik.yml"
                return 7
            fi
            ;;
        poetry)
            if [[ ! -f "${workspace}/pyproject.toml" ]] && [[ ! -f "${workspace}/poetry.lock" ]]; then
                log.error "config mismatch: build.tool is 'poetry' but neither pyproject.toml nor poetry.lock found"
                log.error "fix: create a pyproject.toml, or change build.tool in brik.yml"
                return 7
            fi
            ;;
        pipenv)
            if [[ ! -f "${workspace}/Pipfile" ]]; then
                log.error "config mismatch: build.tool is 'pipenv' but Pipfile not found"
                log.error "fix: create a Pipfile, or change build.tool in brik.yml"
                return 7
            fi
            ;;
        pip)
            if [[ ! -f "${workspace}/requirements.txt" ]] \
                && [[ ! -f "${workspace}/setup.py" ]] \
                && [[ ! -f "${workspace}/pyproject.toml" ]]; then
                log.error "config mismatch: build.tool is 'pip' but no requirements.txt, setup.py, or pyproject.toml found"
                log.error "fix: create a requirements.txt or setup.py, or change build.tool in brik.yml"
                return 7
            fi
            ;;
    esac

    return 0
}

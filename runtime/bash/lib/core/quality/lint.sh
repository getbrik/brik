#!/usr/bin/env bash
# @module quality.lint
# @description Lint code using stack-appropriate linters.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_QUALITY_LINT_LOADED:-}" ]] && return 0
_BRIK_CORE_QUALITY_LINT_LOADED=1

# Run linting on a workspace.
# Usage: quality.lint.run <workspace> [--fix]
quality.lint.run() {
    local workspace="$1"
    shift
    local fix=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --fix) fix="true"; shift ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    runtime.require_dir "$workspace" || return 6

    local lint_cmd=""

    if [[ -f "${workspace}/package.json" ]]; then
        if command -v npx >/dev/null 2>&1; then
            lint_cmd="npx eslint ."
            [[ "$fix" == "true" ]] && lint_cmd="$lint_cmd --fix"
        else
            log.error "npx not found for JavaScript/TypeScript linting"
            return 3
        fi
    elif [[ -f "${workspace}/pyproject.toml" || -f "${workspace}/setup.py" ]]; then
        if command -v ruff >/dev/null 2>&1; then
            lint_cmd="ruff check ."
            [[ "$fix" == "true" ]] && lint_cmd="$lint_cmd --fix"
        else
            log.error "ruff not found for Python linting"
            return 3
        fi
    elif [[ -f "${workspace}/Cargo.toml" ]]; then
        if command -v cargo >/dev/null 2>&1; then
            lint_cmd="cargo clippy"
        else
            log.error "cargo not found for Rust linting"
            return 3
        fi
    elif [[ -f "${workspace}/pom.xml" || -f "${workspace}/build.gradle" || -f "${workspace}/build.gradle.kts" ]]; then
        log.warn "Java linting via checkstyle not yet supported - skipping"
        return 0
    else
        log.error "cannot detect stack for linting in workspace: $workspace"
        return 3
    fi

    log.info "linting: $lint_cmd"
    (cd "$workspace" && eval "$lint_cmd") || {
        log.error "lint violations found"
        return 10
    }

    log.info "lint passed"
    return 0
}

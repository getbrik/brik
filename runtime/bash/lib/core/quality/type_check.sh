#!/usr/bin/env bash
# @module quality.type_check
# @description Type-check code using stack-appropriate type checkers.
# 3-tier resolution: BRIK_QUALITY_TYPE_CHECK_COMMAND > BRIK_QUALITY_TYPE_CHECK_TOOL > auto-detect

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_QUALITY_TYPE_CHECK_LOADED:-}" ]] && return 0
_BRIK_CORE_QUALITY_TYPE_CHECK_LOADED=1

# Run type checking on a workspace.
# Usage: quality.type_check.run <workspace>
quality.type_check.run() {
    local workspace="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    runtime.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    # Tier 1: explicit command override
    if [[ -n "${BRIK_QUALITY_TYPE_CHECK_COMMAND:-}" ]]; then
        log.info "type checking (command override): $BRIK_QUALITY_TYPE_CHECK_COMMAND"
        (cd "$workspace" && eval "$BRIK_QUALITY_TYPE_CHECK_COMMAND") || {
            log.error "type check violations found"
            return "$BRIK_EXIT_CHECK_FAILED"
        }
        log.info "type check passed"
        return 0
    fi

    local check_cmd=""
    local tool="${BRIK_QUALITY_TYPE_CHECK_TOOL:-}"

    # Tier 2: explicit tool selection
    if [[ -n "$tool" ]]; then
        case "$tool" in
            tsc)
                if command -v npx >/dev/null 2>&1; then
                    check_cmd="npx tsc --noEmit"
                else
                    log.error "npx not found for tsc"
                    return "$BRIK_EXIT_MISSING_DEP"
                fi
                ;;
            mypy)
                if command -v mypy >/dev/null 2>&1; then
                    check_cmd="mypy ."
                else
                    log.error "mypy not found"
                    return "$BRIK_EXIT_MISSING_DEP"
                fi
                ;;
            pyright)
                if command -v npx >/dev/null 2>&1; then
                    check_cmd="npx pyright"
                else
                    log.error "npx not found for pyright"
                    return "$BRIK_EXIT_MISSING_DEP"
                fi
                ;;
            *)
                if command -v "$tool" >/dev/null 2>&1; then
                    check_cmd="$tool"
                else
                    log.error "unknown type check tool: $tool"
                    return "$BRIK_EXIT_CONFIG_ERROR"
                fi
                ;;
        esac
    fi

    # Tier 3: auto-detect from workspace files
    if [[ -z "$check_cmd" ]]; then
        if [[ -f "${workspace}/tsconfig.json" ]]; then
            if command -v npx >/dev/null 2>&1; then
                check_cmd="npx tsc --noEmit"
            else
                log.error "npx not found for TypeScript type checking"
                return "$BRIK_EXIT_MISSING_DEP"
            fi
        elif [[ -f "${workspace}/mypy.ini" ]] \
            || { [[ -f "${workspace}/pyproject.toml" ]] && grep -q '\[tool\.mypy\]' "${workspace}/pyproject.toml" 2>/dev/null; }; then
            if command -v mypy >/dev/null 2>&1; then
                check_cmd="mypy ."
            else
                log.error "mypy not found for Python type checking"
                return "$BRIK_EXIT_MISSING_DEP"
            fi
        else
            log.info "no type checker detected - skipping"
            return 0
        fi
    fi

    log.info "type checking: $check_cmd"
    (cd "$workspace" && eval "$check_cmd") || {
        log.error "type check violations found"
        return "$BRIK_EXIT_CHECK_FAILED"
    }

    log.info "type check passed"
    return 0
}

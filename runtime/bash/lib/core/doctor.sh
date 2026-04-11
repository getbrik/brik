#!/usr/bin/env bash
# @module doctor
# @description Prerequisites checker and stack tool diagnostics.
#
# Extracted from bin/brik cmd_doctor (Phase 4 - U9).
# Requires: logging, error, tools (runtime modules), build (for detect_stack).

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_DOCTOR_LOADED:-}" ]] && return 0
_BRIK_CORE_DOCTOR_LOADED=1

# Print tool version (first line of --version output).
# Usage: doctor._tool_version <tool>
doctor._tool_version() {
    local tool="$1"
    local version="installed"

    if command -v "$tool" >/dev/null 2>&1; then
        version="$("$tool" --version 2>/dev/null | head -n 1)" || true
    fi

    printf '%s\n' "$version"
}

# Check a list of tools and update passed/failed counters.
# Usage: doctor._check_tools <passed_var> <failed_var> <tool1> [tool2...]
doctor._check_tools() {
    local -n _passed=$1
    local -n _failed=$2
    shift 2

    local tool_name tool_version
    for tool_name in "$@"; do
        if command -v "$tool_name" >/dev/null 2>&1; then
            tool_version="$(doctor._tool_version "$tool_name")"
            printf '  [OK]      %s (%s)\n' "$tool_name" "$tool_version"
            _passed=$((_passed + 1))
        else
            printf '  [MISSING] %s\n' "$tool_name"
            _failed=$((_failed + 1))
        fi
    done
}

# Run full prerequisites check.
# Usage: doctor.run [<workspace>]
# Outputs diagnostic report to stdout. Returns non-zero if critical tools missing.
doctor.run() {
    local workspace="${1:-.}"
    local passed=0
    local failed=0
    local warned=0
    local tool_name=""
    local tool_version=""
    local stack=""

    runtime.require_dir "$workspace" || return "$?"

    printf '%s\n' "brik doctor - checking prerequisites"
    printf '%s\n' "======================================"
    printf '\n'

    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        printf '  [OK]      bash %s (>= 4 required)\n' "$BASH_VERSION"
        passed=$((passed + 1))
    else
        printf '  [MISSING] bash >= 4 (found %s)\n' "$BASH_VERSION"
        failed=$((failed + 1))
    fi

    for tool_name in yq jq; do
        local tool_hint=""
        case "$tool_name" in
            yq) tool_hint="https://github.com/mikefarah/yq" ;;
            jq) tool_hint="https://jqlang.github.io/jq/" ;;
        esac

        if command -v "$tool_name" >/dev/null 2>&1; then
            tool_version="$(doctor._tool_version "$tool_name")"
            printf '  [OK]      %s (%s)\n' "$tool_name" "$tool_version"
            passed=$((passed + 1))
        else
            printf '  [MISSING] %s - install from %s\n' "$tool_name" "$tool_hint"
            failed=$((failed + 1))
        fi
    done

    if command -v check-jsonschema >/dev/null 2>&1; then
        printf '  [OK]      check-jsonschema\n'
        passed=$((passed + 1))
    else
        printf '  [WARNING] check-jsonschema not found (needed for '\''brik validate'\'')\n'
        warned=$((warned + 1))
    fi

    if command -v shellcheck >/dev/null 2>&1; then
        printf '  [OK]      shellcheck\n'
        passed=$((passed + 1))
    else
        printf '  [WARNING] shellcheck not found (recommended for development)\n'
        warned=$((warned + 1))
    fi

    printf '\n'

    brik.use build
    stack="$(build.detect_stack "$workspace" 2>/dev/null)" || true

    if [[ -n "$stack" ]]; then
        printf '  Detected stack: %s (from %s)\n' "$stack" "$workspace"
        printf '\n'

        case "$stack" in
            node)   doctor._check_tools passed failed node npm ;;
            java)   doctor._check_tools passed failed java mvn ;;
            python) doctor._check_tools passed failed python3 pip3 ;;
            rust)   doctor._check_tools passed failed rustc cargo ;;
            dotnet) doctor._check_tools passed failed dotnet ;;
        esac
    else
        printf '  No stack detected in %s\n' "$workspace"
    fi

    printf '\n'
    printf '%s\n' "======================================"

    local summary="${passed} checks passed"
    if [[ "$failed" -gt 0 ]]; then
        summary="${summary}, ${failed} missing"
    fi
    if [[ "$warned" -gt 0 ]]; then
        summary="${summary}, ${warned} warnings"
    fi
    printf '%s\n' "$summary"

    if [[ "$failed" -gt 0 ]]; then
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    return "$BRIK_EXIT_OK"
}

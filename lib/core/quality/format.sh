#!/usr/bin/env bash
# @module quality.format
# @description Format check using stack-appropriate formatters.
# 3-tier resolution: BRIK_QUALITY_FORMAT_COMMAND > BRIK_QUALITY_FORMAT_TOOL > auto-detect

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_QUALITY_FORMAT_LOADED:-}" ]] && return 0
_BRIK_CORE_QUALITY_FORMAT_LOADED=1

# Run format check on a workspace.
# Usage: quality.format.run <workspace> [--check]
quality.format.run() {
    local workspace="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check) shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    runtime.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    local fmt_cmd=""

    # Tier 1: explicit command override
    if [[ -n "${BRIK_QUALITY_FORMAT_COMMAND:-}" ]]; then
        fmt_cmd="$BRIK_QUALITY_FORMAT_COMMAND"
        log.info "format (command override): $fmt_cmd"
        (cd "$workspace" && eval "$fmt_cmd") || {
            log.error "format violations found"
            return "$BRIK_EXIT_CHECK_FAILED"
        }
        log.info "format check passed"
        return 0
    fi

    # Tier 2: explicit tool selection
    local tool="${BRIK_QUALITY_FORMAT_TOOL:-}"

    # Tier 3: auto-detect from workspace files
    if [[ -z "$tool" ]]; then
        if [[ -f "${workspace}/package.json" ]]; then
            tool="prettier"
        elif [[ -f "${workspace}/pyproject.toml" || -f "${workspace}/setup.py" ]]; then
            tool="ruff-format"
        elif [[ -f "${workspace}/Cargo.toml" ]]; then
            tool="rustfmt"
        elif compgen -G "${workspace}/*.csproj" >/dev/null 2>&1 || compgen -G "${workspace}/*.sln" >/dev/null 2>&1; then
            tool="dotnet-format"
        elif [[ -f "${workspace}/pom.xml" || -f "${workspace}/build.gradle" || -f "${workspace}/build.gradle.kts" ]]; then
            tool="google-java-format"
        fi
    fi

    case "$tool" in
        prettier)
            if command -v npx >/dev/null 2>&1; then
                fmt_cmd="npx prettier --check ."
            else
                log.error "npx not found for prettier"
                return "$BRIK_EXIT_MISSING_DEP"
            fi
            ;;
        biome)
            if command -v npx >/dev/null 2>&1; then
                fmt_cmd="npx biome format . --check"
            else
                log.error "npx not found for biome"
                return "$BRIK_EXIT_MISSING_DEP"
            fi
            ;;
        ruff-format|ruff|"ruff format")
            if command -v ruff >/dev/null 2>&1; then
                fmt_cmd="ruff format --check ."
            else
                log.error "ruff not found for Python formatting"
                return "$BRIK_EXIT_MISSING_DEP"
            fi
            ;;
        black)
            if command -v black >/dev/null 2>&1; then
                fmt_cmd="black --check ."
            else
                log.error "black not found for Python formatting"
                return "$BRIK_EXIT_MISSING_DEP"
            fi
            ;;
        rustfmt)
            if command -v cargo >/dev/null 2>&1; then
                fmt_cmd="cargo fmt -- --check"
            else
                log.error "cargo not found for rustfmt"
                return "$BRIK_EXIT_MISSING_DEP"
            fi
            ;;
        dotnet-format)
            if command -v dotnet >/dev/null 2>&1; then
                fmt_cmd="dotnet format --verify-no-changes"
            else
                log.error "dotnet not found for formatting"
                return "$BRIK_EXIT_MISSING_DEP"
            fi
            ;;
        google-java-format)
            log.warn "google-java-format check not yet automated - skipping"
            return 0
            ;;
        "")
            log.warn "no format tool detected for workspace - skipping"
            return 0
            ;;
        *)
            if command -v "$tool" >/dev/null 2>&1; then
                fmt_cmd="$tool"
            else
                log.error "unknown format tool: $tool"
                return "$BRIK_EXIT_CONFIG_ERROR"
            fi
            ;;
    esac

    log.info "format check: $fmt_cmd"
    (cd "$workspace" && eval "$fmt_cmd") || {
        log.error "format violations found"
        return "$BRIK_EXIT_CHECK_FAILED"
    }

    log.info "format check passed"
    return 0
}

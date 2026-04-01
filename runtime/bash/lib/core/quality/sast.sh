#!/usr/bin/env bash
# @module quality.sast
# @description Static Application Security Testing.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_QUALITY_SAST_LOADED:-}" ]] && return 0
_BRIK_CORE_QUALITY_SAST_LOADED=1

# Run SAST on a workspace.
# Usage: quality.sast.run <workspace> [--tool <semgrep|trivy|custom>] [--command <cmd>]
quality.sast.run() {
    local workspace="$1"
    shift
    local tool="" custom_cmd=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tool) tool="$2"; shift 2 ;;
            --command) custom_cmd="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    runtime.require_dir "$workspace" || return 6

    # Auto-detect tool if not specified
    if [[ -z "$tool" ]]; then
        if command -v semgrep >/dev/null 2>&1; then
            tool="semgrep"
        elif command -v trivy >/dev/null 2>&1; then
            tool="trivy"
        else
            log.warn "no SAST tool available (install semgrep or trivy) - skipping"
            return 0
        fi
    fi

    local sast_cmd=""
    case "$tool" in
        semgrep)
            runtime.require_tool semgrep || return 3
            sast_cmd="semgrep scan --config auto ."
            ;;
        trivy)
            runtime.require_tool trivy || return 3
            sast_cmd="trivy fs --scanners vuln,secret ."
            ;;
        custom)
            if [[ -z "$custom_cmd" ]]; then
                log.error "custom SAST requires --command"
                return 2
            fi
            sast_cmd="$custom_cmd"
            ;;
        *)
            log.error "unsupported SAST tool: $tool"
            return 7
            ;;
    esac

    log.info "running SAST: $sast_cmd"
    (cd "$workspace" && eval "$sast_cmd") || {
        log.error "SAST findings detected"
        return 10
    }

    log.info "SAST passed"
    return 0
}

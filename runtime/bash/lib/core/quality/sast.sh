#!/usr/bin/env bash
# @module quality.sast
# @uses quality._tools
# @description Static Application Security Testing via tool registry.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_QUALITY_SAST_LOADED:-}" ]] && return 0
_BRIK_CORE_QUALITY_SAST_LOADED=1

# Source tool registry if not already loaded
# shellcheck source=_tools.sh
[[ -z "${_BRIK_CORE_QUALITY_TOOLS_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/_tools.sh"

# Register SAST scanners
quality.tool.register sast semgrep semgrep "semgrep scan --config auto ." 10

# Run SAST on a workspace.
# Usage: quality.sast.run <workspace> [--tool <semgrep|custom>] [--command <cmd>]
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

    # Tier 1: explicit command override
    if [[ -n "${BRIK_QUALITY_SAST_COMMAND:-}" ]]; then
        log.info "running SAST (command override): $BRIK_QUALITY_SAST_COMMAND"
        (cd "$workspace" && eval "$BRIK_QUALITY_SAST_COMMAND") || {
            log.error "SAST findings detected"
            return 10
        }
        log.info "SAST passed"
        return 0
    fi

    # Auto-detect tool if not specified
    if [[ -z "$tool" ]]; then
        if command -v semgrep >/dev/null 2>&1; then
            tool="semgrep"
        else
            log.warn "no SAST tool available (install semgrep) - skipping"
            return 0
        fi
    fi

    local sast_cmd=""
    case "$tool" in
        semgrep)
            runtime.require_tool semgrep || return 3
            sast_cmd="semgrep scan --config auto ."
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

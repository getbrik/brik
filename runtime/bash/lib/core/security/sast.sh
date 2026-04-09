#!/usr/bin/env bash
# @module security.sast
# @uses quality._tools
# @description Security-focused Static Application Security Testing.
# 3-tier resolution: BRIK_SECURITY_SAST_COMMAND > BRIK_SECURITY_SAST_TOOL > auto-detect

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_SECURITY_SAST_LOADED:-}" ]] && return 0
_BRIK_CORE_SECURITY_SAST_LOADED=1

# Source tool registry if not already loaded
# shellcheck source=../quality/_tools.sh
[[ -z "${_BRIK_CORE_QUALITY_TOOLS_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../quality/_tools.sh"

# Register security SAST scanners
quality.tool.register sec_sast semgrep semgrep "semgrep scan --config auto ." 10

# Run SAST scan on a workspace.
# Usage: security.sast.run <workspace>
security.sast.run() {
    local workspace="$1"
    shift

    runtime.require_dir "$workspace" || return 6

    # Tier 1: BRIK_SECURITY_SAST_COMMAND
    if [[ -n "${BRIK_SECURITY_SAST_COMMAND:-}" ]]; then
        log.info "SAST scan (command override): $BRIK_SECURITY_SAST_COMMAND"
        (cd "$workspace" && eval "$BRIK_SECURITY_SAST_COMMAND") || {
            log.error "SAST findings detected"
            return 10
        }
        log.info "SAST scan passed"
        return 0
    fi

    # Tier 2: BRIK_SECURITY_SAST_TOOL
    local tool="${BRIK_SECURITY_SAST_TOOL:-}"
    if [[ -n "$tool" ]]; then
        if command -v "$tool" >/dev/null 2>&1; then
            local sast_cmd=""
            case "$tool" in
                semgrep)
                    sast_cmd="semgrep scan --config auto ."
                    if [[ -n "${BRIK_SECURITY_SAST_RULESET:-}" ]]; then
                        sast_cmd="semgrep scan --config ${BRIK_SECURITY_SAST_RULESET} ."
                    fi
                    ;;
                *)
                    sast_cmd="$tool"
                    ;;
            esac
            log.info "SAST scan with tool: $tool"
            (cd "$workspace" && eval "$sast_cmd") || {
                log.error "SAST findings detected"
                return 10
            }
            log.info "SAST scan passed"
            return 0
        else
            log.error "SAST tool not found: $tool"
            return 3
        fi
    fi

    # Tier 3: auto-detect via registry
    local resolved
    resolved="$(quality.tool.resolve sec_sast)" || {
        log.warn "no SAST tool available (install semgrep) - skipping"
        return 0
    }
    log.info "SAST scan with ${resolved}"
    (cd "$workspace" && quality.tool.exec sec_sast "$resolved") || {
        log.error "SAST findings detected"
        return 10
    }
    log.info "SAST scan passed"
    return 0
}

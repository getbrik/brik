#!/usr/bin/env bash
# @module quality.secret_scan
# @uses quality._tools
# @description Secret scanning using dedicated secret detection tools.
# 3-tier resolution: BRIK_QUALITY_SECRET_SCAN_COMMAND > BRIK_QUALITY_SECRET_SCAN_TOOL > auto-detect

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_QUALITY_SECRET_SCAN_LOADED:-}" ]] && return 0
_BRIK_CORE_QUALITY_SECRET_SCAN_LOADED=1

# Source tool registry if not already loaded
# shellcheck source=_tools.sh
[[ -z "${_BRIK_CORE_QUALITY_TOOLS_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/_tools.sh"

# Register secret scanners
quality.tool.register secret_scan gitleaks  gitleaks  "gitleaks detect --source ." 10
quality.tool.register secret_scan trufflehog trufflehog "trufflehog filesystem ."  20

# Run secret scanning on a workspace.
# Usage: quality.secret_scan.run <workspace>
quality.secret_scan.run() {
    local workspace="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    runtime.require_dir "$workspace" || return 6

    # Tier 1: explicit command override
    if [[ -n "${BRIK_QUALITY_SECRET_SCAN_COMMAND:-}" ]]; then
        log.info "secret scanning (command override): $BRIK_QUALITY_SECRET_SCAN_COMMAND"
        (cd "$workspace" && eval "$BRIK_QUALITY_SECRET_SCAN_COMMAND") || {
            log.error "secrets detected"
            return 10
        }
        log.info "secret scan passed"
        return 0
    fi

    local scan_cmd=""
    local tool="${BRIK_QUALITY_SECRET_SCAN_TOOL:-}"

    # Tier 2: explicit tool selection
    if [[ -n "$tool" ]]; then
        case "$tool" in
            gitleaks)
                if command -v gitleaks >/dev/null 2>&1; then
                    scan_cmd="gitleaks detect --source ."
                else
                    log.error "gitleaks not found"
                    return 3
                fi
                ;;
            trufflehog)
                if command -v trufflehog >/dev/null 2>&1; then
                    scan_cmd="trufflehog filesystem ."
                else
                    log.error "trufflehog not found"
                    return 3
                fi
                ;;
            *)
                log.error "unknown secret scan tool: $tool (valid: gitleaks, trufflehog)"
                return 7
                ;;
        esac
    fi

    # Tier 3: auto-detect from available tools
    if [[ -z "$scan_cmd" ]]; then
        if command -v gitleaks >/dev/null 2>&1; then
            scan_cmd="gitleaks detect --source ."
        elif command -v trufflehog >/dev/null 2>&1; then
            scan_cmd="trufflehog filesystem ."
        else
            log.warn "no secret scanning tool available (install gitleaks or trufflehog) - skipping"
            return 0
        fi
    fi

    log.info "secret scanning: $scan_cmd"
    (cd "$workspace" && eval "$scan_cmd") || {
        log.error "secrets detected"
        return 10
    }

    log.info "secret scan passed"
    return 0
}

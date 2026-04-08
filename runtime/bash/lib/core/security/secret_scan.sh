#!/usr/bin/env bash
# @module security.secret_scan
# @uses quality._tools
# @description Security-focused secret scanning.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_SECURITY_SECRET_SCAN_LOADED:-}" ]] && return 0
_BRIK_CORE_SECURITY_SECRET_SCAN_LOADED=1

# Source tool registry if not already loaded
# shellcheck source=../quality/_tools.sh
[[ -z "${_BRIK_CORE_QUALITY_TOOLS_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../quality/_tools.sh"

# Register security secret scanners
quality.tool.register sec_secret gitleaks  gitleaks  "gitleaks detect --source ."  10
quality.tool.register sec_secret trufflehog trufflehog "trufflehog filesystem ."   20

# Run security secret scan on a workspace.
# Usage: security.secret_scan.run <workspace>
security.secret_scan.run() {
    local workspace="$1"
    shift

    runtime.require_dir "$workspace" || return 6

    # Tier 1: BRIK_SECURITY_SECRET_SCAN_COMMAND
    if [[ -n "${BRIK_SECURITY_SECRET_SCAN_COMMAND:-}" ]]; then
        log.info "security secret scan (command override): $BRIK_SECURITY_SECRET_SCAN_COMMAND"
        (cd "$workspace" && eval "$BRIK_SECURITY_SECRET_SCAN_COMMAND") || {
            log.error "secrets detected"
            return 10
        }
        log.info "security secret scan passed"
        return 0
    fi

    local scan_cmd=""
    local tool="${BRIK_SECURITY_SECRET_SCAN_TOOL:-}"

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

    # Tier 3: auto-detect
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

    log.info "security secret scanning: $scan_cmd"
    (cd "$workspace" && eval "$scan_cmd") || {
        log.error "secrets detected"
        return 10
    }

    log.info "security secret scan passed"
    return 0
}

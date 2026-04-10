#!/usr/bin/env bash
# @module security.iac
# @uses quality._tools
# @description Security-focused Infrastructure as Code scanning.
# 3-tier resolution: BRIK_SECURITY_IAC_COMMAND > BRIK_SECURITY_IAC_TOOL > auto-detect

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_SECURITY_IAC_LOADED:-}" ]] && return 0
_BRIK_CORE_SECURITY_IAC_LOADED=1

# Load tool registry
brik.use "quality._tools"

# Register IaC scanners
quality.tool.register sec_iac checkov checkov "checkov -d . --quiet --compact" 10
quality.tool.register sec_iac tfsec   tfsec   "tfsec ."                        20

# Run IaC security scan on a workspace.
# Usage: security.iac.run <workspace>
security.iac.run() {
    local workspace="$1"
    shift

    runtime.require_dir "$workspace" || return 6

    # Tier 1: BRIK_SECURITY_IAC_COMMAND
    if [[ -n "${BRIK_SECURITY_IAC_COMMAND:-}" ]]; then
        log.info "IaC scan (command override): $BRIK_SECURITY_IAC_COMMAND"
        (cd "$workspace" && eval "$BRIK_SECURITY_IAC_COMMAND") || {
            log.error "IaC security findings detected"
            return 10
        }
        log.info "IaC scan passed"
        return 0
    fi

    # Tier 2: BRIK_SECURITY_IAC_TOOL
    local tool="${BRIK_SECURITY_IAC_TOOL:-}"
    if [[ -n "$tool" ]]; then
        if command -v "$tool" >/dev/null 2>&1; then
            local iac_cmd=""
            case "$tool" in
                checkov)
                    iac_cmd="checkov -d . --quiet --compact"
                    ;;
                tfsec)
                    iac_cmd="tfsec ."
                    ;;
                *)
                    iac_cmd="$tool ."
                    ;;
            esac
            log.info "IaC scan with tool: $tool"
            (cd "$workspace" && eval "$iac_cmd") || {
                log.error "IaC security findings detected"
                return 10
            }
            log.info "IaC scan passed"
            return 0
        else
            log.error "IaC scan tool not found: $tool"
            return 3
        fi
    fi

    # Tier 3: auto-detect via registry
    local resolved
    resolved="$(quality.tool.resolve sec_iac)" || {
        log.warn "no IaC scanner available (install checkov or tfsec) - skipping"
        return 0
    }
    log.info "IaC scan with ${resolved}"
    (cd "$workspace" && quality.tool.exec sec_iac "$resolved") || {
        log.error "IaC security findings detected"
        return 10
    }
    log.info "IaC scan passed"
    return 0
}

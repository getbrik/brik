#!/usr/bin/env bash
# @module stages/sast
# @description SAST stage - static analysis, license, and IaC scans.
# Runs in the analysis image (Python/Ruby tools like semgrep, checkov).

# SAST stage: run SAST, license, and IaC scans via brik-lib.
# Usage: stages.sast <context_file>
stages.sast() {
    local context_file="$1"

    config.export_security_vars

    log.info "sast stage - running static analysis scans"

    local failed=0 total=0 passed=0

    # SAST scan (non-negotiable: defaults to semgrep if not configured)
    export BRIK_SECURITY_SAST_TOOL="${BRIK_SECURITY_SAST_TOOL:-semgrep}"
    total=$((total + 1))
    if ! declare -f security.sast.run >/dev/null 2>&1; then
        local sec_sast_path="${BASH_SOURCE[0]%/*}/../core/security/sast.sh"
        [[ -f "$sec_sast_path" ]] && . "$sec_sast_path"
    fi
    if declare -f security.sast.run >/dev/null 2>&1; then
        log.info "running SAST scan (tool=${BRIK_SECURITY_SAST_TOOL})"
        if security.sast.run "${BRIK_WORKSPACE}"; then
            passed=$((passed + 1))
            log.info "SAST scan passed"
        else
            failed=$((failed + 1))
            log.warn "SAST scan failed"
        fi
    else
        log.warn "SAST module not available - skipping"
    fi

    # License scan
    if [[ -n "${BRIK_SECURITY_LICENSE_ALLOWED:-}" || -n "${BRIK_SECURITY_LICENSE_DENIED:-}" ]]; then
        total=$((total + 1))
        if ! declare -f security.license.run >/dev/null 2>&1; then
            local sec_license_path="${BASH_SOURCE[0]%/*}/../core/security/license.sh"
            [[ -f "$sec_license_path" ]] && . "$sec_license_path"
        fi
        if declare -f security.license.run >/dev/null 2>&1; then
            log.info "running license scan"
            if security.license.run "${BRIK_WORKSPACE}"; then
                passed=$((passed + 1))
                log.info "license scan passed"
            else
                failed=$((failed + 1))
                log.warn "license scan failed"
            fi
        else
            log.warn "license module not available - skipping"
        fi
    fi

    # IaC scan
    if [[ -n "${BRIK_SECURITY_IAC_TOOL:-}" || -n "${BRIK_SECURITY_IAC_COMMAND:-}" ]]; then
        total=$((total + 1))
        if ! declare -f security.iac.run >/dev/null 2>&1; then
            local sec_iac_path="${BASH_SOURCE[0]%/*}/../core/security/iac.sh"
            [[ -f "$sec_iac_path" ]] && . "$sec_iac_path"
        fi
        if declare -f security.iac.run >/dev/null 2>&1; then
            log.info "running IaC scan"
            if security.iac.run "${BRIK_WORKSPACE}"; then
                passed=$((passed + 1))
                log.info "IaC scan passed"
            else
                failed=$((failed + 1))
                log.warn "IaC scan failed"
            fi
        else
            log.warn "IaC module not available - skipping"
        fi
    fi

    log.info "sast summary: $passed/$total passed, $failed failed"

    if [[ "$failed" -gt 0 ]]; then
        context.set "$context_file" "BRIK_SAST_STATUS" "failed"
        return 10
    fi

    context.set "$context_file" "BRIK_SAST_STATUS" "success"
    return 0
}

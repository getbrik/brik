#!/usr/bin/env bash
# @module stages/sast
# @description SAST stage - static analysis, license, and IaC scans.
# Runs in the analysis image (Python/Ruby tools like semgrep, checkov).

# SAST stage: run SAST, license, and IaC scans via security.run facade.
# Usage: stages.sast <context_file>
stages.sast() {
    local context_file="$1"

    config.export_security_vars

    log.info "sast stage - running static analysis scans"

    # Set tool defaults
    export BRIK_SECURITY_SAST_TOOL="${BRIK_SECURITY_SAST_TOOL:-semgrep}"

    # Build scans list: sast is always included
    local scans="sast"

    # License scan: only if configured
    if [[ -n "${BRIK_SECURITY_LICENSE_ALLOWED:-}" || -n "${BRIK_SECURITY_LICENSE_DENIED:-}" ]]; then
        scans="${scans},license"
    fi

    # IaC scan: only if configured
    if [[ -n "${BRIK_SECURITY_IAC_TOOL:-}" || -n "${BRIK_SECURITY_IAC_COMMAND:-}" ]]; then
        scans="${scans},iac"
    fi

    if ! declare -f security.run >/dev/null 2>&1; then
        brik.use "security"
    fi

    local result=0
    security.run "${BRIK_WORKSPACE}" --scans "$scans" || result=$?

    if [[ "$result" -eq 0 ]]; then
        context.set "$context_file" "BRIK_SAST_STATUS" "success"
    else
        context.set "$context_file" "BRIK_SAST_STATUS" "failed"
    fi

    return "$result"
}

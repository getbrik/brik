#!/usr/bin/env bash
# @module stages/scan
# @description Scan stage - dependency and secret scanning.
# Runs in the scanner image (Go binaries like osv-scanner, grype, gitleaks).

brik.use "_deps"

# Scan stage: run dependency and secret scans via security.run facade.
# Usage: stages.scan <context_file>
stages.scan() {
    local context_file="$1"

    config.export_security_vars

    log.info "scan stage - running dependency and secret scans"

    # Set tool defaults
    export BRIK_SECURITY_DEPS_TOOL="${BRIK_SECURITY_DEPS_TOOL:-osv-scanner}"
    export BRIK_SECURITY_SECRETS_TOOL="${BRIK_SECURITY_SECRETS_TOOL:-gitleaks}"

    _brik.install_deps "${BRIK_WORKSPACE}" scan

    local severity="${BRIK_SECURITY_DEPS_SEVERITY:-${BRIK_SECURITY_SEVERITY_THRESHOLD:-high}}"

    if ! declare -f security.run >/dev/null 2>&1; then
        brik.use "security"
    fi

    local result=0
    security.run "${BRIK_WORKSPACE}" --scans "deps,secret" --severity "$severity" || result=$?

    if [[ "$result" -eq 0 ]]; then
        context.set "$context_file" "BRIK_SCAN_STATUS" "success"
    else
        context.set "$context_file" "BRIK_SCAN_STATUS" "failed"
    fi

    return "$result"
}

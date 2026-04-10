#!/usr/bin/env bash
# @module stages/scan
# @description Scan stage - dependency and secret scanning.
# Runs in the scanner image (Go binaries like osv-scanner, grype, gitleaks).

brik.use "_deps"

# Scan stage: run dependency and secret scans via brik-lib.
# Usage: stages.scan <context_file>
stages.scan() {
    local context_file="$1"

    config.export_security_vars

    log.info "scan stage - running dependency and secret scans"

    local failed=0 total=0 passed=0

    # Dependency scan (non-negotiable: defaults to osv-scanner if not configured)
    export BRIK_SECURITY_DEPS_TOOL="${BRIK_SECURITY_DEPS_TOOL:-osv-scanner}"
    total=$((total + 1))

    _brik.install_deps "${BRIK_WORKSPACE}" scan

    if ! declare -f security.deps.run >/dev/null 2>&1; then
        brik.use "security.deps"
    fi

    if declare -f security.deps.run >/dev/null 2>&1; then
        local severity="${BRIK_SECURITY_DEPS_SEVERITY:-${BRIK_SECURITY_SEVERITY_THRESHOLD:-high}}"
        log.info "running dependency scan (tool=${BRIK_SECURITY_DEPS_TOOL}, severity=$severity)"
        if security.deps.run "${BRIK_WORKSPACE}" --severity "$severity"; then
            passed=$((passed + 1))
            log.info "dependency scan passed"
        else
            failed=$((failed + 1))
            log.warn "dependency scan failed"
        fi
    else
        log.warn "security.deps module not available - skipping dependency scan"
    fi

    # Secret scan (non-negotiable: defaults to gitleaks if not configured)
    export BRIK_SECURITY_SECRETS_TOOL="${BRIK_SECURITY_SECRETS_TOOL:-gitleaks}"
    total=$((total + 1))

    if ! declare -f security.secret_scan.run >/dev/null 2>&1; then
        brik.use "security.secret_scan"
    fi

    if declare -f security.secret_scan.run >/dev/null 2>&1; then
        log.info "running secret scan (tool=${BRIK_SECURITY_SECRETS_TOOL})"
        if security.secret_scan.run "${BRIK_WORKSPACE}"; then
            passed=$((passed + 1))
            log.info "secret scan passed"
        else
            failed=$((failed + 1))
            log.warn "secret scan failed"
        fi
    else
        log.warn "security.secret_scan module not available - skipping secret scan"
    fi

    log.info "scan summary: $passed/$total passed, $failed failed"

    if [[ "$failed" -gt 0 ]]; then
        context.set "$context_file" "BRIK_SCAN_STATUS" "failed"
        return 10
    fi

    context.set "$context_file" "BRIK_SCAN_STATUS" "success"
    return 0
}

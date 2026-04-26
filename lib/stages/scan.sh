#!/usr/bin/env bash
# @module stages/scan
# @description Scan stage - dependency and secret scanning.
# Runs in the scanner image (Go binaries like osv-scanner, grype, gitleaks).

brik.use "_deps"

# Scan stage: run dependency and secret scans via verify.scan.run facade.
# Usage: stages.scan <context_file>
stages.scan() {
    # context_file positionally passed by stage.run; unused here after §4.2
    # migration (pipeline.run records tech.status from rc).
    # shellcheck disable=SC2034
    local context_file="$1"

    config.export_security_vars

    log.info "scan stage - running dependency and secret scans"

    # Set tool defaults
    export BRIK_SECURITY_DEPS_TOOL="${BRIK_SECURITY_DEPS_TOOL:-osv-scanner}"
    export BRIK_SECURITY_SECRETS_TOOL="${BRIK_SECURITY_SECRETS_TOOL:-gitleaks}"

    stacks.install_deps "${BRIK_WORKSPACE}" scan || return $?

    local severity="${BRIK_SECURITY_DEPS_SEVERITY:-${BRIK_SECURITY_SEVERITY_THRESHOLD:-high}}"

    if ! declare -f verify.scan.run >/dev/null 2>&1; then
        brik.use verify.scan.scan
    fi

    # pipeline.run records tech.status from our rc (see commit cf719f5).
    verify.scan.run "${BRIK_WORKSPACE}" --scans "deps,secret" --severity "$severity"
}

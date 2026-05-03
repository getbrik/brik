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

    # Shift-left contract: scan is mandatory on a release build. A user-set
    # security.scan.enabled=false is honored only when the build is not on
    # a tag; on a tag it is forced and a log.info traces the override.
    if [[ "${BRIK_SCAN_ENABLED:-true}" != "true" ]]; then
        if [[ -n "${BRIK_COMMIT_TAG:-}" ]]; then
            log.info "scan disabled by config but forced on release (BRIK_COMMIT_TAG=${BRIK_COMMIT_TAG})"
        else
            stage.skip_with_warning "scan" \
                "scan disabled by user (security.scan.enabled=false) outside release context"
            return $?
        fi
    fi

    log.info "scan stage - running dependency and secret scans"

    # Set tool defaults
    export BRIK_SECURITY_DEPS_TOOL="${BRIK_SECURITY_DEPS_TOOL:-osv-scanner}"
    export BRIK_SECURITY_SECRETS_TOOL="${BRIK_SECURITY_SECRETS_TOOL:-gitleaks}"

    stacks.install_deps "${BRIK_WORKSPACE}" scan || return $?

    local severity="${BRIK_SECURITY_DEPS_SEVERITY:-${BRIK_SECURITY_SEVERITY_THRESHOLD:-high}}"

    if ! declare -f verify.scan.run >/dev/null 2>&1; then
        brik.use verify.scan.scan
    fi

    # Pipeline-report enrichment (chantier 20260502 L2.C.3). business.deps.*
    # and business.secret.* parsing (osv-scanner JSON, gitleaks JSON, SBOM)
    # is deferred to a follow-up that needs runner-output parsing.
    if command -v jq >/dev/null 2>&1; then
        local _deps_obj _secret_obj
        _deps_obj="$(jq -nc --arg tool "$BRIK_SECURITY_DEPS_TOOL" '{tool: $tool}')"
        _secret_obj="$(jq -nc --arg tool "$BRIK_SECURITY_SECRETS_TOOL" '{tool: $tool}')"
        report.record_object "scan" "tech" "deps"   "$_deps_obj"   2>/dev/null || true
        report.record_object "scan" "tech" "secret" "$_secret_obj" 2>/dev/null || true
    fi
    report.record "scan" "tech" "severity_threshold" "$severity" 2>/dev/null || true

    # pipeline.run records tech.status from our rc (see commit cf719f5).
    verify.scan.run "${BRIK_WORKSPACE}" --scans "deps,secret" --severity "$severity"
}

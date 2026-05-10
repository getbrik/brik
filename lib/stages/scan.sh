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

    # Shift-left contract: scan always runs. The runtime no longer reads
    # BRIK_SCAN_ENABLED to gate the stage; opting out is a business-level
    # decision and lives outside the technical layer.

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
    local _verify_rc=$?

    # Pipeline-report business.* enrichment (chantier 20260502 L2.C.3 absorbed
    # into L4): aggregate the deps SARIF, SBOM, and secret SARIF outputs into
    # business.deps.{vulnerabilities, affected_packages, sbom_path},
    # business.secret.{findings_count, report}, and business.report rollup.
    _scan._record_business 2>/dev/null || true

    return "$_verify_rc"
}

# Aggregate scan-stage artifacts into business.deps.*, business.secret.*,
# and business.report. No-op when the relevant transverse modules are
# missing, jq is missing, or none of the expected files exist.
_scan._record_business() {
    command -v jq >/dev/null 2>&1 || return 0

    if ! declare -f sarif.count_total >/dev/null 2>&1; then
        brik.use transverse.sarif 2>/dev/null || return 0
    fi
    declare -f sbom.component_count >/dev/null 2>&1 \
        || brik.use transverse.sbom 2>/dev/null || true

    local _ws="${BRIK_WORKSPACE:-.}"
    local _deps_path="${BRIK_SECURITY_DEPS_OUTPUT_PATH:-brik-artifacts/scan/deps.sarif}"
    local _sbom_path="${BRIK_SECURITY_DEPS_SBOM_OUTPUT_PATH:-brik-artifacts/scan/sbom.cdx.json}"
    local _secret_path="${BRIK_SECURITY_SECRETS_OUTPUT_PATH:-brik-artifacts/scan/secret.sarif}"

    local _deps_file="${_ws}/${_deps_path}"
    local _sbom_file="${_ws}/${_sbom_path}"
    local _secret_file="${_ws}/${_secret_path}"

    if [[ -f "$_deps_file" ]]; then
        local _deps_total _deps_sev _deps_obj
        _deps_total="$(sarif.count_total "$_deps_file" 2>/dev/null || echo 0)"
        _deps_sev="$(sarif.count_by_severity "$_deps_file" 2>/dev/null \
            || echo '{"critical":0,"high":0,"medium":0,"low":0,"info":0}')"
        _deps_obj="$(jq -nc \
            --argjson total      "$_deps_total" \
            --argjson by_severity "$_deps_sev" \
            '{vulnerabilities: {total: $total, by_severity: $by_severity}}')"

        if [[ -f "$_sbom_file" ]] && declare -f sbom.component_count >/dev/null 2>&1; then
            local _affected
            _affected="$(sbom.vuln_count "$_sbom_file" 2>/dev/null || echo 0)"
            [[ "$_affected" = "0" ]] && _affected="$(sbom.component_count "$_sbom_file" 2>/dev/null || echo 0)"
            _deps_obj="$(jq -nc \
                --argjson base       "$_deps_obj" \
                --argjson affected   "$_affected" \
                --arg     sbom_path  "$_sbom_path" \
                '$base + {affected_packages: $affected, sbom_path: $sbom_path}')"
        fi

        report.record_object "scan" "business" "deps" "$_deps_obj" 2>/dev/null || true

        local _rollup
        _rollup="$(jq -nc --arg path "$_deps_path" '{format:"sarif", path:$path}')"
        report.record_object "scan" "business" "report" "$_rollup" 2>/dev/null || true
    fi

    if [[ -f "$_secret_file" ]]; then
        local _secret_count _secret_obj
        _secret_count="$(sarif.count_total "$_secret_file" 2>/dev/null || echo 0)"
        _secret_obj="$(jq -nc \
            --argjson findings_count "$_secret_count" \
            --arg     path           "$_secret_path" \
            '{findings_count: $findings_count, report: {format:"sarif", path:$path}}')"
        report.record_object "scan" "business" "secret" "$_secret_obj" 2>/dev/null || true
    fi
}

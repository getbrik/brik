#!/usr/bin/env bash
# @module stages/sast
# @description SAST stage - static analysis, license, and IaC scans.
# Runs in the analysis image (Python/Ruby tools like semgrep, checkov).

# SAST stage: run SAST, license, and IaC scans via verify.scan.run facade.
# Usage: stages.sast <context_file>
stages.sast() {
    # context_file positionally passed by stage.run; unused here after §4.2
    # migration (pipeline.run records tech.status from rc).
    # shellcheck disable=SC2034
    local context_file="$1"

    config.export_security_vars

    # Shift-left contract: sast is mandatory on a release build. A user-set
    # security.sast.enabled=false is honored only when the build is not on
    # a tag; on a tag it is forced and a log.info traces the override.
    if [[ "${BRIK_SAST_ENABLED:-true}" != "true" ]]; then
        if [[ -n "${BRIK_COMMIT_TAG:-}" ]]; then
            log.info "sast disabled by config but forced on release (BRIK_COMMIT_TAG=${BRIK_COMMIT_TAG})"
        else
            stage.skip_with_warning "sast" \
                "sast disabled by user (security.sast.enabled=false) outside release context"
            return $?
        fi
    fi

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

    if ! declare -f verify.scan.run >/dev/null 2>&1; then
        brik.use verify.scan.scan
    fi

    # Pipeline-report enrichment (chantier 20260502 L2.C.3). business.findings
    # parsing (semgrep JSON, etc.) is deferred to a follow-up that needs
    # runner-output parsing.
    report.record "sast" "tech" "tool" "$BRIK_SECURITY_SAST_TOOL" 2>/dev/null || true
    if [[ -n "${BRIK_SECURITY_SAST_RULESET:-}" ]]; then
        report.record "sast" "tech" "ruleset" "$BRIK_SECURITY_SAST_RULESET" 2>/dev/null || true
    fi

    # pipeline.run records tech.status from our rc (see commit cf719f5).
    verify.scan.run "${BRIK_WORKSPACE}" --scans "$scans"
    local _verify_rc=$?

    # Pipeline-report business.* enrichment (chantier 20260502 L2.C.3 absorbed
    # into L4): aggregate the SARIF report produced under
    # ${BRIK_WORKSPACE}/${BRIK_SECURITY_SAST_OUTPUT_PATH:-target/sast.sarif}
    # into business.findings.{total, by_severity, cwe} + business.report.
    _sast._record_business 2>/dev/null || true

    return "$_verify_rc"
}

# Aggregate the SAST SARIF report into business.findings + business.report.
# No-op when the sarif transverse module is missing, jq is missing, or the
# expected SARIF file does not exist under the workspace.
_sast._record_business() {
    command -v jq >/dev/null 2>&1 || return 0

    local _path="${BRIK_SECURITY_SAST_OUTPUT_PATH:-target/sast.sarif}"
    local _file="${BRIK_WORKSPACE:-.}/${_path}"
    [[ -f "$_file" ]] || return 0

    if ! declare -f sarif.count_total >/dev/null 2>&1; then
        brik.use transverse.sarif 2>/dev/null || return 0
    fi

    local _total _by_severity _cwe
    _total="$(sarif.count_total "$_file" 2>/dev/null || echo 0)"
    _by_severity="$(sarif.count_by_severity "$_file" 2>/dev/null \
        || echo '{"critical":0,"high":0,"medium":0,"low":0,"info":0}')"
    _cwe="$(sarif.extract_cwe "$_file" 2>/dev/null || echo '[]')"

    local _findings_obj
    _findings_obj="$(jq -nc \
        --argjson total       "$_total" \
        --argjson by_severity "$_by_severity" \
        --argjson cwe         "$_cwe" \
        '{total: $total, by_severity: $by_severity, cwe: $cwe}')"
    report.record_object "sast" "business" "findings" "$_findings_obj" 2>/dev/null || true

    local _report_obj
    _report_obj="$(jq -nc --arg path "$_path" '{format:"sarif", path:$path}')"
    report.record_object "sast" "business" "report" "$_report_obj" 2>/dev/null || true
}

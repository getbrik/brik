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

    # Shift-left contract: sast always runs. The runtime no longer reads
    # BRIK_SAST_ENABLED to gate the stage; opting out is a business-level
    # decision and lives outside the technical layer.

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

    # Lazy load of the unified findings module (chantier 20260508 P1.6 / P4).
    # Tests Include findings.sh directly so this brik.use is a no-op there;
    # in prod it pulls the module on first SAST run. Failures of brik.use
    # are intentionally not suppressed -- a missing module would surface a
    # log.error and the pipeline operator must fix the install.
    if ! declare -f findings.process >/dev/null 2>&1; then
        brik.use transverse.findings
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

    # Run the SARIF through the unified ingest -> policy -> aggregate
    # pipeline (chantier 20260508 P4). The recorded L4 v1 shape
    # (business.findings.{total, by_severity, cwe} + business.report.{format,
    # path}) is preserved verbatim so Jenkins Warnings NG and the GitLab
    # Ultimate SARIF overlay keep working unchanged; L4 v2 fields
    # (failing, ignored.*) are added on top via apply_policy.
    local _sast_sarif="${BRIK_WORKSPACE:-.}/${BRIK_SECURITY_SAST_OUTPUT_PATH:-brik-artifacts/sast/sast.sarif}"
    if declare -f findings.scan_gate >/dev/null 2>&1; then
        findings.scan_gate "sast" "$_verify_rc" "$_sast_sarif"
        return $?
    fi
    return "$_verify_rc"
}

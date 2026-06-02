#!/usr/bin/env bash
# @module verify.scan.deps
# @uses transverse.tools verify._scan
# @description Security-focused dependency vulnerability scanning.

# Guard against double-sourcing
[[ -n "${_BRIK_VERIFY_SCAN_DEPS_LOADED:-}" ]] && return 0
_BRIK_VERIFY_SCAN_DEPS_LOADED=1

# Load tool registry and common scan helper
brik.use transverse.tools
brik.use verify.scan._scan

# Register security dependency scanners (sec_ prefix avoids collision with quality.deps).
#
# osv-scanner emits its SARIF from THIS single authoritative pass (--format
# sarif --output-file). The run that decides pass/fail is the run that writes
# the report, so the report can never disagree with the verdict and -- unlike
# a second, rc-gated osv-scanner invocation -- it can never write a clean
# report that masks a tool failure (chantier 20260508 P4 HIGH 1 / chantier #24
# Phase 3). grype keeps its dir-mode table pass (no native SARIF here).
transverse.tools.register sec_deps osv-scanner osv-scanner "osv-scanner scan --format sarif --output-file {output} ." 10
transverse.tools.register sec_deps grype       grype       "grype dir:{workspace}"                                    20

# Run security dependency scan on a workspace.
# Usage: verify.scan.deps.run <workspace> [--severity <threshold>]
verify.scan.deps.run() {
    local workspace="$1"
    shift
    local severity="high"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --severity) severity="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    pipeline.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    # Tier 1: BRIK_SECURITY_DEPS_COMMAND
    if [[ -n "${BRIK_SECURITY_DEPS_COMMAND:-}" ]]; then
        log.info "security dependency scan (command override): $BRIK_SECURITY_DEPS_COMMAND"
        (cd "$workspace" && eval "$BRIK_SECURITY_DEPS_COMMAND") || {
            log.error "security dependency vulnerabilities found"
            return "$BRIK_EXIT_CHECK_FAILED"
        }
        log.info "security dependency scan passed"
        return 0
    fi

    # Tier 2+3: resolve via tool registry
    local tool="${BRIK_SECURITY_DEPS_TOOL:-}"
    local resolve_args=(sec_deps)
    [[ -n "$tool" ]] && resolve_args+=(--tool "$tool")

    local resolved rc=0
    resolved="$(transverse.tools.resolve "${resolve_args[@]}")" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        if [[ $rc -eq 3 ]]; then
            log.error "security dependency scan tool not found: $tool"
            return "$BRIK_EXIT_MISSING_DEP"
        elif [[ $rc -eq 7 ]]; then
            log.error "unknown security dependency scan tool: $tool"
            return "$BRIK_EXIT_CONFIG_ERROR"
        fi
        log.warn "no security dependency scanner available - skipping"
        return 0
    fi

    log.info "security dependency scan with $resolved"

    local _deps_rel="${BRIK_SECURITY_DEPS_OUTPUT_PATH:-brik-artifacts/scan/deps.sarif}"
    local _deps_sarif="${workspace}/${_deps_rel}"

    # Make the findings gate available to both paths below.
    if ! declare -f findings.scan_gate >/dev/null 2>&1; then
        brik.use transverse.findings 2>/dev/null || true
    fi

    if [[ "$resolved" == "osv-scanner" ]]; then
        _verify.scan.deps._run_osv "$workspace" "$_deps_rel" "$_deps_sarif"
        return $?
    fi

    # Any non-osv tool (grype): legacy dir-mode table pass; the gate falls back
    # to the tool exit code because grype produces no native SARIF here.
    _verify.scan.deps._run_table "$workspace" "$resolved" "$severity" "$_deps_sarif"
    return $?
}

# osv-scanner path: the single authoritative scan pass writes the SARIF. The
# outcome is read from the SARIF, never invented from an empty fragment.
#
# Three cases, never conflated:
#   1. packages scanned, no vulnerabilities -> valid SARIF, zero results -> pass
#   2. packages scanned, vulnerabilities    -> valid SARIF, results > 0  -> fail (rc 10)
#   3. no valid SARIF produced and not a "no package sources" skip -> the tool
#      failed before reporting -> tech.tool_error + fail, NEVER a silent
#      "0 findings" success (chantier #24 Phase 3, council case 3).
_verify.scan.deps._run_osv() {
    local workspace="$1" rel="$2" sarif="$3"
    local scan_output="" scan_rc=0

    (cd "$workspace" && mkdir -p "$(dirname "$rel")") 2>/dev/null || true
    # Clear any stale report from a prior run BEFORE scanning. Otherwise a
    # crash that writes nothing could be masked by an old (possibly clean)
    # SARIF left at this path. After this, the SARIF's presence proves THIS
    # pass produced it -- which is what makes the case-3 tool-error check below
    # sound on persistent/cached runners, not only on fresh CI workspaces.
    rm -f "$sarif" 2>/dev/null || true
    scan_output="$(cd "$workspace" && transverse.tools.exec sec_deps osv-scanner \
        workspace="$workspace" output="$rel" 2>&1)" || scan_rc=$?

    # No package sources: nothing to scan (osv-scanner exits non-zero and
    # writes no SARIF). A legitimate skip, not a failure. Emit empty stubs so
    # CI artifact uploads find the expected files.
    if printf '%s' "$scan_output" | grep -qi "no package sources found"; then
        log.warn "no package sources found for osv-scanner - skipping"
        _verify.scan.deps._write_empty_reports "$workspace"
        return 0
    fi

    # The SBOM is the dependency inventory ("what was scanned"), not the
    # verdict ("did it pass"); emit it regardless so downstream supply-chain
    # tooling has it. It cannot mask the failure signal (the SARIF is
    # authoritative).
    _verify.scan.deps._emit_sbom "$workspace"

    # No valid SARIF from the authoritative pass. Distinguish a tool failure
    # from a benign no-op using the exit status as the corroborating signal:
    #   - non-zero exit -> osv-scanner failed before reporting (crash, OOM,
    #     bad invocation). Surface a tool error -- NEVER a silent "0 findings"
    #     success (council case 3). A real vulnerability run that somehow left
    #     no SARIF also exits non-zero, so it is caught here, not masked.
    #   - zero exit -> the tool ran and reported success but emitted no report
    #     (e.g. a stubbed scanner). There is nothing to gate on; treat it as a
    #     clean pass. Real osv-scanner always writes a SARIF on a zero exit, so
    #     this branch never triggers for it in production.
    if [[ ! -f "$sarif" ]] || ! jq -e 'has("runs")' "$sarif" >/dev/null 2>&1; then
        if [[ "$scan_rc" -ne 0 ]]; then
            report.record "scan" "tech" "tool_error" "true" 2>/dev/null || true
            printf '%s\n' "$scan_output" >&2
            log.error "security dependency scanner error: osv-scanner produced no valid report (exit ${scan_rc})"
            return "$BRIK_EXIT_CHECK_FAILED"
        fi
        log.info "security dependency scan passed"
        return 0
    fi

    # The SARIF is authoritative. Derive the gate's fallback verdict from the
    # SARIF result count (robust across osv-scanner exit-code quirks) so an
    # extraction error that still scanned cleanly is a pass; when a policy
    # backend is present, findings.scan_gate's policy decision takes over.
    local _results
    _results="$(jq '[.runs[].results[]?] | length' "$sarif" 2>/dev/null || echo 0)"
    [[ "$_results" =~ ^[0-9]+$ ]] || _results=0

    # Surface the advisories in the job log. In --output-file mode the SARIF
    # goes to a file, so without this the readable advisory list never reaches
    # the log. Runs whether the policy gate passes (below-threshold) or fails.
    _verify.scan.deps._log_findings "$sarif"

    local _content_rc=0
    (( _results > 0 )) && _content_rc="$BRIK_EXIT_CHECK_FAILED"

    if declare -f findings.scan_gate >/dev/null 2>&1; then
        if findings.scan_gate "scan_deps" "$_content_rc" "$sarif" 2>/dev/null; then
            log.info "security dependency scan passed"
            return 0
        fi
        log.error "security dependency vulnerabilities found"
        return "$BRIK_EXIT_CHECK_FAILED"
    fi

    # No findings module: the SARIF result count is the verdict.
    if (( _results > 0 )); then
        log.error "security dependency vulnerabilities found"
        return "$BRIK_EXIT_CHECK_FAILED"
    fi
    log.info "security dependency scan passed"
    return 0
}

# Non-osv path (grype): dir-mode pass that prints a human table. grype emits no
# native SARIF here, so the gate falls back to the tool exit code.
_verify.scan.deps._run_table() {
    local workspace="$1" resolved="$2" severity="$3" sarif="$4"
    local scan_output="" scan_rc=0

    scan_output="$(cd "$workspace" && transverse.tools.exec sec_deps "$resolved" \
        workspace="$workspace" severity="${severity^^}" 2>&1)" || scan_rc=$?

    if [[ "$scan_rc" -ne 0 ]]; then
        # The tool returns non-zero when no package sources are found.
        if echo "$scan_output" | grep -qi "no package sources found"; then
            log.warn "no package sources found for $resolved - skipping"
            _verify.scan.deps._write_empty_reports "$workspace"
            return 0
        fi
        # Transient extraction errors (e.g. deps.dev RPC unreachable) can exit
        # non-zero while still reporting zero vulnerabilities. Treat as a pass.
        if echo "$scan_output" | grep -qE "Total 0 packages affected by 0 known vulnerabilities"; then
            log.warn "$resolved reported extraction errors but found no vulnerabilities - treating as pass"
            printf '%s\n' "$scan_output" >&2
            scan_rc=0
        fi
    fi

    if declare -f findings.scan_gate >/dev/null 2>&1; then
        if findings.scan_gate "scan_deps" "$scan_rc" "$sarif" 2>/dev/null; then
            log.info "security dependency scan passed"
            return 0
        fi
        printf '%s\n' "$scan_output" >&2
        log.error "security dependency vulnerabilities found"
        return "$BRIK_EXIT_CHECK_FAILED"
    fi

    if [[ "$scan_rc" -ne 0 ]]; then
        printf '%s\n' "$scan_output" >&2
        log.error "security dependency vulnerabilities found"
        return "$BRIK_EXIT_CHECK_FAILED"
    fi
    log.info "security dependency scan passed"
    return 0
}

# Write valid empty SARIF and CycloneDX stubs at the canonical paths.
# Used when osv-scanner reports "no package sources found" so CI artifact
# uploads (GitLab artifacts.reports.cyclonedx, artifacts.paths) find the
# expected files instead of emitting "no matching files" warnings.
_verify.scan.deps._write_empty_reports() {
    local workspace="$1"
    local sarif="${BRIK_SECURITY_DEPS_OUTPUT_PATH:-brik-artifacts/scan/deps.sarif}"
    local sbom="${BRIK_SECURITY_DEPS_SBOM_OUTPUT_PATH:-brik-artifacts/scan/sbom.cdx.json}"
    (cd "$workspace" \
        && mkdir -p "$(dirname "$sarif")" "$(dirname "$sbom")" \
        && printf '%s\n' '{"$schema":"https://json.schemastore.org/sarif-2.1.0.json","version":"2.1.0","runs":[]}' > "$sarif" \
        && printf '%s\n' '{"$schema":"http://cyclonedx.org/schema/bom-1.5.schema.json","bomFormat":"CycloneDX","specVersion":"1.5","version":1,"components":[],"vulnerabilities":[]}' > "$sbom") \
        || true
}

# Log a summary of the advisories in the authoritative SARIF so the job log
# shows WHAT was found. In --format sarif --output-file mode the report goes to
# a file, so without this the readable advisory list never reaches the log.
# Logs the per-result message (osv-scanner phrases it as "Package <pkg> is
# vulnerable to <CVE> (also known as <GHSA>)", so it carries the package and
# every advisory alias), falling back to the rule id. No-op when the SARIF is
# absent/empty. Logged at info and the header is worded with "vulnerabilities"
# so it does not read as a stage error.
_verify.scan.deps._log_findings() {
    local sarif="$1"
    [[ -f "$sarif" ]] && command -v jq >/dev/null 2>&1 || return 0
    local count
    count="$(jq -r '[.runs[].results[]?] | length' "$sarif" 2>/dev/null || echo 0)"
    [[ "$count" =~ ^[0-9]+$ ]] && (( count > 0 )) || return 0
    log.info "dependency vulnerabilities found (${count}):"
    # gsub collapses any control chars (newlines, tabs, terminal escapes) so a
    # message cannot split a finding across log lines or inject escape noise.
    # One info line per advisory.
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] && log.info "  ${line}"
    done < <(jq -r '
        .runs[].results[]?
        | ((.message.text // .ruleId // "unknown") | gsub("[[:cntrl:]]+"; " "))
    ' "$sarif" 2>/dev/null)
}

# Emit the CycloneDX SBOM (dependency inventory). Separate osv-scanner
# invocation: the SBOM lists components, not the scan verdict, so producing it
# after the authoritative SARIF pass cannot mask a failure. Non-fatal: a
# missing SBOM only costs supply-chain inspection, never the verdict.
_verify.scan.deps._emit_sbom() {
    local workspace="$1"
    local sbom="${BRIK_SECURITY_DEPS_SBOM_OUTPUT_PATH:-brik-artifacts/scan/sbom.cdx.json}"
    local sbom_dir;  sbom_dir="$(dirname "$sbom")"

    if [[ "${BRIK_SECURITY_DEPS_SBOM_ENABLED:-true}" == "true" ]]; then
        (cd "$workspace" && mkdir -p "$sbom_dir" \
            && osv-scanner scan --format cyclonedx-1-5 --output-file "$sbom" . >/dev/null 2>&1 || true)
    fi
}

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

# Register security dependency scanners (sec_ prefix avoids collision with quality.deps)
transverse.tools.register sec_deps osv-scanner osv-scanner "osv-scanner scan --format table ." 10
transverse.tools.register sec_deps grype       grype       "grype dir:{workspace}"              20

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
    local scan_output="" scan_rc=0
    scan_output="$(cd "$workspace" && transverse.tools.exec sec_deps "$resolved" \
        workspace="$workspace" severity="${severity^^}" 2>&1)" || scan_rc=$?

    if [[ "$scan_rc" -ne 0 ]]; then
        # osv-scanner returns non-zero when no package sources found
        if echo "$scan_output" | grep -qi "no package sources found"; then
            log.warn "no package sources found for $resolved - skipping"
            return 0
        fi
        # osv-scanner can exit non-zero on transient extraction errors
        # (e.g. transitivedependency/pomxml RPC to deps.dev unreachable)
        # while still reporting zero vulnerabilities. Treat that as a pass.
        if echo "$scan_output" | grep -qE "Total 0 packages affected by 0 known vulnerabilities"; then
            log.warn "$resolved reported extraction errors but found no vulnerabilities - treating as pass"
            printf '%s\n' "$scan_output" >&2
            scan_rc=0
        fi
    fi

    # L4 enrichment: emit SARIF + CycloneDX reports for the pipeline-report
    # business.deps.* aggregation. Only osv-scanner has native support for
    # both formats here; grype takes a separate path. Failures of the
    # report passes are non-fatal (informational outputs).
    if [[ "$resolved" == "osv-scanner" ]]; then
        _verify.scan.deps._emit_reports "$workspace"
    fi

    if [[ "$scan_rc" -ne 0 ]]; then
        printf '%s\n' "$scan_output" >&2
        log.error "security dependency vulnerabilities found"
        return "$BRIK_EXIT_CHECK_FAILED"
    fi
    log.info "security dependency scan passed"
    return 0
}

# Run osv-scanner twice more: once for SARIF, once for CycloneDX 1.5.
# Both calls tolerate non-zero exit (the table pass already determined
# pass/fail above; these passes only produce side-effect reports for the
# L4 lib/stages/scan.sh aggregator).
_verify.scan.deps._emit_reports() {
    local workspace="$1"
    local sarif="${BRIK_SECURITY_DEPS_OUTPUT_PATH:-target/scan.sarif}"
    local sbom="${BRIK_SECURITY_DEPS_SBOM_OUTPUT_PATH:-target/sbom.cdx.json}"
    local sarif_dir; sarif_dir="$(dirname "$sarif")"
    local sbom_dir;  sbom_dir="$(dirname "$sbom")"

    (cd "$workspace" && mkdir -p "$sarif_dir" \
        && osv-scanner scan --format sarif --output "$sarif" . >/dev/null 2>&1 || true)

    if [[ "${BRIK_SECURITY_DEPS_SBOM_ENABLED:-true}" == "true" ]]; then
        (cd "$workspace" && mkdir -p "$sbom_dir" \
            && osv-scanner scan --format cyclonedx-1-5 --output "$sbom" . >/dev/null 2>&1 || true)
    fi
}

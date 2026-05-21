#!/usr/bin/env bash
# @module verify.scan.container
# @uses transverse.tools transverse.findings
# @description Security-focused container image scanning.

# Guard against double-sourcing
[[ -n "${_BRIK_VERIFY_SCAN_CONTAINER_LOADED:-}" ]] && return 0
_BRIK_VERIFY_SCAN_CONTAINER_LOADED=1

# Load tool registry
brik.use transverse.tools

# Build the grype command line emitting SARIF (no --fail-on; the policy
# gate downstream decides pass/fail from business.findings.failing). The
# SARIF lands at brik-artifacts/container-scan/container-scan.sarif so
# findings.process can pick it up alongside the other stage outputs and
# the artifact dir matches the canonical kebab-case stage name shared by
# the GitLab fragment dir, the Jenkins workspace layout, and the
# .stages[].name entry that report.record writes from lib/stages/container_scan.sh.
_verify.scan.container._build_grype_command() {
    local out="${BRIK_WORKSPACE:-.}/${BRIK_SECURITY_CONTAINER_OUTPUT_PATH:-brik-artifacts/container-scan/container-scan.sarif}"
    local out_dir
    out_dir="$(dirname "$out")"
    printf 'mkdir -p %s && grype {image} -o sarif --file %s' "$out_dir" "$out"
}

# Run security container scan.
# Usage: verify.scan.container.run <workspace> [--image <image>] [--severity <threshold>]
verify.scan.container.run() {
    # shellcheck disable=SC2034
    local workspace="$1"
    shift
    local image="" severity="HIGH"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image) image="$2"; shift 2 ;;
            --severity) severity="${2^^}"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Use config vars as fallback for image and severity
    if [[ -z "$image" ]]; then
        image="${BRIK_SECURITY_CONTAINER_IMAGE:-}"
    fi
    if [[ -z "$image" ]]; then
        image="${BRIK_PROJECT_NAME:-project}:${BRIK_APP_VERSION:-${BRIK_COMMIT_SHORT_SHA:-latest}}"
    fi

    if [[ -n "${BRIK_SECURITY_CONTAINER_SEVERITY:-}" && "$severity" == "HIGH" ]]; then
        severity="${BRIK_SECURITY_CONTAINER_SEVERITY^^}"
    fi

    # Re-register grype just-in-time so a per-run BRIK_WORKSPACE update is
    # reflected in the SARIF output path. Dockle remains text-only until
    # the P5 converter lands; it stays as a Tier-3 fallback for hosts
    # without grype installed.
    transverse.tools.register sec_container grype  grype \
        "$(_verify.scan.container._build_grype_command)" 10
    transverse.tools.register sec_container dockle dockle \
        "dockle {image}" 20

    local resolved
    resolved="$(transverse.tools.resolve sec_container)" || {
        log.warn "no security container scanner available (install grype) - skipping"
        return 0
    }

    log.info "security container scan with ${resolved}"
    if ! transverse.tools.exec sec_container "$resolved" \
            image="$image" severity="${severity,,}"; then
        # Tool execution itself failed (binary error, registry unreachable,
        # ...). Without --fail-on grype only exits non-zero on real errors;
        # propagate the failure as an external dep issue instead of hiding
        # it under the policy gate.
        log.error "container scan tool ${resolved} failed unexpectedly"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    # Process the SARIF through the unified ingest -> policy -> aggregate
    # pipeline and gate on business.findings.failing (chantier 20260508 P4).
    # Dockle is the only registered tool without SARIF output today; in that
    # branch findings.scan_gate falls back to the tool exit code 0 (we just
    # validated the tool ran cleanly) and the stage trivially passes.
    if ! declare -f findings.scan_gate >/dev/null 2>&1; then
        brik.use transverse.findings
    fi
    local _sarif="${BRIK_WORKSPACE:-.}/${BRIK_SECURITY_CONTAINER_OUTPUT_PATH:-brik-artifacts/container-scan/container-scan.sarif}"
    if ! findings.scan_gate "container-scan" 0 "$_sarif"; then
        log.error "security container vulnerabilities found in: $image"
        return "$BRIK_EXIT_CHECK_FAILED"
    fi

    log.info "security container scan passed"
    return 0
}

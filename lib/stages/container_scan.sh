#!/usr/bin/env bash
# @module stages/container_scan
# @description Container scan stage - post-package container image scanning.
# Runs in the scanner image after the package stage produces an image.
#
# Design note (Decision X7, Phase 4.5 Lot 7):
# stages.container_scan delegates to verify.scan.run --scans container rather
# than inlining grype/dockle invocations. Rationale:
#   1. "One scanner per stage" (final-plan §6.12) is already satisfied because
#      stages.container_scan invokes verify.scan.container.run for exactly one
#      scanner category.
#   2. verify.scan.run centralises scanner resolution (tier 1 command override,
#      tier 2 explicit tool, tier 3 registry priority); sharing that path
#      avoids duplicating the 3-tier logic between the stage and the scanner.
#   3. Inlining grype/dockle here would duplicate the scanner implementation
#      in lib/stages/verify/scan/container.sh without behaviour gain, and
#      would widen the test surface.
# The thin delegation pattern is the chosen steady state, not a step toward
# inlining.

# Container scan stage: scan a built container image for vulnerabilities.
# Usage: stages.container_scan <context_file>
stages.container_scan() {
    local context_file="$1"

    config.export_security_vars

    local image="${BRIK_SECURITY_CONTAINER_IMAGE:-}"

    if [[ -z "$image" ]]; then
        log.info "no container image configured - skipping container scan"
        context.set "$context_file" "BRIK_CONTAINER_SCAN_STATUS" "skipped"
        return 0
    fi

    log.info "container scan stage - scanning image: $image"

    local severity="${BRIK_SECURITY_CONTAINER_SEVERITY:-${BRIK_SECURITY_SEVERITY_THRESHOLD:-high}}"

    if ! declare -f verify.scan.run >/dev/null 2>&1; then
        brik.use verify.scan.scan
    fi

    local result=0
    verify.scan.run "${BRIK_WORKSPACE}" --scans "container" --image "$image" --severity "$severity" || result=$?

    context.set_result "$context_file" "BRIK_CONTAINER_SCAN_STATUS" "$result"

    return "$result"
}

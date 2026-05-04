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
    # context_file positionally passed by stage.run; unused here after §4.2
    # migration (pipeline.run records tech.status from rc; config-skip path
    # uses report.record directly).
    # shellcheck disable=SC2034
    local context_file="$1"

    config.export_security_vars

    # Source of truth: the package stage reports tech.image_built when
    # it actually produced a Docker image (lib/stages/package.sh). When
    # absent or false, container-scan does not apply (silent skip, no
    # fragment, no warning).
    local image_built="false" image_ref="" image_digest=""
    if command -v jq >/dev/null 2>&1; then
        # Read the package stage fragment directly. On GitLab each job has
        # an isolated backend, but brik-artifacts/package.json travels as
        # an artifact (declared in package.yml + pulled via needs.artifacts
        # by the container-scan job). On Jenkins the workspace is shared,
        # so the same path is also visible. Single source of truth.
        local _pkg_fragment="${BRIK_WORKSPACE:-.}/brik-artifacts/package.json"
        if [[ -f "$_pkg_fragment" ]]; then
            image_built="$(jq -r '.tech.image_built // "false"' "$_pkg_fragment" 2>/dev/null || printf 'false')"
            image_ref="$(jq -r '.tech.image_ref // ""' "$_pkg_fragment" 2>/dev/null || printf '')"
            image_digest="$(jq -r '.business.image.digest // ""' "$_pkg_fragment" 2>/dev/null || printf '')"
        fi
    fi

    # Explicit user override: a non-empty security.container.image takes
    # precedence over the package fragment inference (the user knows
    # which image to scan, e.g. a vendored release tarball).
    if [[ -n "${BRIK_SECURITY_CONTAINER_IMAGE:-}" ]]; then
        image_built="true"
        image_ref="${BRIK_SECURITY_CONTAINER_IMAGE}"
    fi

    if [[ "$image_built" != "true" ]]; then
        log.info "no container image produced by package stage - skipping container scan silently"
        return 0
    fi

    # Shift-left contract: container-scan is mandatory on a release build
    # whenever a Docker image was produced. A user-set
    # security.container_scan.enabled=false is honored only when the build
    # is not on a tag; on a tag it is forced and a log.info traces the override.
    if [[ "${BRIK_CONTAINER_SCAN_ENABLED:-true}" != "true" ]]; then
        if [[ -n "${BRIK_COMMIT_TAG:-}" ]]; then
            log.info "container-scan disabled by config but forced on release (BRIK_COMMIT_TAG=${BRIK_COMMIT_TAG})"
        else
            stage.skip_with_warning "container-scan" \
                "container-scan disabled by user (security.container_scan.enabled=false) outside release context"
            return $?
        fi
    fi

    local image="${BRIK_SECURITY_CONTAINER_IMAGE:-${image_ref}}"

    if [[ -z "$image" ]]; then
        log.info "no container image configured - skipping container scan"
        report.record "container-scan" "tech" "status" "skipped" 2>/dev/null || true
        return 0
    fi

    log.info "container scan stage - scanning image: $image"

    local severity="${BRIK_SECURITY_CONTAINER_SEVERITY:-${BRIK_SECURITY_SEVERITY_THRESHOLD:-high}}"

    if ! declare -f verify.scan.run >/dev/null 2>&1; then
        brik.use verify.scan.scan
    fi

    report.record "container-scan" "tech" "tool" "${BRIK_SECURITY_CONTAINER_TOOL:-auto}" 2>/dev/null || true
    report.record "container-scan" "tech" "target_image" "$image" 2>/dev/null || true
    if [[ -n "$image_digest" ]]; then
        report.record "container-scan" "tech" "target_digest" "$image_digest" 2>/dev/null || true
    fi

    local _scan_start_ms _scan_end_ms _scan_dur_ms _scan_rc
    _scan_start_ms="$(_helpers.epoch_ms 2>/dev/null || printf '0')"
    verify.scan.run "${BRIK_WORKSPACE}" --scans "container" --image "$image" --severity "$severity"
    _scan_rc=$?
    _scan_end_ms="$(_helpers.epoch_ms 2>/dev/null || printf '0')"
    _scan_dur_ms=$(( _scan_end_ms - _scan_start_ms ))
    [[ "$_scan_dur_ms" -lt 0 ]] && _scan_dur_ms=0
    report.record "container-scan" "tech" "scan_duration_ms" "$_scan_dur_ms" 2>/dev/null || true
    return "$_scan_rc"
}

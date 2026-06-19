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
    local image_built="false" image_ref="" image_digest="" image_pushed="false"
    if command -v jq >/dev/null 2>&1; then
        # Read the package stage fragment directly. On GitLab each job has
        # an isolated backend, but brik-artifacts/package/package.json travels as
        # an artifact (declared in package.yml + pulled via needs.artifacts
        # by the container-scan job). On Jenkins the workspace is shared,
        # so the same path is also visible. Single source of truth.
        local _pkg_fragment="${BRIK_WORKSPACE:-.}/brik-artifacts/package/package.json"
        if [[ -f "$_pkg_fragment" ]]; then
            image_built="$(jq -r '.tech.image_built // "false"' "$_pkg_fragment" 2>/dev/null || printf 'false')"
            image_ref="$(jq -r '.tech.image_ref // ""' "$_pkg_fragment" 2>/dev/null || printf '')"
            image_digest="$(jq -r '.business.image.digest // ""' "$_pkg_fragment" 2>/dev/null || printf '')"
            image_pushed="$(jq -r '.tech.image_pushed // "false"' "$_pkg_fragment" 2>/dev/null || printf 'false')"
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

    # Shift-left contract: container-scan always runs whenever a Docker
    # image was produced. The legacy security.container_scan.enabled opt-out
    # is no longer honoured (init surfaces a deprecation warning when it sees
    # the key); opting out is a business-level decision and lives outside the
    # technical layer.

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

    # Attach signed evidence to the published digest. This is the only stage
    # that holds both the image digest and the signer (cosign ships in the
    # scanner image), so the SBOM + provenance are signed here. A signing
    # failure when cosign is present is a real integrity gap and fails the
    # stage; a missing cosign is a silent skip (the deploy verifies fail-closed
    # and refuses an unsigned image there).
    if [[ -n "$image_digest" && "$image_pushed" == "true" ]]; then
        local _ref="${image%:*}@${image_digest}"
        if ! _stages.container_scan._sign_evidence "$_ref" && [[ "$_scan_rc" -eq 0 ]]; then
            _scan_rc="$BRIK_EXIT_EXTERNAL_FAIL"
        fi
    elif [[ -n "$image_digest" ]]; then
        # A digest without a push this run is daemon residue (byte-identical
        # rebuild): there is nothing in the registry to attach evidence to.
        log.info "image not published this run - skipping evidence signing"
    fi
    return "$_scan_rc"
}

# Generate the SBOM and SLSA provenance for the published digest and attach them
# as signed cosign attestations. Returns 0 (skip) when no signer is on the
# runner; returns non-zero only when signing is attempted and fails.
# Usage: _stages.container_scan._sign_evidence <name@sha256:...>
_stages.container_scan._sign_evidence() {
    local ref="$1"

    brik.use transverse.attest
    if ! attest.available; then
        log.info "cosign not on PATH - skipping evidence signing (deploy verifies fail-closed)"
        return 0
    fi
    if ! command -v syft >/dev/null 2>&1; then
        log.warn "syft not on PATH - cannot produce an SBOM to sign; skipping"
        return 0
    fi

    local _ev_dir="${BRIK_LOG_DIR:-${BRIK_WORKSPACE:-.}/.brik-logs}/evidence"
    mkdir -p "$_ev_dir" || { log.error "cannot create evidence dir: $_ev_dir"; return "$BRIK_EXIT_IO_FAILURE"; }
    local _sbom="${_ev_dir}/sbom.cyclonedx.json"
    local _prov="${_ev_dir}/provenance.slsa.json"

    log.info "generating SBOM for ${ref}"
    if ! syft "$ref" -o "cyclonedx-json=${_sbom}" >/dev/null 2>&1; then
        log.error "syft failed to generate an SBOM for ${ref}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    # Builder identity, the brik convention require_attestation verifies:
    # <orchestrator-url>/-/brik/<runner-class>, plus the brik version as
    # builder.version.brik. The runner class comes from the registry (the
    # class this stage's manifest declares), never from the environment.
    local _runner_class=""
    brik.use registry.registry 2>/dev/null || true
    if declare -f registry.stage.runner_class >/dev/null 2>&1; then
        _runner_class="$(registry.stage.runner_class container-scan 2>/dev/null || printf '')"
    fi
    [[ -z "$_runner_class" ]] && _runner_class="unknown"

    if ! attest.provenance_predicate \
            --version "${BRIK_COMMIT_TAG:-${BRIK_COMMIT_SHORT_SHA:-unknown}}" \
            --commit  "${BRIK_COMMIT_SHA:-unknown}" \
            --repo    "git+${BRIK_COMMIT_REPO_URL:-unknown}" \
            --builder "${BRIK_ORCHESTRATOR_URL:-https://brik.sh/local}/-/brik/${_runner_class}" \
            --brik-version "${BRIK_VERSION:-unknown}" \
            --run-id  "${BRIK_RUN_ID:-${BRIK_PIPELINE_ID:-unknown}}" \
            > "$_prov"; then
        log.error "failed to build the provenance predicate for ${ref}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    attest.sign "$ref" --sbom "$_sbom" --provenance "$_prov" || return $?

    report.record "container-scan" "tech" "signed" "true" 2>/dev/null || true
    report.record "container-scan" "tech" "attestation_subject" "$ref" 2>/dev/null || true

    _stages.container_scan._record_evidence "$ref" "$_sbom" "$_prov" || return $?
    return 0
}

# Record BuildEvidence for the signed digest in the configured state-repo.
# Self-skips when no artifacts.evidence.repo is configured (the attestations on
# the digest stand on their own); a configured publish that fails is an error.
# Usage: _stages.container_scan._record_evidence <ref> <sbom> <provenance>
_stages.container_scan._record_evidence() {
    local ref="$1" sbom="$2" prov="$3"

    brik.use transverse.config
    local _repo _branch _token_var _sign
    _repo="$(config.get '.artifacts.evidence.repo' '' 2>/dev/null || printf '')"
    if [[ -z "$_repo" ]]; then
        return 0
    fi
    _branch="$(config.get '.artifacts.evidence.branch' '' 2>/dev/null || printf '')"
    _token_var="$(config.get '.artifacts.evidence.token_var' '' 2>/dev/null || printf '')"
    brik.use transverse.state_repo
    _token_var="$(transverse.state_repo.token_var "$_repo" "$_token_var")" || return "$?"
    _sign="$(config.get '.artifacts.evidence.sign' 'false' 2>/dev/null || printf 'false')"

    local _digest="${ref#*@}"
    local _version="${BRIK_COMMIT_TAG:-${BRIK_COMMIT_SHORT_SHA:-unknown}}"

    brik.use transverse.evidence
    local -a _pub=(--repo "$_repo" --version "$_version" --digest "$_digest")
    [[ -n "$_branch" ]]    && _pub+=(--branch "$_branch")
    [[ -n "$_token_var" ]] && _pub+=(--token-var "$_token_var")
    [[ "$_sign" == "true" ]] && _pub+=(--sign)

    if ! evidence.build \
            --version "$_version" --digest "$_digest" \
            --commit "${BRIK_COMMIT_SHA:-unknown}" \
            --run-id "${BRIK_RUN_ID:-${BRIK_PIPELINE_ID:-unknown}}" \
            --platform "${BRIK_PLATFORM:-local}" \
            --sbom-ref "$(basename "$sbom")" \
            --provenance-ref "$(basename "$prov")" \
            --version-ref "${BRIK_COMMIT_TAG:-}" \
            | evidence.publish "${_pub[@]}"; then
        log.error "failed to record BuildEvidence for ${ref}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi
    report.record "container-scan" "tech" "evidence_recorded" "true" 2>/dev/null || true
    return 0
}

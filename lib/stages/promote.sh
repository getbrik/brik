#!/usr/bin/env bash
# @module stages.promote
# @description Phase 9.B Docker promote. Moves a candidate image from
#   release.candidate.docker.registry to release.release.docker.registry
#   on a release context. The candidate is identified by digest; the
#   release ref is tagged with the project version (BRIK_PROJECT_VERSION)
#   and 'latest'. Records the candidate+release refs and digests so
#   downstream stages (deploy) can consume BRIK_PROMOTED_IMAGE_REF
#   without re-querying the registry.
#
# Contract: this stage is gated by gate.contexts=[release] in the registry
# manifest, so the planner only schedules it on a tag push. The dispatcher
# also enforces dry-run honoring via BRIK_DRY_RUN=true.

# Guard against double-sourcing.
[[ -n "${_BRIK_STAGE_PROMOTE_LOADED:-}" ]] && return 0
_BRIK_STAGE_PROMOTE_LOADED=1

# Log in to a Docker registry when per-zone credentials are configured.
# Mirrors the publish login in package-managers/docker.sh. No-op when the
# username/password vars are empty (anonymous-access registry).
# Args: $1 registry, $2 username_var name, $3 password_var name.
_promote.docker_login() {
    local registry="$1" username_var="$2" password_var="$3"
    [[ -z "$username_var" || -z "$password_var" ]] && return 0
    brik.use transverse.secrets
    brik.use transverse.env
    transverse.secrets.require_var "$username_var" "docker username" || return "$?"
    transverse.secrets.require_var "$password_var" "docker password" || return "$?"
    local _u _p
    _u="$(transverse.env.resolve_indirect "$username_var")"
    _p="$(transverse.env.resolve_indirect "$password_var")"
    log.info "stages.promote: logging in to ${registry}"
    printf '%s' "$_p" | docker login "$registry" --username "$_u" --password-stdin >/dev/null 2>&1 || {
        log.error "stages.promote: docker login to ${registry} failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }
    return 0
}

stages.promote() {
    brik.use transverse.config
    brik.use pipeline.report

    # Self-gate against snapshot context. The plan-driven path
    # (BRIK_PLAN_FILE) already filters this via gate.contexts=[release],
    # but the legacy `pipeline.run` path (no plan) does not enforce
    # contexts. Skipping silently here keeps promote a no-op in feature
    # pipelines without forcing users into --auto-select on day one.
    if [[ -z "${BRIK_COMMIT_TAG:-}" ]]; then
        report.record "promote" "tech" "status" "skipped"        || true
        report.record "promote" "tech" "kind"   "not-applicable" || true
        report.record "promote" "business" "reason" "not-a-release-context" || true
        return 0
    fi

    local candidate_registry candidate_image release_registry release_image
    candidate_registry="$(config.get '.release.candidate.docker.registry' '')"
    candidate_image="$(config.get '.release.candidate.docker.image' '')"
    release_registry="$(config.get '.release.release.docker.registry' '')"
    release_image="$(config.get '.release.release.docker.image' '')"

    local candidate_username_var candidate_password_var release_username_var release_password_var
    candidate_username_var="$(config.get '.release.candidate.docker.username_var' '')"
    candidate_password_var="$(config.get '.release.candidate.docker.password_var' '')"
    release_username_var="$(config.get '.release.release.docker.username_var' '')"
    release_password_var="$(config.get '.release.release.docker.password_var' '')"

    # Opt-in gate. A project that declares no release.{candidate,release}
    # .docker config has not opted into the 2-zone Docker promotion
    # model, so promote is not applicable -- skip gracefully. Without
    # this, the promote stage (a builtin since 9.B) would hard-fail the
    # release pipeline of every project that does not use promotion.
    if [[ -z "$candidate_registry" && -z "$candidate_image" \
          && -z "$release_registry" && -z "$release_image" ]]; then
        log.info "stages.promote: no release Docker promotion config; skipping"
        report.record "promote" "tech" "status" "skipped"        || true
        report.record "promote" "tech" "kind"   "not-applicable" || true
        report.record "promote" "business" "reason" "no-docker-promotion-config" || true
        return 0
    fi

    # Past the opt-in gate a partial config IS an error: the project
    # asked for promotion but did not fully describe both zones.
    if [[ -z "$candidate_registry" || -z "$candidate_image" ]]; then
        log.error "stages.promote: .release.candidate.docker.{registry,image} are required"
        report.record "promote" "tech" "status" "failure" || true
        report.record "promote" "tech" "kind"   "config-error" || true
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    if [[ -z "$release_registry" || -z "$release_image" ]]; then
        log.error "stages.promote: .release.release.docker.{registry,image} are required"
        report.record "promote" "tech" "status" "failure" || true
        report.record "promote" "tech" "kind"   "config-error" || true
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    local version="${BRIK_PROJECT_VERSION:-0.0.0}"
    if [[ "$version" == "0.0.0" ]]; then
        log.warn "stages.promote: BRIK_PROJECT_VERSION is 0.0.0; promote on a tag push is expected"
    fi

    local candidate_ref="${candidate_registry}/${candidate_image}:${version}"
    local release_ref="${release_registry}/${release_image}:${version}"
    local release_latest="${release_registry}/${release_image}:latest"

    log.info "promoting ${candidate_ref} -> ${release_ref}"

    if [[ "${BRIK_DRY_RUN:-false}" == "true" ]]; then
        log.info "[dry-run] docker pull ${candidate_ref}"
        log.info "[dry-run] docker tag ${candidate_ref} ${release_ref}"
        log.info "[dry-run] docker tag ${candidate_ref} ${release_latest}"
        log.info "[dry-run] docker push ${release_ref}"
        log.info "[dry-run] docker push ${release_latest}"
        report.record "promote" "tech"     "status"           "success"        || true
        report.record "promote" "tech"     "kind"             "dry-run"        || true
        report.record "promote" "business" "candidate_ref"    "$candidate_ref" || true
        report.record "promote" "business" "candidate_digest" "sha256:dry-run" || true
        report.record "promote" "business" "release_ref"      "$release_ref"   || true
        report.record "promote" "business" "release_digest"   "sha256:dry-run" || true
        report.record "promote" "env"      "BRIK_PROMOTED_IMAGE_REF" "$release_ref" || true
        return 0
    fi

    if ! command -v docker >/dev/null 2>&1; then
        log.error "stages.promote: docker not found on PATH"
        report.record "promote" "tech" "status" "failure" || true
        report.record "promote" "tech" "kind"   "missing-tool" || true
        return "$BRIK_EXIT_MISSING_DEP"
    fi

    if ! _promote.docker_login "$candidate_registry" "$candidate_username_var" "$candidate_password_var"; then
        report.record "promote" "tech" "status" "failure" || true
        report.record "promote" "tech" "kind"   "auth-failed" || true
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    if ! docker pull "$candidate_ref" >/dev/null 2>&1; then
        log.error "stages.promote: docker pull ${candidate_ref} failed"
        report.record "promote" "tech" "status" "failure" || true
        report.record "promote" "tech" "kind"   "candidate-not-found" || true
        return "$BRIK_EXIT_FAILURE"
    fi

    local candidate_digest
    candidate_digest="$(docker inspect --format '{{index .RepoDigests 0}}' "$candidate_ref" 2>/dev/null \
                      | sed 's/.*@//')"
    [[ -z "$candidate_digest" ]] && candidate_digest="unknown"

    if ! _promote.docker_login "$release_registry" "$release_username_var" "$release_password_var"; then
        report.record "promote" "tech" "status" "failure" || true
        report.record "promote" "tech" "kind"   "auth-failed" || true
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    docker tag "$candidate_ref" "$release_ref"
    docker tag "$candidate_ref" "$release_latest"
    if ! docker push "$release_ref" >/dev/null 2>&1; then
        log.error "stages.promote: docker push ${release_ref} failed"
        report.record "promote" "tech" "status" "failure" || true
        report.record "promote" "tech" "kind"   "push-failed" || true
        return "$BRIK_EXIT_FAILURE"
    fi
    if ! docker push "$release_latest" >/dev/null 2>&1; then
        log.warn "stages.promote: docker push ${release_latest} failed (continuing; the versioned tag landed)"
    fi

    local release_digest
    release_digest="$(docker inspect --format '{{index .RepoDigests 0}}' "$release_ref" 2>/dev/null \
                    | sed 's/.*@//')"
    [[ -z "$release_digest" ]] && release_digest="$candidate_digest"

    report.record "promote" "tech"     "status"           "success"           || true
    report.record "promote" "business" "candidate_ref"    "$candidate_ref"    || true
    report.record "promote" "business" "candidate_digest" "$candidate_digest" || true
    report.record "promote" "business" "release_ref"      "$release_ref"      || true
    report.record "promote" "business" "release_digest"   "$release_digest"   || true
    report.record "promote" "env"      "BRIK_PROMOTED_IMAGE_REF" "$release_ref" || true

    return 0
}

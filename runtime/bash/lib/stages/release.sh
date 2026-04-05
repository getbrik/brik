#!/usr/bin/env bash
# @module stages/release
# @description Release stage - semantic version calculation + optional changelog and tag.

# Release stage: compute version from git tags, optionally generate changelog and tag.
# Usage: stages.release <context_file>
stages.release() {
    local context_file="$1"

    config.export_release_vars

    log.info "release stage - computing version"

    brik.use version
    brik.use git

    local strategy="${BRIK_RELEASE_STRATEGY:-semver}"
    local tag_prefix="${BRIK_RELEASE_TAG_PREFIX:-v}"

    log.info "release strategy: $strategy, tag prefix: $tag_prefix"

    local current_version
    current_version="$(version.current --from-git-tag --prefix "$tag_prefix")" || {
        log.info "no git tag found, using 0.0.0"
        current_version="0.0.0"
    }

    log.info "current version: $current_version"
    export BRIK_VERSION="$current_version"
    context.set "$context_file" "BRIK_VERSION" "$current_version"

    # If on a tag (release trigger), prepare and finalize if release module available
    if [[ -n "${BRIK_TAG:-}" ]]; then
        brik.use release

        local changelog_enabled="${BRIK_RELEASE_CHANGELOG_ENABLED:-true}"
        local -a prepare_args=("$current_version")
        if [[ "$changelog_enabled" == "true" ]]; then
            prepare_args+=(--changelog)
            [[ -n "${BRIK_RELEASE_CHANGELOG_FILE:-}" ]] && \
                prepare_args+=(--changelog-file "$BRIK_RELEASE_CHANGELOG_FILE")
        fi

        local rc=0
        release.prepare "${prepare_args[@]}" || rc=$?
        [[ $rc -ne 0 ]] && log.warn "release.prepare skipped or failed (rc=$rc)"

        rc=0
        release.finalize "$current_version" --tag-prefix "$tag_prefix" || rc=$?
        [[ $rc -ne 0 ]] && log.warn "release.finalize skipped or failed (rc=$rc)"
    fi

    return 0
}

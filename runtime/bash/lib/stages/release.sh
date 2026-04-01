#!/usr/bin/env bash
# @module stages/release
# @description Release stage - semantic version calculation.

# Release stage: compute version from git tags using config.
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
    current_version="$(version.current --from-git-tag --prefix "$tag_prefix" 2>/dev/null)" || {
        log.info "no git tag found, using 0.0.0"
        current_version="0.0.0"
    }

    log.info "current version: $current_version"
    context.set "$context_file" "BRIK_VERSION" "$current_version"

    return 0
}

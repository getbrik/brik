#!/usr/bin/env bash
# @module stages/release
# @description Release stage - semantic version calculation.

# Release stage: compute version from git tags.
# Usage: stages.release <context_file>
stages.release() {
    local context_file="$1"

    log.info "release stage - computing version"

    brik.use version
    brik.use git

    local current_version
    current_version="$(version.current --from-git-tag 2>/dev/null)" || {
        log.info "no git tag found, using 0.0.0"
        current_version="0.0.0"
    }

    log.info "current version: $current_version"
    context.set "$context_file" "BRIK_VERSION" "$current_version"

    return 0
}

#!/usr/bin/env bash
# @module stages/package
# @description Package stage - container build.

# Package stage: container build (stub for MVP).
# Usage: stages.package <context_file>
stages.package() {
    local context_file="$1"

    log.info "package stage - container build"
    log.warn "package stage is a stub - full implementation in M3"
    context.set "$context_file" "BRIK_PACKAGE_STATUS" "skipped"
    return 0
}

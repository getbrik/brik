#!/usr/bin/env bash
# @module stages/security
# @description Security stage - dependency and secret scanning.

# Security stage: dependency and secret scanning (stub for MVP).
# Usage: stages.security <context_file>
stages.security() {
    local context_file="$1"

    log.info "security stage - dependency and secret scanning"
    log.warn "security stage is a stub - full implementation in M3"
    context.set "$context_file" "BRIK_SECURITY_STATUS" "skipped"
    return 0
}

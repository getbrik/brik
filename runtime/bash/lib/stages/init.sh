#!/usr/bin/env bash
# @module stages/init
# @description Init stage - detect stack, validate config, setup environment.

# Init stage: detect stack, validate config, setup environment.
# Usage: stages.init <context_file>
stages.init() {
    local context_file="$1"

    log.info "initializing pipeline"

    # Validate brik.yml exists
    if [[ ! -f "${BRIK_CONFIG_FILE}" ]]; then
        log.error "brik.yml not found at ${BRIK_CONFIG_FILE}"
        return 7
    fi

    # Detect or read stack
    local stack
    stack="$(config.get '.project.stack' 'auto')"

    if [[ "$stack" == "auto" ]]; then
        brik.use build
        stack="$(build.detect_stack "${BRIK_WORKSPACE}")" || {
            log.warn "could not auto-detect stack, continuing without stack-specific defaults"
            stack="unknown"
        }
        log.info "auto-detected stack: $stack"
    else
        log.info "configured stack: $stack"
    fi

    context.set "$context_file" "BRIK_STACK" "$stack"

    # Export config and override stack with the runtime-resolved value.
    # config.export_build_vars re-reads .project.stack from brik.yml, which may
    # be "auto". The init-resolved $stack (e.g. "node") must take precedence.
    config.export_all || return $?
    export BRIK_BUILD_STACK="$stack"
    config.validate_coherence || return $?

    # Log project info
    local project_name
    project_name="$(config.get '.project.name' 'unnamed')"
    log.info "project: $project_name"
    log.info "workspace: ${BRIK_WORKSPACE}"
    log.info "platform: ${BRIK_PLATFORM:-unknown}"

    # Verify required tools
    if ! command -v yq >/dev/null 2>&1; then
        log.error "yq is required but not available"
        return 3
    fi

    log.info "init stage complete"
    return 0
}

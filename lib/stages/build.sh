#!/usr/bin/env bash
# @module stages/build
# @description Build stage - compile/build via stack-specific modules.

# Build stage: compile/build via brik-lib.
# Usage: stages.build <context_file>
stages.build() {
    # context_file positionally passed by stage.run; unused here after §4.2
    # migration (pipeline.run records tech.status from rc).
    # shellcheck disable=SC2034
    local context_file="$1"

    config.export_build_vars

    local stack="${BRIK_BUILD_STACK:-auto}"
    local result=0

    pipeline.require_dir "${BRIK_WORKSPACE}" || return $?

    # Auto-detect stack if not explicitly set.
    if [[ -z "$stack" || "$stack" == "auto" ]]; then
        brik.use stacks._detect
        stack="$(stacks.detect "${BRIK_WORKSPACE}")" || return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    log.info "running build (stack=$stack)"

    # Custom build command override bypasses the stack module.
    if [[ -n "${BRIK_BUILD_COMMAND:-}" ]]; then
        log.info "using custom build command: $BRIK_BUILD_COMMAND"
        (cd "${BRIK_WORKSPACE}" && eval "$BRIK_BUILD_COMMAND") || result=$?
        return "$result"
    fi

    # Load and delegate to the stack-specific module.
    if ! brik.use "stacks.${stack}"; then
        log.error "unsupported build stack: $stack"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    local build_fn="stacks.${stack}.build"
    if ! declare -f "$build_fn" >/dev/null 2>&1; then
        log.error "build function not found: $build_fn"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    # Pass BRIK_BUILD_TOOL to stack module if set and not 'auto'.
    local tool_args=()
    if [[ -n "${BRIK_BUILD_TOOL:-}" && "${BRIK_BUILD_TOOL}" != "auto" ]]; then
        tool_args=(--tool "$BRIK_BUILD_TOOL")
    fi

    # pipeline.run records tech.status from our rc (see commit cf719f5).
    "$build_fn" "${BRIK_WORKSPACE}" "${tool_args[@]}"
}

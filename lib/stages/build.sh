#!/usr/bin/env bash
# @module stages/build
# @description Build stage - compile/build via stack-specific modules.

# Build stage: compile/build via brik-lib.
# Usage: stages.build <context_file>
stages.build() {
    local context_file="$1"

    config.export_build_vars

    local stack="${BRIK_BUILD_STACK:-auto}"
    local result=0

    pipeline.require_dir "${BRIK_WORKSPACE}" || {
        result=$?
        context.set_result "$context_file" "BRIK_BUILD_STATUS" "$result"
        return "$result"
    }

    # Auto-detect stack if not explicitly set.
    if [[ -z "$stack" || "$stack" == "auto" ]]; then
        brik.use stacks._detect
        stack="$(stacks.detect "${BRIK_WORKSPACE}")" || {
            result="$BRIK_EXIT_CONFIG_ERROR"
            context.set_result "$context_file" "BRIK_BUILD_STATUS" "$result"
            return "$result"
        }
    fi

    log.info "running build (stack=$stack)"

    # Custom build command override bypasses the stack module.
    if [[ -n "${BRIK_BUILD_COMMAND:-}" ]]; then
        log.info "using custom build command: $BRIK_BUILD_COMMAND"
        (cd "${BRIK_WORKSPACE}" && eval "$BRIK_BUILD_COMMAND") || result=$?
        context.set_result "$context_file" "BRIK_BUILD_STATUS" "$result"
        return "$result"
    fi

    # Load and delegate to the stack-specific module.
    if ! brik.use "stacks.${stack}"; then
        log.error "unsupported build stack: $stack"
        result="$BRIK_EXIT_CONFIG_ERROR"
        context.set_result "$context_file" "BRIK_BUILD_STATUS" "$result"
        return "$result"
    fi

    local build_fn="stacks.${stack}.build"
    if ! declare -f "$build_fn" >/dev/null 2>&1; then
        log.error "build function not found: $build_fn"
        result="$BRIK_EXIT_CONFIG_ERROR"
        context.set_result "$context_file" "BRIK_BUILD_STATUS" "$result"
        return "$result"
    fi

    # Pass BRIK_BUILD_TOOL to stack module if set and not 'auto'.
    local tool_args=()
    if [[ -n "${BRIK_BUILD_TOOL:-}" && "${BRIK_BUILD_TOOL}" != "auto" ]]; then
        tool_args=(--tool "$BRIK_BUILD_TOOL")
    fi

    "$build_fn" "${BRIK_WORKSPACE}" "${tool_args[@]}" || result=$?

    context.set_result "$context_file" "BRIK_BUILD_STATUS" "$result"
    return "$result"
}

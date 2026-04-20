#!/usr/bin/env bash
# @module stages/build
# @description Build stage - compile/build via brik-lib.

# Build stage: compile/build via brik-lib.
# Usage: stages.build <context_file>
stages.build() {
    local context_file="$1"

    config.export_build_vars

    brik.use build

    local stack="${BRIK_BUILD_STACK:-auto}"

    # Load stack-specific module
    case "$stack" in
        node)   brik.use stacks.node ;;
        java)   brik.use stacks.java ;;
        python) brik.use stacks.python ;;
        dotnet) brik.use stacks.dotnet ;;
        rust)   brik.use stacks.rust ;;
    esac

    log.info "running build (stack=$stack)"

    local result=0
    build.run "${BRIK_WORKSPACE}" --stack "$stack" --config "${BRIK_CONFIG_FILE}" || result=$?

    context.set_result "$context_file" "BRIK_BUILD_STATUS" "$result"

    return "$result"
}

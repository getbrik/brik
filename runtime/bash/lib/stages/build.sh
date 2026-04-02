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
        node)   brik.use build.node ;;
        java)   brik.use build.java ;;
        python) brik.use build.python ;;
        dotnet) brik.use build.dotnet ;;
        rust)   brik.use build.rust ;;
    esac

    log.info "running build (stack=$stack)"

    build.run "${BRIK_WORKSPACE}" --stack "$stack" --config "${BRIK_CONFIG_FILE}"
    local result=$?

    if [[ $result -eq 0 ]]; then
        context.set "$context_file" "BRIK_BUILD_STATUS" "success"
    else
        context.set "$context_file" "BRIK_BUILD_STATUS" "failed"
    fi

    return "$result"
}

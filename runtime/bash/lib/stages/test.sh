#!/usr/bin/env bash
# @module stages/test
# @description Test stage - run tests via brik-lib.

# Test stage: run tests via brik-lib.
# Usage: stages.test <context_file>
stages.test() {
    local context_file="$1"

    brik.use test

    log.info "running tests"

    test.run "${BRIK_WORKSPACE}"
    local result=$?

    if [[ $result -eq 0 ]]; then
        context.set "$context_file" "BRIK_TEST_STATUS" "success"
    else
        context.set "$context_file" "BRIK_TEST_STATUS" "failed"
    fi

    return "$result"
}

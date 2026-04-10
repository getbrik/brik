#!/usr/bin/env bash
# @module stages/test
# @description Test stage - run tests via brik-lib.

brik.use "_deps"

# Test stage: run tests via brik-lib.
# Usage: stages.test <context_file>
stages.test() {
    local context_file="$1"

    config.export_test_vars

    brik.use test

    _brik.install_deps "${BRIK_WORKSPACE}" test

    log.info "running tests"

    local test_args=("${BRIK_WORKSPACE}")

    if [[ -n "${BRIK_TEST_FRAMEWORK:-}" ]]; then
        test_args+=(--framework "$BRIK_TEST_FRAMEWORK")
    fi

    if [[ -n "${BRIK_TEST_COMMAND_UNIT:-}" ]]; then
        log.info "unit test command: $BRIK_TEST_COMMAND_UNIT"
    fi
    if [[ -n "${BRIK_TEST_COMMAND_INTEGRATION:-}" ]]; then
        log.info "integration test command: $BRIK_TEST_COMMAND_INTEGRATION"
    fi
    if [[ -n "${BRIK_TEST_COMMAND_E2E:-}" ]]; then
        log.info "e2e test command: $BRIK_TEST_COMMAND_E2E"
    fi

    test.run "${test_args[@]}"
    local result=$?

    context.set_result "$context_file" "BRIK_TEST_STATUS" "$result"

    return "$result"
}

#!/usr/bin/env bash
# @module stages/test
# @description Test stage - run tests via stack-specific modules.

brik.use "_deps"

# Test stage: run tests via stack-specific modules.
# Usage: stages.test <context_file>
stages.test() {
    # context_file positionally passed by stage.run; unused here after §4.2
    # migration (pipeline.run records tech.status from rc).
    # shellcheck disable=SC2034
    local context_file="$1"

    config.export_test_vars

    pipeline.require_dir "${BRIK_WORKSPACE}" || return $?

    stacks.install_deps "${BRIK_WORKSPACE}" test || return $?

    log.info "running tests"

    # Log configured per-suite commands (surfaced from brik.yml, informational).
    [[ -n "${BRIK_TEST_COMMAND_UNIT:-}" ]] && log.info "unit test command: $BRIK_TEST_COMMAND_UNIT"
    [[ -n "${BRIK_TEST_COMMAND_INTEGRATION:-}" ]] && log.info "integration test command: $BRIK_TEST_COMMAND_INTEGRATION"
    [[ -n "${BRIK_TEST_COMMAND_E2E:-}" ]] && log.info "e2e test command: $BRIK_TEST_COMMAND_E2E"

    # Tier 1: explicit test command override bypasses stack resolution.
    if [[ -n "${BRIK_TEST_COMMAND:-}" ]]; then
        log.info "running tests (command override): $BRIK_TEST_COMMAND"
        local exit_code=0
        (cd "${BRIK_WORKSPACE}" && eval "$BRIK_TEST_COMMAND") || exit_code=$?
        if [[ "$exit_code" -ne 0 ]]; then
            log.error "tests failed with exit code $exit_code"
            return "$BRIK_EXIT_CHECK_FAILED"
        fi
        log.info "tests passed"
        return 0
    fi

    # Tier 2/3: resolve stack from framework name or workspace marker files.
    brik.use stacks._detect
    local stack=""
    if [[ -n "${BRIK_TEST_FRAMEWORK:-}" ]]; then
        stack="$(stacks.detect_from_framework "$BRIK_TEST_FRAMEWORK")" || {
            log.error "unsupported test framework: $BRIK_TEST_FRAMEWORK"
            return "$BRIK_EXIT_CONFIG_ERROR"
        }
    else
        stack="$(stacks.detect "${BRIK_WORKSPACE}")" || return "$BRIK_EXIT_MISSING_DEP"
    fi

    if ! brik.use "stacks.${stack}"; then
        log.error "no test module: $stack"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    local test_cmd=""
    if [[ -n "${BRIK_TEST_FRAMEWORK:-}" ]]; then
        test_cmd="$(stacks."${stack}".test_cmd "$BRIK_TEST_FRAMEWORK" "${BRIK_WORKSPACE}" "")" || return $?
    else
        test_cmd="$(stacks."${stack}".test "${BRIK_WORKSPACE}" "")" || return $?
    fi

    log.info "running tests: $test_cmd"

    local exit_code2=0
    (cd "${BRIK_WORKSPACE}" && eval "$test_cmd") || exit_code2=$?
    if [[ "$exit_code2" -ne 0 ]]; then
        log.error "tests failed with exit code $exit_code2"
        return "$BRIK_EXIT_CHECK_FAILED"
    fi
    log.info "tests passed"
    # pipeline.run records tech.status=success from rc (see commit cf719f5).
    return 0
}

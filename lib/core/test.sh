#!/usr/bin/env bash
# @module test
# @description Test execution functions for brik-lib.
# Dispatches to stack-specific modules in test/<stack>.sh.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_TEST_LOADED:-}" ]] && return 0
_BRIK_CORE_TEST_LOADED=1

# Load a stack-specific test module via brik.use.
# Returns 7 if module not found.
_stacks._load() {
    local stack="$1"
    brik.use "stacks.${stack}" || {
        log.error "no test module: $stack"
        return "$BRIK_EXIT_CONFIG_ERROR"
    }
}

# Map a framework name to its stack.
# Prints the stack name on stdout.
# Returns 1 for unknown frameworks.
stacks.detect_from_framework() {
    case "$1" in
        jest|npm|vitest|mocha)      printf 'node' ;;
        junit|maven|gradle)         printf 'java' ;;
        pytest|unittest|tox)        printf 'python' ;;
        cargo)                      printf 'rust' ;;
        dotnet|xunit|nunit)         printf 'dotnet' ;;
        *)                          return "$BRIK_EXIT_FAILURE" ;;
    esac
}

# Run tests in a workspace.
# Usage: test.run <workspace> [--suite <unit|integration|e2e>] [--report-dir <path>]
#        [--framework <jest|npm|junit|pytest|gradle|cargo|dotnet>]
test.run() {
    local workspace="$1"
    shift
    local suite="unit" report_dir="" framework=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --suite) suite="$2"; shift 2 ;;
            --report-dir) report_dir="$2"; shift 2 ;;
            --framework) framework="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    pipeline.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    # Tier 1: explicit command override
    if [[ -n "${BRIK_TEST_COMMAND:-}" ]]; then
        log.info "running $suite tests (command override): $BRIK_TEST_COMMAND"
        local exit_code=0
        (cd "$workspace" && eval "$BRIK_TEST_COMMAND") || exit_code=$?
        if [[ "$exit_code" -ne 0 ]]; then
            log.error "tests failed with exit code $exit_code"
            return "$BRIK_EXIT_CHECK_FAILED"
        fi
        log.info "tests passed"
        return 0
    fi

    local test_cmd=""
    if [[ -n "$framework" ]]; then
        local stack
        stack="$(stacks.detect_from_framework "$framework")" || {
            log.error "unsupported test framework: $framework"
            return "$BRIK_EXIT_CONFIG_ERROR"
        }
        _stacks._load "$stack"
        test_cmd="$(stacks."${stack}".test_cmd "$framework" "$workspace" "$report_dir")" || return $?
    else
        local stack
        brik.use build
        stack="$(stacks.detect "$workspace")" || return "$BRIK_EXIT_MISSING_DEP"
        _stacks._load "$stack"
        test_cmd="$(stacks."${stack}".test "$workspace" "$report_dir")" || return $?
    fi

    log.info "running $suite tests: $test_cmd"

    if [[ -n "$report_dir" ]]; then
        mkdir -p "$report_dir" || return "$BRIK_EXIT_IO_FAILURE"
        export JEST_JUNIT_OUTPUT_DIR="$report_dir"
    fi

    local exit_code2=0
    (cd "$workspace" && eval "$test_cmd") || exit_code2=$?
    if [[ "$exit_code2" -ne 0 ]]; then
        log.error "tests failed with exit code $exit_code2"
        return "$BRIK_EXIT_CHECK_FAILED"
    fi

    log.info "tests passed"
    return 0
}

#!/usr/bin/env bash
# @module test
# @description Test execution functions for brik-lib.
# Dispatches to stack-specific modules in test/<stack>.sh.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_TEST_LOADED:-}" ]] && return 0
_BRIK_CORE_TEST_LOADED=1

# Load a stack-specific test module via brik.use.
# Returns 7 if module not found.
_test._load_stack() {
    local stack="$1"
    brik.use "test.${stack}" || {
        log.error "no test module: $stack"
        return "$BRIK_EXIT_CONFIG_ERROR"
    }
}

# Map a framework name to its stack.
# Prints the stack name on stdout.
# Returns 1 for unknown frameworks.
_test._stack_for_framework() {
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

    runtime.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    # Tier 1: explicit command override
    if [[ -n "${BRIK_TEST_COMMAND:-}" ]]; then
        log.info "running $suite tests (command override): $BRIK_TEST_COMMAND"
        (cd "$workspace" && eval "$BRIK_TEST_COMMAND") || {
            local exit_code=$?
            log.error "tests failed with exit code $exit_code"
            return "$BRIK_EXIT_CHECK_FAILED"
        }
        log.info "tests passed"
        return 0
    fi

    local test_cmd=""
    if [[ -n "$framework" ]]; then
        local stack
        stack="$(_test._stack_for_framework "$framework")" || {
            log.error "unsupported test framework: $framework"
            return "$BRIK_EXIT_CONFIG_ERROR"
        }
        _test._load_stack "$stack"
        test_cmd="$(test."${stack}".cmd "$framework" "$workspace" "$report_dir")" || return $?
    else
        local stack
        brik.use build
        stack="$(build.detect_stack "$workspace")" || return "$BRIK_EXIT_MISSING_DEP"
        _test._load_stack "$stack"
        test_cmd="$(test."${stack}".run_cmd "$workspace" "$report_dir")" || return $?
    fi

    log.info "running $suite tests: $test_cmd"

    if [[ -n "$report_dir" ]]; then
        mkdir -p "$report_dir" || return "$BRIK_EXIT_IO_FAILURE"
        export JEST_JUNIT_OUTPUT_DIR="$report_dir"
    fi

    (cd "$workspace" && eval "$test_cmd") || {
        local exit_code=$?
        log.error "tests failed with exit code $exit_code"
        return "$BRIK_EXIT_CHECK_FAILED"
    }

    log.info "tests passed"
    return 0
}

# Publish a test report to the log directory.
# Usage: test.publish_report <report_path> [--format <junit|tap>]
test.publish_report() {
    local report_path="$1"
    shift
    local format="junit"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) format="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ ! -f "$report_path" ]]; then
        log.error "report file not found: $report_path"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    local reports_dir="${BRIK_LOG_DIR:-${BRIK_DEFAULT_LOG_DIR:-/tmp/brik/logs}}/reports"
    mkdir -p "$reports_dir" || return "$BRIK_EXIT_IO_FAILURE"

    local dest
    dest="${reports_dir}/$(basename "$report_path")"
    cp "$report_path" "$dest" || {
        log.error "cannot copy report to: $dest"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    log.info "test report published: $dest (format: $format)"
    return 0
}

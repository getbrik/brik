#!/usr/bin/env bash
# @module test
# @description Test execution functions for brik-lib.
# Dispatches to stack-specific modules in test/<stack>.sh.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_TEST_LOADED:-}" ]] && return 0
_BRIK_CORE_TEST_LOADED=1

# Directory containing stack-specific test modules
_BRIK_TEST_DIR="${BASH_SOURCE[0]%/*}/test"

# Detect the stack from workspace marker files.
# Prints the stack name on stdout.
# Returns 1 if no stack detected.
_test._detect_stack() {
    local workspace="$1"

    if [[ -f "${workspace}/package.json" ]]; then
        printf 'node'
    elif [[ -f "${workspace}/build.gradle" || -f "${workspace}/build.gradle.kts" ]]; then
        printf 'java'
    elif [[ -f "${workspace}/pom.xml" ]]; then
        printf 'java'
    elif [[ -f "${workspace}/pyproject.toml" || -f "${workspace}/setup.py" ]]; then
        printf 'python'
    elif [[ -f "${workspace}/Cargo.toml" ]]; then
        printf 'rust'
    elif ls "${workspace}"/*.csproj >/dev/null 2>&1 || ls "${workspace}"/*.sln >/dev/null 2>&1; then
        printf 'dotnet'
    else
        return 1
    fi
    return 0
}

# Load a stack-specific test module.
# Returns 7 if module not found.
_test._load_stack() {
    local stack="$1"
    local module_path="${_BRIK_TEST_DIR}/${stack}.sh"

    if [[ -f "$module_path" ]]; then
        # shellcheck source=/dev/null
        . "$module_path"
    else
        log.error "no test module: $stack"
        return 7
    fi
}

# Map a framework name to its stack.
# Prints the stack name on stdout.
# Returns 1 for unknown frameworks.
_test._stack_for_framework() {
    case "$1" in
        jest|npm)       printf 'node' ;;
        junit|maven)    printf 'java' ;;
        gradle)         printf 'java' ;;
        pytest)         printf 'python' ;;
        cargo)          printf 'rust' ;;
        dotnet)         printf 'dotnet' ;;
        *)              return 1 ;;
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
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    runtime.require_dir "$workspace" || return 6

    local test_cmd=""
    if [[ -n "$framework" ]]; then
        local stack
        stack="$(_test._stack_for_framework "$framework")" || {
            log.error "unsupported test framework: $framework"
            return 7
        }
        _test._load_stack "$stack"
        test_cmd="$(test."${stack}".cmd "$framework" "$workspace" "$report_dir")" || return $?
    else
        local stack
        stack="$(_test._detect_stack "$workspace")" || {
            log.error "cannot detect test framework for workspace: $workspace"
            return 3
        }
        _test._load_stack "$stack"
        test_cmd="$(test."${stack}".run_cmd "$workspace" "$report_dir")" || return $?
    fi

    log.info "running $suite tests: $test_cmd"

    if [[ -n "$report_dir" ]]; then
        mkdir -p "$report_dir" || return 6
        export JEST_JUNIT_OUTPUT_DIR="$report_dir"
    fi

    (cd "$workspace" && eval "$test_cmd") || {
        local exit_code=$?
        log.error "tests failed with exit code $exit_code"
        return 10
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
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    if [[ ! -f "$report_path" ]]; then
        log.error "report file not found: $report_path"
        return 6
    fi

    local reports_dir="${BRIK_LOG_DIR:-/tmp/brik/logs}/reports"
    mkdir -p "$reports_dir" || return 6

    local dest
    dest="${reports_dir}/$(basename "$report_path")"
    cp "$report_path" "$dest" || {
        log.error "cannot copy report to: $dest"
        return 6
    }

    log.info "test report published: $dest (format: $format)"
    return 0
}

#!/usr/bin/env bash
# @module test
# @description Test execution functions for brik-lib.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_TEST_LOADED:-}" ]] && return 0
_BRIK_CORE_TEST_LOADED=1

# Run tests in a workspace.
# Usage: test.run <workspace> [--suite <unit|integration|e2e>] [--report-dir <path>]
test.run() {
    local workspace="$1"
    shift
    local suite="unit" report_dir=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --suite) suite="$2"; shift 2 ;;
            --report-dir) report_dir="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    runtime.require_dir "$workspace" || return 6

    # Detect test runner based on workspace
    local test_cmd=""
    if [[ -f "${workspace}/package.json" ]]; then
        # Node.js project - use npm test or npx jest
        if command -v npx >/dev/null 2>&1; then
            test_cmd="npx jest"
            if [[ -n "$report_dir" ]]; then
                test_cmd="$test_cmd --reporters=default --reporters=jest-junit"
            fi
        else
            test_cmd="npm test"
        fi
    elif [[ -f "${workspace}/pom.xml" ]]; then
        test_cmd="mvn test"
    elif [[ -f "${workspace}/pyproject.toml" || -f "${workspace}/setup.py" ]]; then
        test_cmd="python -m pytest"
        if [[ -n "$report_dir" ]]; then
            test_cmd="$test_cmd --junitxml=${report_dir}/report.xml"
        fi
    else
        log.error "cannot detect test framework for workspace: $workspace"
        return 3
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

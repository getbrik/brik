#!/usr/bin/env bash
# @module test.python
# @requires python
# @description Test commands for Python projects.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_TEST_PYTHON_LOADED:-}" ]] && return 0
_BRIK_CORE_TEST_PYTHON_LOADED=1

# Build the test command for a given Python framework.
# Usage: test.python.cmd <framework> <workspace> <report_dir>
# Frameworks: pytest, unittest, tox
test.python.cmd() {
    local framework="$1" workspace="$2" report_dir="$3"
    local cmd=""

    case "$framework" in
        pytest)
            cmd="python -m pytest"
            [[ -n "$report_dir" ]] && cmd="$cmd --junitxml=${report_dir}/report.xml"
            ;;
        unittest)
            cmd="python -m unittest discover"
            ;;
        tox)
            cmd="tox"
            ;;
        *)
            log.error "unsupported Python test framework: $framework"
            return 7
            ;;
    esac

    printf '%s' "$cmd"
    return 0
}

# Auto-detect and return the test command for a Python workspace.
# Usage: test.python.run_cmd <workspace> <report_dir>
test.python.run_cmd() {
    local workspace="$1" report_dir="$2"

    test.python.cmd "pytest" "$workspace" "$report_dir"
}

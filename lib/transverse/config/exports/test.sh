#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.config.exports.test
# @description Exports BRIK_TEST_* variables from brik.yml.

# Guard against double-sourcing
[[ -n "${_BRIK_CONFIG_EXPORTS_TEST_LOADED:-}" ]] && return 0
_BRIK_CONFIG_EXPORTS_TEST_LOADED=1

# Export test-related variables from brik.yml.
# Sets: BRIK_TEST_FRAMEWORK, BRIK_TEST_COMMAND_*
config.export_test_vars() {
    local stack
    stack="$(config.get '.project.stack' 'auto')"

    local default_framework=""
    if [[ "$stack" != "auto" ]]; then
        # optional: stack may not define a default test framework
        default_framework="$(config.stack_default "$stack" "test_framework" 2>/dev/null || true)"
    fi

    local framework
    framework="$(config.get '.test.framework' "$default_framework")"
    export BRIK_TEST_FRAMEWORK="$framework"

    # Test command override (Tier 1 of 3-tier resolution)
    local test_cmd
    test_cmd="$(config.get '.test.command' '')"
    [[ -n "$test_cmd" ]] && export BRIK_TEST_COMMAND="$test_cmd"

    # Coverage threshold (moved from quality)
    local coverage_threshold
    coverage_threshold="$(config.get '.test.coverage.threshold' '')"
    [[ -n "$coverage_threshold" ]] && export BRIK_TEST_COVERAGE_THRESHOLD="$coverage_threshold"

    local coverage_report
    coverage_report="$(config.get '.test.coverage.report' '')"
    [[ -n "$coverage_report" ]] && export BRIK_TEST_COVERAGE_REPORT="$coverage_report"

    return 0
}

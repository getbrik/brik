#!/usr/bin/env bash
# @module test
# @description Test execution functions for brik-lib.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_TEST_LOADED:-}" ]] && return 0
_BRIK_CORE_TEST_LOADED=1

# Detect the test framework from workspace marker files.
# Prints the framework name on stdout.
# Returns 1 if no framework detected.
_test._detect_framework() {
    local workspace="$1"

    if [[ -f "${workspace}/package.json" ]]; then
        printf 'node'
    elif [[ -f "${workspace}/build.gradle" || -f "${workspace}/build.gradle.kts" ]]; then
        printf 'gradle'
    elif [[ -f "${workspace}/pom.xml" ]]; then
        printf 'maven'
    elif [[ -f "${workspace}/pyproject.toml" || -f "${workspace}/setup.py" ]]; then
        printf 'pytest'
    elif [[ -f "${workspace}/Cargo.toml" ]]; then
        printf 'cargo'
    elif ls "${workspace}"/*.csproj >/dev/null 2>&1 || ls "${workspace}"/*.sln >/dev/null 2>&1; then
        printf 'dotnet'
    else
        return 1
    fi
    return 0
}

# Build the test command for an explicit framework.
# Prints the command on stdout.
_test._cmd_for_framework() {
    local framework="$1" workspace="$2" report_dir="$3"
    local cmd=""

    case "$framework" in
        jest)
            cmd="npx jest"
            [[ -n "$report_dir" ]] && cmd="$cmd --reporters=default --reporters=jest-junit"
            ;;
        junit|maven)
            cmd="mvn test"
            [[ -n "$report_dir" ]] && cmd="$cmd -Dsurefire.reportsDirectory=${report_dir}"
            ;;
        gradle)
            cmd="gradle test"
            [[ -x "${workspace}/gradlew" ]] && cmd="./gradlew test"
            ;;
        pytest)
            cmd="python -m pytest"
            [[ -n "$report_dir" ]] && cmd="$cmd --junitxml=${report_dir}/report.xml"
            ;;
        cargo)
            cmd="cargo test"
            ;;
        npm)
            cmd="npm test"
            ;;
        dotnet)
            cmd="dotnet test"
            ;;
        *)
            log.error "unsupported test framework: $framework"
            return 7
            ;;
    esac

    printf '%s' "$cmd"
    return 0
}

# Run tests in a workspace.
# Usage: test.run <workspace> [--suite <unit|integration|e2e>] [--report-dir <path>]
#        [--framework <jest|junit|pytest|gradle|cargo|dotnet>]
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

    # Detect test runner based on workspace (or use --framework override)
    local test_cmd=""
    if [[ -n "$framework" ]]; then
        test_cmd="$(_test._cmd_for_framework "$framework" "$workspace" "$report_dir")" || return $?
    else
        local detected
        detected="$(_test._detect_framework "$workspace")" || {
            log.error "cannot detect test framework for workspace: $workspace"
            return 3
        }

        if [[ "$detected" == "node" ]]; then
            # Node.js - prefer npm test if a test script is defined
            local has_test_script=""
            if command -v jq >/dev/null 2>&1 && [[ -f "${workspace}/package.json" ]]; then
                has_test_script="$(jq -r '.scripts.test // empty' "${workspace}/package.json" 2>/dev/null)"
            elif command -v node >/dev/null 2>&1; then
                has_test_script="$(node -e "
                    const p = require('${workspace}/package.json');
                    if (p.scripts && p.scripts.test) console.log('yes');
                " 2>/dev/null || true)"
            fi
            if [[ -n "$has_test_script" ]]; then
                test_cmd="npm test"
            elif command -v npx >/dev/null 2>&1; then
                test_cmd="$(_test._cmd_for_framework "jest" "$workspace" "$report_dir")"
            else
                test_cmd="npm test"
            fi
        else
            test_cmd="$(_test._cmd_for_framework "$detected" "$workspace" "$report_dir")" || return $?
        fi
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

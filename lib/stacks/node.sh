#!/usr/bin/env bash
# @module stacks/node
# @requires node
# @uses version
# @description Build Node.js projects (npm, yarn, pnpm).

# Guard against double-sourcing
[[ -n "${_BRIK_STACKS_NODE_LOADED:-}" ]] && return 0
_BRIK_STACKS_NODE_LOADED=1

# Detect the package manager from lock files.
# Prints npm, yarn, or pnpm on stdout.
_stacks.node._detect_pm() {
    local workspace="$1"

    if [[ -f "${workspace}/pnpm-lock.yaml" ]]; then
        printf 'pnpm'
    elif [[ -f "${workspace}/yarn.lock" ]]; then
        printf 'yarn'
    else
        printf 'npm'
    fi
}

# Install dependencies.
# Usage: stacks.node.install <workspace> [--package-manager <npm|yarn|pnpm>]
stacks.node.install() {
    local workspace="$1"
    shift
    local pm=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --package-manager|--tool) pm="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    [[ -z "$pm" ]] && pm="$(_stacks.node._detect_pm "$workspace")"

    pipeline.require_tool "$pm" || return "$BRIK_EXIT_MISSING_DEP"
    pipeline.require_file "${workspace}/package.json" || return "$BRIK_EXIT_IO_FAILURE"

    log.info "installing dependencies with $pm"

    local install_cmd="install"
    # Use ci/frozen lockfile for reproducible installs when lock file exists
    case "$pm" in
        npm)
            if [[ -f "${workspace}/package-lock.json" ]]; then
                install_cmd="ci --cache .npm --prefer-offline"
            fi
            ;;
        yarn)
            [[ -f "${workspace}/yarn.lock" ]] && install_cmd="install --frozen-lockfile"
            ;;
        pnpm)
            [[ -f "${workspace}/pnpm-lock.yaml" ]] && install_cmd="install --frozen-lockfile"
            ;;
    esac

    # $install_cmd intentionally word-splits (e.g. "install --frozen-lockfile")
    # shellcheck disable=SC2086
    (cd "$workspace" && $pm $install_cmd) || {
        log.error "dependency installation failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    return 0
}

# Run the build.
# Usage: stacks.node.build <workspace> [--package-manager <npm|yarn|pnpm>]
stacks.node.build() {
    local workspace="$1"
    shift
    local pm=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --package-manager|--tool) pm="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    [[ -z "$pm" ]] && pm="$(_stacks.node._detect_pm "$workspace")"

    pipeline.require_tool node || return "$BRIK_EXIT_MISSING_DEP"
    pipeline.require_tool "$pm" || return "$BRIK_EXIT_MISSING_DEP"
    pipeline.require_file "${workspace}/package.json" || return "$BRIK_EXIT_IO_FAILURE"

    # Install if node_modules is missing
    if [[ ! -d "${workspace}/node_modules" ]]; then
        stacks.node.install "$workspace" --package-manager "$pm" || return $?
    fi

    log.info "running build with $pm"
    (cd "$workspace" && $pm run build) || {
        log.error "build failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "build completed successfully"
    return 0
}

# Build the test command for a given Node.js framework.
# Usage: stacks.node.test_cmd <framework> <workspace> <report_dir>
# Frameworks: jest, npm
stacks.node.test_cmd() {
    local framework="$1" workspace="$2" report_dir="$3"
    local cmd=""
    local reports_on="${BRIK_TEST_REPORTS_ENABLED:-false}"

    case "$framework" in
        jest)
            cmd="npx jest"
            if [[ "$reports_on" == "true" ]]; then
                local cov_dir="${BRIK_TEST_COVERAGE_DIR:-coverage}"
                local junit="${BRIK_TEST_JUNIT_PATH:-reports/junit.xml}"
                # JEST_JUNIT_OUTPUT_FILE is the env var jest-junit honours.
                # It must be inlined in the command because stages.test
                # eval's the resulting string in a subshell.
                cmd="JEST_JUNIT_OUTPUT_FILE='${junit}' ${cmd} --coverage --coverageDirectory='${cov_dir}' --reporters=default --reporters=jest-junit"
            elif [[ -n "$report_dir" ]]; then
                # Legacy explicit report_dir argument (pre-test.reports.enabled).
                cmd="$cmd --reporters=default --reporters=jest-junit"
            fi
            ;;
        npm)
            # The user owns scripts.test; we cannot add coverage/reporter
            # flags without breaking custom commands. They must wire it up
            # in package.json themselves.
            cmd="npm test"
            ;;
        *)
            log.error "unsupported Node.js test framework: $framework"
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac

    printf '%s' "$cmd"
    return 0
}

# Auto-detect and return the test command for a Node.js workspace.
# Prefers npm test when scripts.test exists in package.json, falls back to npx jest.
# Usage: stacks.node.test <workspace> <report_dir>
stacks.node.test() {
    local workspace="$1" report_dir="$2"

    local has_test_script=""
    if command -v jq >/dev/null 2>&1 && [[ -f "${workspace}/package.json" ]]; then
        has_test_script="$(jq -r '.scripts.test // empty' "${workspace}/package.json" 2>/dev/null)"
    elif command -v node >/dev/null 2>&1; then
        has_test_script="$(node -e "
            const p = require('${workspace}/package.json');
            if (p.scripts && p.scripts.test) console.log('yes');
        " 2>/dev/null || true)"  # optional: node -e may fail if package.json invalid
    fi

    if [[ -n "$has_test_script" ]]; then
        printf '%s' "npm test"
    elif command -v npx >/dev/null 2>&1; then
        stacks.node.test_cmd "jest" "$workspace" "$report_dir"
    else
        printf '%s' "npm test"
    fi

    return 0
}

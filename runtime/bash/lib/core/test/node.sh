#!/usr/bin/env bash
# @module test.node
# @description Test commands for Node.js projects.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_TEST_NODE_LOADED:-}" ]] && return 0
_BRIK_CORE_TEST_NODE_LOADED=1

# Build the test command for a given Node.js framework.
# Usage: test.node.cmd <framework> <workspace> <report_dir>
# Frameworks: jest, npm
test.node.cmd() {
    local framework="$1" workspace="$2" report_dir="$3"
    local cmd=""

    case "$framework" in
        jest)
            cmd="npx jest"
            [[ -n "$report_dir" ]] && cmd="$cmd --reporters=default --reporters=jest-junit"
            ;;
        npm)
            cmd="npm test"
            ;;
        *)
            log.error "unsupported Node.js test framework: $framework"
            return 7
            ;;
    esac

    printf '%s' "$cmd"
    return 0
}

# Auto-detect and return the test command for a Node.js workspace.
# Prefers npm test when scripts.test exists in package.json, falls back to npx jest.
# Usage: test.node.run_cmd <workspace> <report_dir>
test.node.run_cmd() {
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
        test.node.cmd "jest" "$workspace" "$report_dir"
    else
        printf '%s' "npm test"
    fi

    return 0
}

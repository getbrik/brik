#!/usr/bin/env bash
# @module config.node
# @description Node.js stack defaults, version export, and coherence validation.
#
# Loaded via: brik.use config.node

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_CONFIG_NODE_LOADED:-}" ]] && return 0
_BRIK_CORE_CONFIG_NODE_LOADED=1

# Return the default value for a Node.js setting.
# Usage: config.node.default <setting>
config.node.default() {
    local setting="$1"

    case "$setting" in
        build_command)  printf 'npm run build' ;;
        test_framework) printf 'jest' ;;
        lint_tool)      printf 'eslint' ;;
        format_tool)    printf 'prettier' ;;
        *) return 1 ;;
    esac
    return 0
}

# Export Node.js version pinning.
# Sets: BRIK_BUILD_NODE_VERSION (if configured)
config.node.export_build_vars() {
    local node_version
    node_version="$(config.get '.build.node_version' '')"
    [[ -n "$node_version" ]] && export BRIK_BUILD_NODE_VERSION="$node_version"
    return 0
}

# Validate Node.js test framework coherence.
# If framework=jest but jest is not in deps and a custom test script exists, error.
# Usage: config.node.validate_coherence <workspace>
config.node.validate_coherence() {
    local workspace="$1"
    local framework="${BRIK_TEST_FRAMEWORK:-}"

    # Only validate jest coherence
    [[ "$framework" != "jest" ]] && return 0

    local package_json="${workspace}/package.json"
    [[ ! -f "$package_json" ]] && return 0

    if ! command -v jq >/dev/null 2>&1; then
        log.warn "jq not found - skipping Node.js coherence validation"
        return 0
    fi

    # Parse both fields in a single jq invocation
    local jq_result
    jq_result="$(jq -r '
        [
            ((.dependencies // {}) + (.devDependencies // {}) | has("jest")),
            (.scripts.test // "")
        ] | @tsv
    ' "$package_json" 2>/dev/null)" || return 0

    local has_jest test_script
    has_jest="$(printf '%s' "$jq_result" | cut -f1)"
    test_script="$(printf '%s' "$jq_result" | cut -f2)"

    # Determine source of the framework value
    local source="stack default"
    local explicit_framework
    explicit_framework="$(config.get '.test.framework' '')" || true
    [[ -n "$explicit_framework" ]] && source="brik.yml"

    # If jest is not in deps AND a custom test script exists, that's a mismatch
    if [[ "$has_jest" == "false" && -n "$test_script" ]]; then
        log.error "config mismatch: test.framework resolves to 'jest' (${source}) but jest is not in package.json dependencies"
        log.error "package.json defines a custom test script: \"${test_script}\""
        log.error "fix: set 'test.framework: npm' in brik.yml, or add jest to devDependencies"
        return 7
    fi

    return 0
}

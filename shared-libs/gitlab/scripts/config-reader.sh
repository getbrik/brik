#!/usr/bin/env bash
# @module config-reader
# @description Reads brik.yml via yq and exports stage-relevant environment variables.
#
# Centralizes all brik.yml parsing for the GitLab shared library.
# Every GitLab job sources this script to access project configuration.
#
# Requires: yq (mikefarah/yq v4+)

# Guard against double-sourcing
[[ -n "${_BRIK_CONFIG_READER_LOADED:-}" ]] && return 0
_BRIK_CONFIG_READER_LOADED=1

# ---------------------------------------------------------------------------
# Core config functions
# ---------------------------------------------------------------------------

# Load and validate that the config file exists.
# Usage: config.read <brik_yml_path>
config.read() {
    local config_path="${1:-brik.yml}"

    if [[ ! -f "$config_path" ]]; then
        echo "error: config file not found: $config_path" >&2
        return 7
    fi

    if ! command -v yq >/dev/null 2>&1; then
        echo "error: yq is required but not found on PATH" >&2
        return 3
    fi

    # Validate YAML is parseable
    if ! yq '.' "$config_path" >/dev/null 2>&1; then
        echo "error: failed to parse $config_path as YAML" >&2
        return 2
    fi

    export BRIK_CONFIG_FILE="$config_path"
    return 0
}

# Read a value from brik.yml with optional default.
# Usage: config.get <yq_path> [default]
# Example: config.get '.project.stack' 'auto'
config.get() {
    local yq_path="$1"
    local default_value="${2:-}"
    local config_file="${BRIK_CONFIG_FILE:-brik.yml}"

    if [[ ! -f "$config_file" ]]; then
        if [[ -n "$default_value" ]]; then
            printf '%s' "$default_value"
            return 0
        fi
        return 7
    fi

    local value
    if [[ -n "$default_value" ]]; then
        value="$(yq "${yq_path} // \"${default_value}\"" "$config_file" 2>/dev/null)"
    else
        value="$(yq "${yq_path}" "$config_file" 2>/dev/null)"
    fi

    # yq returns "null" for missing keys
    if [[ "$value" == "null" || -z "$value" ]]; then
        if [[ -n "$default_value" ]]; then
            printf '%s' "$default_value"
            return 0
        fi
        return 1
    fi

    printf '%s' "$value"
    return 0
}

# Check if a stage is enabled in brik.yml.
# Usage: config.stage_enabled <stage_name>
# Returns 0 if enabled, 1 if disabled.
config.stage_enabled() {
    local stage_name="$1"

    case "$stage_name" in
        init|build|test|notify)
            # These stages are always enabled
            return 0
            ;;
        quality)
            local enabled
            enabled="$(config.get '.quality.enabled')" || enabled="true"
            [[ "$enabled" == "true" ]]
            return $?
            ;;
        security)
            local enabled
            enabled="$(config.get '.security.enabled')" || enabled="false"
            [[ "$enabled" == "true" ]]
            return $?
            ;;
        release)
            # Enabled if version section exists
            local version_strategy
            version_strategy="$(config.get '.release.strategy' '')"
            [[ -n "$version_strategy" ]]
            return $?
            ;;
        package)
            # Enabled if package section exists
            local package_type
            package_type="$(config.get '.package.docker.image' '')"
            [[ -n "$package_type" ]]
            return $?
            ;;
        deploy)
            # Enabled if deploy.environments exists and is not empty
            local env_count
            env_count="$(config.get '.deploy.environments | length' '0')"
            [[ "$env_count" -gt 0 ]] 2>/dev/null
            return $?
            ;;
        *)
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Stack detection and defaults
# ---------------------------------------------------------------------------

# Stack defaults table
# Returns the default value for a stack-specific setting.
# Usage: config.stack_default <stack> <setting>
config.stack_default() {
    local stack="$1"
    local setting="$2"

    case "${stack}:${setting}" in
        node:build_command)     printf 'npm run build' ;;
        node:test_framework)    printf 'jest' ;;
        node:lint_tool)         printf 'eslint' ;;
        node:format_tool)       printf 'prettier' ;;
        java:build_command)     printf 'mvn package -DskipTests' ;;
        java:test_framework)    printf 'junit' ;;
        java:lint_tool)         printf 'checkstyle' ;;
        java:format_tool)       printf 'google-java-format' ;;
        python:build_command)   printf 'pip install .' ;;
        python:test_framework)  printf 'pytest' ;;
        python:lint_tool)       printf 'ruff' ;;
        python:format_tool)     printf 'ruff format' ;;
        dotnet:build_command)   printf 'dotnet build' ;;
        dotnet:test_framework)  printf 'xunit' ;;
        dotnet:lint_tool)       printf 'dotnet-format' ;;
        dotnet:format_tool)     printf 'dotnet-format' ;;
        rust:build_command)     printf 'cargo build' ;;
        rust:test_framework)    printf 'cargo test' ;;
        rust:lint_tool)         printf 'clippy' ;;
        rust:format_tool)       printf 'rustfmt' ;;
        *) return 1 ;;
    esac
    return 0
}

# ---------------------------------------------------------------------------
# Export functions for each stage
# ---------------------------------------------------------------------------

# Export build-related variables from brik.yml.
# Sets: BRIK_BUILD_STACK, BRIK_BUILD_COMMAND, BRIK_BUILD_NODE_VERSION, etc.
config.export_build_vars() {
    local stack
    stack="$(config.get '.project.stack' 'auto')"
    export BRIK_BUILD_STACK="$stack"

    local default_cmd=""
    if [[ "$stack" != "auto" ]]; then
        default_cmd="$(config.stack_default "$stack" "build_command" 2>/dev/null || true)"
    fi

    local build_cmd
    build_cmd="$(config.get '.build.command' "$default_cmd")"
    export BRIK_BUILD_COMMAND="$build_cmd"

    # Version pinning
    local node_version
    node_version="$(config.get '.build.node_version' '')"
    [[ -n "$node_version" ]] && export BRIK_BUILD_NODE_VERSION="$node_version"

    local java_version
    java_version="$(config.get '.build.java_version' '')"
    [[ -n "$java_version" ]] && export BRIK_BUILD_JAVA_VERSION="$java_version"

    local python_version
    python_version="$(config.get '.build.python_version' '')"
    [[ -n "$python_version" ]] && export BRIK_BUILD_PYTHON_VERSION="$python_version"

    return 0
}

# Export test-related variables from brik.yml.
# Sets: BRIK_TEST_FRAMEWORK, BRIK_TEST_COVERAGE_THRESHOLD, BRIK_TEST_COMMANDS_*
config.export_test_vars() {
    local stack
    stack="$(config.get '.project.stack' 'auto')"

    local default_framework=""
    if [[ "$stack" != "auto" ]]; then
        default_framework="$(config.stack_default "$stack" "test_framework" 2>/dev/null || true)"
    fi

    local framework
    framework="$(config.get '.test.framework' "$default_framework")"
    export BRIK_TEST_FRAMEWORK="$framework"

    local threshold
    threshold="$(config.get '.test.coverage_threshold' '80')"
    export BRIK_TEST_COVERAGE_THRESHOLD="$threshold"

    # Test commands per suite
    local unit_cmd
    unit_cmd="$(config.get '.test.commands.unit' '')"
    [[ -n "$unit_cmd" ]] && export BRIK_TEST_COMMAND_UNIT="$unit_cmd"

    local integration_cmd
    integration_cmd="$(config.get '.test.commands.integration' '')"
    [[ -n "$integration_cmd" ]] && export BRIK_TEST_COMMAND_INTEGRATION="$integration_cmd"

    local e2e_cmd
    e2e_cmd="$(config.get '.test.commands.e2e' '')"
    [[ -n "$e2e_cmd" ]] && export BRIK_TEST_COMMAND_E2E="$e2e_cmd"

    return 0
}

# Export quality-related variables from brik.yml.
# Sets: BRIK_QUALITY_ENABLED, BRIK_QUALITY_LINT_TOOL, BRIK_QUALITY_FORMAT_TOOL
config.export_quality_vars() {
    local enabled
    enabled="$(config.get '.quality.enabled' 'true')"
    export BRIK_QUALITY_ENABLED="$enabled"

    local stack
    stack="$(config.get '.project.stack' 'auto')"

    local default_lint=""
    local default_format=""
    if [[ "$stack" != "auto" ]]; then
        default_lint="$(config.stack_default "$stack" "lint_tool" 2>/dev/null || true)"
        default_format="$(config.stack_default "$stack" "format_tool" 2>/dev/null || true)"
    fi

    local lint_tool
    lint_tool="$(config.get '.quality.lint.tool' "$default_lint")"
    export BRIK_QUALITY_LINT_TOOL="$lint_tool"

    local format_tool
    format_tool="$(config.get '.quality.format.tool' "$default_format")"
    export BRIK_QUALITY_FORMAT_TOOL="$format_tool"

    return 0
}

# Export security-related variables from brik.yml.
# Sets: BRIK_SECURITY_ENABLED, BRIK_SECURITY_SEVERITY_THRESHOLD
config.export_security_vars() {
    local enabled
    enabled="$(config.get '.security.enabled' 'false')"
    export BRIK_SECURITY_ENABLED="$enabled"

    local threshold
    threshold="$(config.get '.security.severity_threshold' 'high')"
    export BRIK_SECURITY_SEVERITY_THRESHOLD="$threshold"

    return 0
}

# Export all configuration variables at once.
# Convenience function for jobs that need full context.
config.export_all() {
    local config_path="${1:-${BRIK_CONFIG_FILE:-brik.yml}}"

    config.read "$config_path" || return $?

    # Project-level vars
    local project_name
    project_name="$(config.get '.project.name' '')"
    export BRIK_PROJECT_NAME="$project_name"

    local project_root
    project_root="$(config.get '.project.root' '.')"
    export BRIK_PROJECT_ROOT="$project_root"

    config.export_build_vars
    config.export_test_vars
    config.export_quality_vars
    config.export_security_vars

    return 0
}

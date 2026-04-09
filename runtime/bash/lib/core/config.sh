#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module config
# @description Reads brik.yml via yq and exports stage-relevant environment variables.
#
# Portable configuration reader for the Brik runtime.
# Loaded via: brik.use config
#
# Requires: yq (mikefarah/yq v4+)

# Guard against double-sourcing (compatible with brik.use)
[[ -n "${_BRIK_CORE_CONFIG_LOADED:-}" ]] && return 0
_BRIK_CORE_CONFIG_LOADED=1

# Base directory for config sub-modules
_BRIK_CONFIG_DIR="${BASH_SOURCE[0]%/*}/config"

# Load a config sub-module by stack name.
# Config sub-modules are co-located in _BRIK_CONFIG_DIR and have their own
# double-sourcing guards, so direct sourcing is safe and avoids dependency
# on the brik.use loader (which may be mocked or unavailable in tests).
_config._load_module() {
    local stack="$1"
    local module_path="${_BRIK_CONFIG_DIR}/${stack}.sh"
    if [[ -f "$module_path" ]]; then
        # shellcheck source=/dev/null
        . "$module_path"
    else
        return 1
    fi
}

# Ensure runtime logging is available
if [[ -z "${_BRIK_LOGGING_LOADED:-}" ]]; then
    local_runtime_dir="${BASH_SOURCE[0]%/*}/../runtime"
    if [[ -f "${local_runtime_dir}/logging.sh" ]]; then
        # shellcheck source=../runtime/logging.sh
        . "${local_runtime_dir}/logging.sh"
    fi
    unset local_runtime_dir
fi

# ---------------------------------------------------------------------------
# Core config functions
# ---------------------------------------------------------------------------

# Load and validate that the config file exists.
# Usage: config.read <brik_yml_path>
config.read() {
    local config_path="${1:-brik.yml}"

    if [[ ! -f "$config_path" ]]; then
        log.error "config file not found: $config_path"
        return 7
    fi

    if ! command -v yq >/dev/null 2>&1; then
        log.error "yq is required but not found on PATH"
        return 3
    fi

    # Validate YAML is parseable
    if ! yq '.' "$config_path" >/dev/null 2>&1; then
        log.error "failed to parse $config_path as YAML"
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
    value="$(yq "${yq_path}" "$config_file" 2>/dev/null)"

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
        init|build|test|notify|verify)
            # These stages are always enabled
            return 0
            ;;
        lint)
            local enabled
            enabled="$(config.get '.quality.lint.enabled')" || enabled="true"
            [[ "$enabled" == "true" ]]
            return $?
            ;;
        sast|scan)
            # Always enabled when reached (non-negotiable scans)
            return 0
            ;;
        container_scan)
            # Enabled only if container image is configured
            local container_image
            container_image="$(config.get '.security.container.image' '')"
            [[ -n "$container_image" ]]
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

    # Load stack config module if available
    _config._load_module "$stack" || return 1

    local fn="config.${stack}.default"
    if declare -f "$fn" >/dev/null 2>&1; then
        "$fn" "$setting"
        return $?
    fi
    return 1
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

    local stack_version
    stack_version="$(config.get '.project.stack_version' '')"
    export BRIK_BUILD_STACK_VERSION="$stack_version"

    local default_cmd=""
    if [[ "$stack" != "auto" ]]; then
        default_cmd="$(config.stack_default "$stack" "build_command" 2>/dev/null || true)"
    fi

    local build_cmd
    build_cmd="$(config.get '.build.command' "$default_cmd")"
    export BRIK_BUILD_COMMAND="$build_cmd"

    # Build tool (Tier 2 of 3-tier resolution: command > tool > auto)
    local build_tool
    build_tool="$(config.get '.build.tool' '')"
    if [[ -z "$build_tool" && "$stack" != "auto" ]]; then
        build_tool="$(config.stack_default "$stack" "build_tool" 2>/dev/null || true)"
    fi
    export BRIK_BUILD_TOOL="$build_tool"

    # Delegate version pinning to stack config module
    if [[ "$stack" != "auto" ]]; then
        if _config._load_module "$stack"; then
            local fn="config.${stack}.export_build_vars"
            declare -f "$fn" >/dev/null 2>&1 && "$fn"
        fi
    fi

    return 0
}

# Export test-related variables from brik.yml.
# Sets: BRIK_TEST_FRAMEWORK, BRIK_TEST_COMMAND_*
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

# Export quality-related variables from brik.yml.
# Sets: BRIK_LINT_ENABLED, BRIK_QUALITY_LINT_TOOL, BRIK_QUALITY_FORMAT_TOOL
config.export_quality_vars() {
    local enabled
    enabled="$(config.get '.quality.lint.enabled' 'true')"
    export BRIK_LINT_ENABLED="$enabled"

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

    local format_check
    format_check="$(config.get '.quality.format.check' 'false')"
    export BRIK_QUALITY_FORMAT_CHECK="$format_check"

    local lint_config
    lint_config="$(config.get '.quality.lint.config' '')"
    [[ -n "$lint_config" ]] && export BRIK_QUALITY_LINT_CONFIG="$lint_config"

    local lint_fix
    lint_fix="$(config.get '.quality.lint.fix' '')"
    [[ -n "$lint_fix" ]] && export BRIK_QUALITY_LINT_FIX="$lint_fix"

    # Quality command overrides (Tier 1 of 3-tier resolution)
    local lint_cmd
    lint_cmd="$(config.get '.quality.lint.command' '')"
    [[ -n "$lint_cmd" ]] && export BRIK_QUALITY_LINT_COMMAND="$lint_cmd"

    local format_cmd
    format_cmd="$(config.get '.quality.format.command' '')"
    [[ -n "$format_cmd" ]] && export BRIK_QUALITY_FORMAT_COMMAND="$format_cmd"

    # Type check tool and command (Tier 2 / Tier 1)
    local type_check_tool
    type_check_tool="$(config.get '.quality.type_check.tool' '')"
    [[ -n "$type_check_tool" ]] && export BRIK_QUALITY_TYPE_CHECK_TOOL="$type_check_tool"

    local type_check_cmd
    type_check_cmd="$(config.get '.quality.type_check.command' '')"
    [[ -n "$type_check_cmd" ]] && export BRIK_QUALITY_TYPE_CHECK_COMMAND="$type_check_cmd"

    return 0
}

# Export security-related variables from brik.yml.
# Sets: BRIK_SECURITY_SAST_*, BRIK_SECURITY_DEPS_*, BRIK_SECURITY_SECRETS_*,
#       BRIK_SECURITY_LICENSE_*, BRIK_SECURITY_CONTAINER_*, BRIK_SECURITY_IAC_*,
#       BRIK_SECURITY_SEVERITY_THRESHOLD
config.export_security_vars() {
    # SAST
    local sast_tool; sast_tool="$(config.get '.security.sast.tool' '')"
    [[ -n "$sast_tool" ]] && export BRIK_SECURITY_SAST_TOOL="$sast_tool"
    local sast_ruleset; sast_ruleset="$(config.get '.security.sast.ruleset' '')"
    [[ -n "$sast_ruleset" ]] && export BRIK_SECURITY_SAST_RULESET="$sast_ruleset"
    local sast_cmd; sast_cmd="$(config.get '.security.sast.command' '')"
    [[ -n "$sast_cmd" ]] && export BRIK_SECURITY_SAST_COMMAND="$sast_cmd"

    # Deps
    local deps_tool; deps_tool="$(config.get '.security.deps.tool' '')"
    [[ -n "$deps_tool" ]] && export BRIK_SECURITY_DEPS_TOOL="$deps_tool"
    local deps_severity; deps_severity="$(config.get '.security.deps.severity' '')"
    [[ -n "$deps_severity" ]] && export BRIK_SECURITY_DEPS_SEVERITY="$deps_severity"
    local deps_cmd; deps_cmd="$(config.get '.security.deps.command' '')"
    [[ -n "$deps_cmd" ]] && export BRIK_SECURITY_DEPS_COMMAND="$deps_cmd"

    # Secrets
    local secrets_tool; secrets_tool="$(config.get '.security.secrets.tool' '')"
    [[ -n "$secrets_tool" ]] && export BRIK_SECURITY_SECRETS_TOOL="$secrets_tool"
    local secrets_cmd; secrets_cmd="$(config.get '.security.secrets.command' '')"
    [[ -n "$secrets_cmd" ]] && export BRIK_SECURITY_SECRETS_COMMAND="$secrets_cmd"

    # License
    local license_allowed; license_allowed="$(config.get '.security.license.allowed' '')"
    [[ -n "$license_allowed" ]] && export BRIK_SECURITY_LICENSE_ALLOWED="$license_allowed"
    local license_denied; license_denied="$(config.get '.security.license.denied' '')"
    [[ -n "$license_denied" ]] && export BRIK_SECURITY_LICENSE_DENIED="$license_denied"

    # Container
    local container_image; container_image="$(config.get '.security.container.image' '')"
    [[ -n "$container_image" ]] && export BRIK_SECURITY_CONTAINER_IMAGE="$container_image"
    local container_severity; container_severity="$(config.get '.security.container.severity' '')"
    [[ -n "$container_severity" ]] && export BRIK_SECURITY_CONTAINER_SEVERITY="$container_severity"

    # IaC
    local iac_tool; iac_tool="$(config.get '.security.iac.tool' '')"
    [[ -n "$iac_tool" ]] && export BRIK_SECURITY_IAC_TOOL="$iac_tool"
    local iac_cmd; iac_cmd="$(config.get '.security.iac.command' '')"
    [[ -n "$iac_cmd" ]] && export BRIK_SECURITY_IAC_COMMAND="$iac_cmd"

    # Global threshold
    local threshold; threshold="$(config.get '.security.severity_threshold' 'high')"
    export BRIK_SECURITY_SEVERITY_THRESHOLD="$threshold"

    return 0
}

# Export package-related variables from brik.yml.
# Sets: BRIK_PACKAGE_DOCKER_*
config.export_package_vars() {
    local image
    image="$(config.get '.package.docker.image' '')"
    [[ -n "$image" ]] && export BRIK_PACKAGE_DOCKER_IMAGE="$image"

    local dockerfile
    dockerfile="$(config.get '.package.docker.dockerfile' '')"
    [[ -n "$dockerfile" ]] && export BRIK_PACKAGE_DOCKER_DOCKERFILE="$dockerfile"

    local context
    context="$(config.get '.package.docker.context' '')"
    [[ -n "$context" ]] && export BRIK_PACKAGE_DOCKER_CONTEXT="$context"

    local platforms
    platforms="$(config.get '.package.docker.platforms' '')"
    [[ -n "$platforms" ]] && export BRIK_PACKAGE_DOCKER_PLATFORMS="$platforms"

    local build_args
    build_args="$(config.get '.package.docker.build_args' '')"
    [[ -n "$build_args" ]] && export BRIK_PACKAGE_DOCKER_BUILD_ARGS="$build_args"

    return 0
}

# Export deploy-related variables from brik.yml.
# Sets: BRIK_DEPLOY_ENVIRONMENTS, BRIK_DEPLOY_<ENV>_*
config.export_deploy_vars() {
    local env_keys
    env_keys="$(config.get '.deploy.environments | keys | .[]' '' 2>/dev/null)" || true
    if [[ -z "$env_keys" ]]; then
        export BRIK_DEPLOY_ENVIRONMENTS=""
        return 0
    fi

    export BRIK_DEPLOY_ENVIRONMENTS="$env_keys"

    local env_name upper_env
    while IFS= read -r env_name; do
        [[ -z "$env_name" ]] && continue
        upper_env="$(printf '%s' "$env_name" | tr '[:lower:]' '[:upper:]')"

        local val
        val="$(config.get ".deploy.environments.${env_name}.target" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_TARGET=$val"

        val="$(config.get ".deploy.environments.${env_name}.namespace" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_NAMESPACE=$val"

        val="$(config.get ".deploy.environments.${env_name}.manifest" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_MANIFEST=$val"

        val="$(config.get ".deploy.environments.${env_name}.when" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_WHEN=$val"

        val="$(config.get ".deploy.environments.${env_name}.repo" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_REPO=$val"

        val="$(config.get ".deploy.environments.${env_name}.path" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_PATH=$val"

        val="$(config.get ".deploy.environments.${env_name}.controller" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_CONTROLLER=$val"

        val="$(config.get ".deploy.environments.${env_name}.app_name" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_APP_NAME=$val"
    done <<< "$env_keys"

    return 0
}

# Export notify-related variables from brik.yml.
# Sets: BRIK_NOTIFY_SLACK_*, BRIK_NOTIFY_EMAIL_*, BRIK_NOTIFY_WEBHOOK_*
config.export_notify_vars() {
    local val

    val="$(config.get '.notify.slack.channel' '')"
    [[ -n "$val" ]] && export BRIK_NOTIFY_SLACK_CHANNEL="$val"

    val="$(config.get '.notify.slack.on' '')"
    [[ -n "$val" ]] && export BRIK_NOTIFY_SLACK_ON="$val"

    val="$(config.get '.notify.email.to' '')"
    [[ -n "$val" ]] && export BRIK_NOTIFY_EMAIL_TO="$val"

    val="$(config.get '.notify.email.on' '')"
    [[ -n "$val" ]] && export BRIK_NOTIFY_EMAIL_ON="$val"

    val="$(config.get '.notify.webhook.url' '')"
    [[ -n "$val" ]] && export BRIK_NOTIFY_WEBHOOK_URL="$val"

    val="$(config.get '.notify.webhook.on' '')"
    [[ -n "$val" ]] && export BRIK_NOTIFY_WEBHOOK_ON="$val"

    return 0
}

# Export hooks-related variables from brik.yml.
# Sets: BRIK_HOOK_PRE_<STAGE>, BRIK_HOOK_POST_<STAGE>
config.export_hooks_vars() {
    local stage upper_stage val
    for stage in init release build lint sast scan test package container_scan deploy notify; do
        upper_stage="$(printf '%s' "$stage" | tr '[:lower:]' '[:upper:]')"

        val="$(config.get ".hooks.pre_${stage}" '')"
        [[ -n "$val" ]] && export "BRIK_HOOK_PRE_${upper_stage}=$val"

        val="$(config.get ".hooks.post_${stage}" '')"
        [[ -n "$val" ]] && export "BRIK_HOOK_POST_${upper_stage}=$val"
    done

    return 0
}

# Export release-related variables from brik.yml.
# Sets: BRIK_RELEASE_STRATEGY, BRIK_RELEASE_TAG_PREFIX
config.export_release_vars() {
    local strategy
    strategy="$(config.get '.release.strategy' 'semver')"
    export BRIK_RELEASE_STRATEGY="$strategy"

    local tag_prefix
    tag_prefix="$(config.get '.release.tag_prefix' 'v')"
    export BRIK_RELEASE_TAG_PREFIX="$tag_prefix"

    local val
    val="$(config.get '.release.changelog.enabled' 'true')"
    export BRIK_RELEASE_CHANGELOG_ENABLED="$val"

    val="$(config.get '.release.changelog.format' 'conventional')"
    export BRIK_RELEASE_CHANGELOG_FORMAT="$val"

    val="$(config.get '.release.changelog.file' 'CHANGELOG.md')"
    export BRIK_RELEASE_CHANGELOG_FILE="$val"

    return 0
}

# Export publish-related variables from brik.yml.
# Sets: BRIK_PUBLISH_NPM_*, BRIK_PUBLISH_DOCKER_*, BRIK_PUBLISH_MAVEN_*,
#       BRIK_PUBLISH_PYPI_*, BRIK_PUBLISH_CARGO_*, BRIK_PUBLISH_NUGET_*
config.export_publish_vars() {
    local val

    # npm
    val="$(config.get '.publish.npm.registry' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_NPM_REGISTRY="$val"

    val="$(config.get '.publish.npm.tag' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_NPM_TAG="$val"

    val="$(config.get '.publish.npm.access' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_NPM_ACCESS="$val"

    val="$(config.get '.publish.npm.token_var' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_NPM_TOKEN_VAR="$val"

    # docker
    val="$(config.get '.publish.docker.image' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_DOCKER_IMAGE="$val"

    val="$(config.get '.publish.docker.registry' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_DOCKER_REGISTRY="$val"

    val="$(config.get '.publish.docker.tags | join(",")' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_DOCKER_TAGS="$val"

    val="$(config.get '.publish.docker.username_var' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_DOCKER_USERNAME_VAR="$val"

    val="$(config.get '.publish.docker.password_var' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_DOCKER_PASSWORD_VAR="$val"

    # maven
    val="$(config.get '.publish.maven.repository' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_MAVEN_REPOSITORY="$val"

    val="$(config.get '.publish.maven.username_var' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_MAVEN_USERNAME_VAR="$val"

    val="$(config.get '.publish.maven.password_var' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_MAVEN_PASSWORD_VAR="$val"

    # pypi
    val="$(config.get '.publish.pypi.repository' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_PYPI_REPOSITORY="$val"

    val="$(config.get '.publish.pypi.token_var' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_PYPI_TOKEN_VAR="$val"

    # cargo
    val="$(config.get '.publish.cargo.registry' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_CARGO_REGISTRY="$val"

    val="$(config.get '.publish.cargo.token_var' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_CARGO_TOKEN_VAR="$val"

    # nuget
    val="$(config.get '.publish.nuget.source' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_NUGET_SOURCE="$val"

    val="$(config.get '.publish.nuget.api_key_var' '')"
    [[ -n "$val" ]] && export BRIK_PUBLISH_NUGET_API_KEY_VAR="$val"

    return 0
}

# ---------------------------------------------------------------------------
# Runner image resolution
# ---------------------------------------------------------------------------

# Export runner image variable from stack + version.
# Sets: BRIK_RUNNER_IMAGE
config.export_runner_vars() {
    local stack="${BRIK_BUILD_STACK:-auto}"
    local version="${BRIK_BUILD_STACK_VERSION:-}"

    if [[ "$stack" == "auto" || -z "$stack" ]]; then
        export BRIK_RUNNER_IMAGE="${BRIK_RUNNER_REGISTRY:-ghcr.io/getbrik}/brik-runner-base:latest"
        return 0
    fi

    # Source runner-images if not already loaded
    local runner_file="${BASH_SOURCE[0]%/*}/../runtime/runner-images.sh"
    if [[ -f "$runner_file" && -z "${_BRIK_RUNNER_IMAGES_LOADED:-}" ]]; then
        # shellcheck source=../runtime/runner-images.sh
        . "$runner_file"
    fi

    local image
    if image="$(runner.resolve_image "$stack" "$version")"; then
        export BRIK_RUNNER_IMAGE="$image"
    else
        log.warn "no runner image found for stack '$stack' version '${version:-default}', using base"
        export BRIK_RUNNER_IMAGE="${BRIK_RUNNER_REGISTRY:-ghcr.io/getbrik}/brik-runner-base:latest"
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Config coherence validation
# ---------------------------------------------------------------------------

# Validate that resolved config values are coherent with the actual project.
# Called from init after config.export_all to fail fast on mismatches.
# Returns 7 on coherence errors, 0 otherwise.
config.validate_coherence() {
    local stack="${BRIK_BUILD_STACK:-auto}"

    if [[ -z "${BRIK_WORKSPACE:-}" ]]; then
        log.warn "BRIK_WORKSPACE not set - skipping coherence validation"
        return 0
    fi

    local workspace="$BRIK_WORKSPACE"

    if [[ "$stack" == "auto" || "$stack" == "unknown" ]]; then
        return 0
    fi

    # Delegate to stack-specific coherence validator
    if _config._load_module "$stack"; then
        local fn="config.${stack}.validate_coherence"
        if declare -f "$fn" >/dev/null 2>&1; then
            "$fn" "$workspace" || return 7
        fi
    fi

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
    config.export_runner_vars
    config.export_test_vars
    config.export_quality_vars
    config.export_security_vars
    config.export_package_vars
    config.export_deploy_vars
    config.export_notify_vars
    config.export_hooks_vars
    config.export_release_vars
    config.export_publish_vars

    return 0
}

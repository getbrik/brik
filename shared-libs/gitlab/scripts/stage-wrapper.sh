#!/usr/bin/env bash
# @module stage-wrapper
# @description Bridges GitLab CI jobs to the Brik runtime (stage.run).
#
# This is the main entry point called by each GitLab CI job script.
# It sources the runtime, config reader, and brik-lib, then dispatches
# each stage to its logic function via stage.run.
#
# Usage from GitLab CI job:
#   source "${BRIK_HOME}/shared-libs/gitlab/scripts/stage-wrapper.sh"
#   brik.gitlab.run_stage <stage_name>

# Guard against double-sourcing
[[ -n "${_BRIK_STAGE_WRAPPER_LOADED:-}" ]] && return 0
_BRIK_STAGE_WRAPPER_LOADED=1

# ---------------------------------------------------------------------------
# Bootstrap: setup BRIK_HOME, source runtime and config reader
# ---------------------------------------------------------------------------

# Setup the Brik runtime environment.
# Must be called once before any brik.gitlab.run_stage calls.
# Usage: brik.gitlab.setup [brik_home]
brik.gitlab.setup() {
    local brik_home="${1:-${BRIK_HOME:-}}"

    if [[ -z "$brik_home" ]]; then
        echo "error: BRIK_HOME is not set. Cannot find the Brik runtime." >&2
        echo "hint: set BRIK_HOME or pass it as argument to brik.gitlab.setup" >&2
        return 4
    fi

    if [[ ! -d "$brik_home" ]]; then
        echo "error: BRIK_HOME directory does not exist: $brik_home" >&2
        return 4
    fi

    export BRIK_HOME="$brik_home"

    # Verify runtime files exist
    local runtime_dir="${BRIK_HOME}/runtime/bash/lib/runtime"
    local core_dir="${BRIK_HOME}/runtime/bash/lib/core"

    if [[ ! -f "${runtime_dir}/stage.sh" ]]; then
        echo "error: stage.sh not found at ${runtime_dir}/stage.sh" >&2
        return 4
    fi

    if [[ ! -f "${core_dir}/_loader.sh" ]]; then
        echo "error: _loader.sh not found at ${core_dir}/_loader.sh" >&2
        return 4
    fi

    # Set standard environment variables
    export BRIK_PROJECT_DIR="${BRIK_PROJECT_DIR:-${CI_PROJECT_DIR:-$(pwd)}}"
    export BRIK_WORKSPACE="${BRIK_WORKSPACE:-${BRIK_PROJECT_DIR}}"
    export BRIK_CONFIG_FILE="${BRIK_CONFIG_FILE:-${BRIK_PROJECT_DIR}/brik.yml}"
    export BRIK_LOG_DIR="${BRIK_LOG_DIR:-/tmp/brik/logs}"
    export BRIK_PLATFORM="gitlab"
    export BRIK_LIB="${core_dir}"

    # Source the runtime
    # shellcheck source=/dev/null
    . "${runtime_dir}/stage.sh"
    # shellcheck source=/dev/null
    . "${core_dir}/_loader.sh"

    # Source the config reader
    local scripts_dir="${BRIK_HOME}/shared-libs/gitlab/scripts"
    # shellcheck source=config-reader.sh
    . "${scripts_dir}/config-reader.sh"
    # shellcheck source=condition-eval.sh
    . "${scripts_dir}/condition-eval.sh"

    # Read configuration
    config.read "${BRIK_CONFIG_FILE}" || {
        log.error "failed to read config: ${BRIK_CONFIG_FILE}"
        return 7
    }

    # Export all config vars
    config.export_all "${BRIK_CONFIG_FILE}" || {
        log.warn "some config exports failed, continuing with defaults"
    }

    log.info "brik gitlab setup complete (BRIK_HOME=$BRIK_HOME)"
    return 0
}

# ---------------------------------------------------------------------------
# Stage logic functions
# ---------------------------------------------------------------------------

# Init stage: detect stack, validate config, setup environment.
_gitlab_init_logic() {
    local context_file="$1"

    log.info "initializing pipeline"

    # Validate brik.yml exists
    if [[ ! -f "${BRIK_CONFIG_FILE}" ]]; then
        log.error "brik.yml not found at ${BRIK_CONFIG_FILE}"
        return 7
    fi

    # Detect or read stack
    local stack
    stack="$(config.get '.project.stack' 'auto')"

    if [[ "$stack" == "auto" ]]; then
        brik.use build
        stack="$(build.detect_stack "${BRIK_WORKSPACE}")" || {
            log.warn "could not auto-detect stack, continuing without stack-specific defaults"
            stack="unknown"
        }
        log.info "auto-detected stack: $stack"
    else
        log.info "configured stack: $stack"
    fi

    context.set "$context_file" "BRIK_STACK" "$stack"

    # Log project info
    local project_name
    project_name="$(config.get '.project.name' 'unnamed')"
    log.info "project: $project_name"
    log.info "workspace: ${BRIK_WORKSPACE}"
    log.info "platform: gitlab"

    # Verify required tools
    if ! command -v yq >/dev/null 2>&1; then
        log.error "yq is required but not available"
        return 3
    fi

    log.info "init stage complete"
    return 0
}

# Release stage: semantic version calculation (stub for MVP).
_gitlab_release_logic() {
    local context_file="$1"

    log.info "release stage - computing version"

    brik.use version
    brik.use git

    local current_version
    current_version="$(version.current --from-git-tag 2>/dev/null)" || {
        log.info "no git tag found, using 0.0.0"
        current_version="0.0.0"
    }

    log.info "current version: $current_version"
    context.set "$context_file" "BRIK_VERSION" "$current_version"

    return 0
}

# Build stage: compile/build via brik-lib.
_gitlab_build_logic() {
    local context_file="$1"

    brik.use build

    local stack
    stack="$(config.get '.project.stack' 'auto')"

    # Load stack-specific module
    case "$stack" in
        node)  brik.use build.node ;;
    esac

    log.info "running build (stack=$stack)"

    build.run "${BRIK_WORKSPACE}" --stack "$stack" --config "${BRIK_CONFIG_FILE}"
    local result=$?

    if [[ $result -eq 0 ]]; then
        context.set "$context_file" "BRIK_BUILD_STATUS" "success"
    else
        context.set "$context_file" "BRIK_BUILD_STATUS" "failed"
    fi

    return "$result"
}

# Quality stage: lint + format checks (stub for MVP).
_gitlab_quality_logic() {
    local context_file="$1"

    log.info "quality stage - lint and format checks"

    local lint_tool
    lint_tool="${BRIK_QUALITY_LINT_TOOL:-}"
    local format_tool
    format_tool="${BRIK_QUALITY_FORMAT_TOOL:-}"

    if [[ -n "$lint_tool" ]]; then
        log.info "lint tool: $lint_tool (not yet implemented in brik-lib)"
    fi
    if [[ -n "$format_tool" ]]; then
        log.info "format tool: $format_tool (not yet implemented in brik-lib)"
    fi

    log.warn "quality stage is a stub - full implementation in M3"
    context.set "$context_file" "BRIK_QUALITY_STATUS" "skipped"
    return 0
}

# Security stage: dependency and secret scanning (stub for MVP).
_gitlab_security_logic() {
    local context_file="$1"

    log.info "security stage - dependency and secret scanning"
    log.warn "security stage is a stub - full implementation in M3"
    context.set "$context_file" "BRIK_SECURITY_STATUS" "skipped"
    return 0
}

# Test stage: run tests via brik-lib.
_gitlab_test_logic() {
    local context_file="$1"

    brik.use test

    log.info "running tests"

    test.run "${BRIK_WORKSPACE}"
    local result=$?

    if [[ $result -eq 0 ]]; then
        context.set "$context_file" "BRIK_TEST_STATUS" "success"
    else
        context.set "$context_file" "BRIK_TEST_STATUS" "failed"
    fi

    return "$result"
}

# Package stage: container build (stub for MVP).
_gitlab_package_logic() {
    local context_file="$1"

    log.info "package stage - container build"
    log.warn "package stage is a stub - full implementation in M3"
    context.set "$context_file" "BRIK_PACKAGE_STATUS" "skipped"
    return 0
}

# Deploy stage: deploy to target environment (stub for MVP).
_gitlab_deploy_logic() {
    local context_file="$1"

    log.info "deploy stage"
    log.warn "deploy stage is a stub - full implementation in M3"
    context.set "$context_file" "BRIK_DEPLOY_STATUS" "skipped"
    return 0
}

# Notify stage: print pipeline summary.
_gitlab_notify_logic() {
    local context_file="$1"

    log.info "notify stage - pipeline summary"

    local project_name
    project_name="$(config.get '.project.name' 'unnamed')"

    echo "========================================"
    echo "  Brik Pipeline Summary"
    echo "========================================"
    echo "  Project : $project_name"
    echo "  Platform: GitLab CI"
    echo "  Ref     : ${CI_COMMIT_REF_NAME:-unknown}"
    echo "  SHA     : ${CI_COMMIT_SHORT_SHA:-unknown}"
    echo "========================================"

    return 0
}

# ---------------------------------------------------------------------------
# Stage dispatcher
# ---------------------------------------------------------------------------

# Run a stage by name. Dispatches to the correct logic function via stage.run.
# Usage: brik.gitlab.run_stage <stage_name>
brik.gitlab.run_stage() {
    local stage_name="$1"

    if [[ -z "$stage_name" ]]; then
        log.error "stage name is required"
        return 2
    fi

    # Verify setup was called
    if [[ -z "${BRIK_HOME:-}" ]]; then
        echo "error: brik.gitlab.setup must be called before brik.gitlab.run_stage" >&2
        return 4
    fi

    local logic_function=""

    case "$stage_name" in
        init)     logic_function="_gitlab_init_logic" ;;
        release)  logic_function="_gitlab_release_logic" ;;
        build)    logic_function="_gitlab_build_logic" ;;
        quality)  logic_function="_gitlab_quality_logic" ;;
        security) logic_function="_gitlab_security_logic" ;;
        test)     logic_function="_gitlab_test_logic" ;;
        package)  logic_function="_gitlab_package_logic" ;;
        deploy)   logic_function="_gitlab_deploy_logic" ;;
        notify)   logic_function="_gitlab_notify_logic" ;;
        *)
            log.error "unknown stage: $stage_name"
            log.error "valid stages: init, release, build, quality, security, test, package, deploy, notify"
            return 2
            ;;
    esac

    stage.run "$stage_name" "$logic_function" "${BRIK_WORKSPACE}" "${BRIK_CONFIG_FILE}"
    return $?
}

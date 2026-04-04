#!/usr/bin/env bash
# @module jenkins-wrapper
# @description Bridges Jenkins pipelines to the Brik runtime (stage.run).
#
# This is a thin adapter that:
# 1. Sets up the Jenkins-specific environment (BRIK_* from Jenkins vars)
# 2. Sources the portable runtime, config, condition, and stage modules
# 3. Dispatches stages to portable stages.* functions via stage.run
#
# Usage from Jenkins pipeline (via brikStage.groovy):
#   source "${BRIK_HOME}/shared-libs/jenkins/scripts/jenkins-wrapper.sh"
#   brik.jenkins.setup "${BRIK_HOME}"
#   brik.jenkins.run_stage <stage_name>

# Guard against double-sourcing
[[ -n "${_BRIK_JENKINS_WRAPPER_LOADED:-}" ]] && return 0
_BRIK_JENKINS_WRAPPER_LOADED=1

# ---------------------------------------------------------------------------
# Bootstrap: setup BRIK_HOME, source runtime, load stages
# ---------------------------------------------------------------------------

# Setup the Brik runtime environment for Jenkins.
# Must be called once before any brik.jenkins.run_stage calls.
# Usage: brik.jenkins.setup [brik_home]
brik.jenkins.setup() {
    local brik_home="${1:-${BRIK_HOME:-}}"

    if [[ -z "$brik_home" ]]; then
        echo "error: BRIK_HOME is not set. Cannot find the Brik runtime." >&2
        echo "hint: set BRIK_HOME or pass it as argument to brik.jenkins.setup" >&2
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
    # Jenkins uses WORKSPACE; fallback to pwd
    export BRIK_PROJECT_DIR="${BRIK_PROJECT_DIR:-${WORKSPACE:-$(pwd)}}"
    export BRIK_WORKSPACE="${BRIK_WORKSPACE:-${BRIK_PROJECT_DIR}}"
    export BRIK_CONFIG_FILE="${BRIK_CONFIG_FILE:-${BRIK_PROJECT_DIR}/brik.yml}"
    export BRIK_LOG_DIR="${BRIK_LOG_DIR:-/tmp/brik/logs/${BUILD_TAG:-$$}}"
    export BRIK_PLATFORM="jenkins"
    export BRIK_LIB="${core_dir}"

    # Platform variable normalization (Jenkins -> BRIK_* convention)
    # GIT_BRANCH in Jenkins often has "origin/" prefix - strip it
    local raw_branch="${GIT_BRANCH:-}"
    export BRIK_BRANCH="${raw_branch#origin/}"

    export BRIK_TAG="${TAG_NAME:-}"
    export BRIK_COMMIT_SHA="${GIT_COMMIT:-}"
    export BRIK_COMMIT_SHORT_SHA="${GIT_COMMIT:+${GIT_COMMIT:0:7}}"

    # BRIK_COMMIT_REF: tag takes priority over branch
    if [[ -n "$BRIK_TAG" ]]; then
        export BRIK_COMMIT_REF="$BRIK_TAG"
    else
        export BRIK_COMMIT_REF="$BRIK_BRANCH"
    fi

    # Jenkins has no direct equivalent of pipeline_source; default to "push"
    export BRIK_PIPELINE_SOURCE="push"

    # CHANGE_ID is set by Jenkins Multibranch for PRs
    export BRIK_MERGE_REQUEST_ID="${CHANGE_ID:-}"

    # Source the runtime
    # shellcheck source=/dev/null
    . "${runtime_dir}/stage.sh"
    # shellcheck source=/dev/null
    . "${core_dir}/_loader.sh"

    # Load portable config and condition modules
    brik.use config
    brik.use condition

    # Source portable stage logic
    local stages_dir="${BRIK_HOME}/runtime/bash/lib/stages"
    local stage_file
    for stage_file in "${stages_dir}"/*.sh; do
        if [[ -f "$stage_file" ]]; then
            # shellcheck source=/dev/null
            . "$stage_file"
        fi
    done

    # Read configuration
    config.read "${BRIK_CONFIG_FILE}" || {
        log.error "failed to read config: ${BRIK_CONFIG_FILE}"
        return 7
    }

    # Export all config vars
    config.export_all "${BRIK_CONFIG_FILE}" || {
        log.warn "some config exports failed, continuing with defaults"
    }

    log.info "brik jenkins setup complete (BRIK_HOME=$BRIK_HOME)"
    return 0
}

# ---------------------------------------------------------------------------
# Stage dispatcher
# ---------------------------------------------------------------------------

# Run a stage by name. Dispatches to portable stages.* functions via stage.run.
# Usage: brik.jenkins.run_stage <stage_name>
brik.jenkins.run_stage() {
    local stage_name="$1"

    if [[ -z "$stage_name" ]]; then
        log.error "stage name is required"
        return 2
    fi

    # Verify setup was called
    if [[ -z "${BRIK_HOME:-}" ]]; then
        echo "error: brik.jenkins.setup must be called before brik.jenkins.run_stage" >&2
        return 4
    fi

    local logic_function=""

    case "$stage_name" in
        init)     logic_function="stages.init" ;;
        release)  logic_function="stages.release" ;;
        build)    logic_function="stages.build" ;;
        quality)  logic_function="stages.quality" ;;
        security) logic_function="stages.security" ;;
        test)     logic_function="stages.test" ;;
        package)  logic_function="stages.package" ;;
        deploy)   logic_function="stages.deploy" ;;
        notify)   logic_function="stages.notify" ;;
        *)
            log.error "unknown stage: $stage_name"
            log.error "valid stages: init, release, build, quality, security, test, package, deploy, notify"
            return 2
            ;;
    esac

    stage.run "$stage_name" "$logic_function" "${BRIK_WORKSPACE}" "${BRIK_CONFIG_FILE}"
}

#!/usr/bin/env bash
# @module stage-wrapper
# @description Bridges GitLab CI jobs to the Brik runtime (stage.run).
#
# This is a thin adapter that:
# 1. Sets up the GitLab-specific environment (BRIK_* from CI_*)
# 2. Sources the portable runtime, config, condition, and stage modules
# 3. Dispatches stages to portable stages.* functions via stage.run
#
# Usage from GitLab CI job:
#   source "${BRIK_HOME}/shared-libs/gitlab/scripts/stage-wrapper.sh"
#   brik.gitlab.run_stage <stage_name>

# Guard against double-sourcing
[[ -n "${_BRIK_STAGE_WRAPPER_LOADED:-}" ]] && return 0
_BRIK_STAGE_WRAPPER_LOADED=1

# ---------------------------------------------------------------------------
# Bootstrap: setup BRIK_HOME, source runtime, load stages
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

    # Platform variable normalization (BRIK_* convention)
    export BRIK_BRANCH="${CI_COMMIT_BRANCH:-}"
    export BRIK_TAG="${CI_COMMIT_TAG:-}"
    export BRIK_COMMIT_SHA="${CI_COMMIT_SHA:-}"
    export BRIK_COMMIT_SHORT_SHA="${CI_COMMIT_SHORT_SHA:-}"
    export BRIK_COMMIT_REF="${CI_COMMIT_REF_NAME:-}"
    export BRIK_PIPELINE_SOURCE="${CI_PIPELINE_SOURCE:-}"
    export BRIK_MERGE_REQUEST_ID="${CI_MERGE_REQUEST_IID:-}"

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

    # Prepare runtime environment (install prerequisites + stack)
    setup.prepare_env "${BRIK_BUILD_STACK:-}" || {
        log.warn "runtime preparation failed, some stages may fail"
    }

    log.info "brik gitlab setup complete (BRIK_HOME=$BRIK_HOME)"
    return 0
}

# ---------------------------------------------------------------------------
# Stage dispatcher
# ---------------------------------------------------------------------------

# Run a stage by name. Dispatches to portable stages.* functions via stage.run.
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

    # Show the logo once, before the first stage
    if [[ "$stage_name" == "init" ]]; then
        local _brik_ver="${BRIK_VERSION:-}"
        [[ -z "$_brik_ver" ]] && _brik_ver="$(sed -n 's/^readonly BRIK_VERSION="\(.*\)"/\1/p' "${BRIK_HOME}/bin/brik" 2>/dev/null || true)"
        banner.brik "$_brik_ver"
    fi

    local logic_function=""

    case "$stage_name" in
        init)            logic_function="stages.init" ;;
        release)         logic_function="stages.release" ;;
        build)           logic_function="stages.build" ;;
        lint)            logic_function="stages.lint" ;;
        sast)            logic_function="stages.sast" ;;
        scan)            logic_function="stages.scan" ;;
        test)            logic_function="stages.test" ;;
        package)         logic_function="stages.package" ;;
        container-scan)  logic_function="stages.container_scan" ;;
        deploy)          logic_function="stages.deploy" ;;
        notify)          logic_function="stages.notify" ;;
        # Backward-compat aliases (deprecated)
        quality)         logic_function="stages.lint" ;;
        security)        logic_function="stages.scan" ;;
        *)
            log.error "unknown stage: $stage_name"
            log.error "valid stages: init, release, build, lint, sast, scan, test, package, container-scan, deploy, notify"
            return 2
            ;;
    esac

    stage.run "$stage_name" "$logic_function" "${BRIK_WORKSPACE}" "${BRIK_CONFIG_FILE}"
    return $?
}

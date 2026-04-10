#!/usr/bin/env bash
# @module base-wrapper
# @description Common wrapper logic shared by all platform adapters.
#
# Provides the portable bootstrap, config loading, and stage dispatch
# that is identical across GitLab, Jenkins, and local wrappers.
# Platform wrappers source this file and call its functions.
#
# Usage (from a platform wrapper):
#   _BRIK_WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   . "${_BRIK_WRAPPER_DIR}/../../common/scripts/base-wrapper.sh"

# Guard against double-sourcing
[[ -n "${_BRIK_BASE_WRAPPER_LOADED:-}" ]] && return 0
_BRIK_BASE_WRAPPER_LOADED=1

# ---------------------------------------------------------------------------
# Exit code bootstrap (needed before validate_home, error.sh not yet loaded)
# ---------------------------------------------------------------------------

# Ensure BRIK_EXIT_* constants are available.
# Uses fallback values identical to runtime/bash/lib/runtime/error.sh.
# After bootstrap(), error.sh is sourced and the canonical values take over.
_brik_wrapper_ensure_exit_codes() {
    : "${BRIK_EXIT_OK:=0}"
    : "${BRIK_EXIT_FAILURE:=1}"
    : "${BRIK_EXIT_INVALID_INPUT:=2}"
    : "${BRIK_EXIT_MISSING_DEP:=3}"
    : "${BRIK_EXIT_INVALID_ENV:=4}"
    : "${BRIK_EXIT_EXTERNAL_FAIL:=5}"
    : "${BRIK_EXIT_IO_FAILURE:=6}"
    : "${BRIK_EXIT_CONFIG_ERROR:=7}"
    : "${BRIK_EXIT_TIMEOUT:=8}"
    : "${BRIK_EXIT_INTERRUPTED:=9}"
    : "${BRIK_EXIT_CHECK_FAILED:=10}"
}
_brik_wrapper_ensure_exit_codes

# ---------------------------------------------------------------------------
# brik.wrapper.validate_home -- validate BRIK_HOME and runtime files
# ---------------------------------------------------------------------------

# Validates BRIK_HOME path and verifies runtime files exist.
# Arguments: $1 = brik_home path
# Exports: BRIK_HOME, _BRIK_RUNTIME_DIR, _BRIK_CORE_DIR
# Returns: 0 on success, $BRIK_EXIT_INVALID_ENV on failure
brik.wrapper.validate_home() {
    local brik_home="$1"

    if [[ -z "$brik_home" ]]; then
        echo "error: BRIK_HOME is not set. Cannot find the Brik runtime." >&2
        echo "hint: set BRIK_HOME or pass it as argument to the wrapper setup function" >&2
        return "$BRIK_EXIT_INVALID_ENV"
    fi

    if [[ ! -d "$brik_home" ]]; then
        echo "error: BRIK_HOME directory does not exist: $brik_home" >&2
        return "$BRIK_EXIT_INVALID_ENV"
    fi

    export BRIK_HOME="$brik_home"

    # Verify runtime files exist
    export _BRIK_RUNTIME_DIR="${BRIK_HOME}/runtime/bash/lib/runtime"
    export _BRIK_CORE_DIR="${BRIK_HOME}/runtime/bash/lib/core"

    if [[ ! -f "${_BRIK_RUNTIME_DIR}/stage.sh" ]]; then
        echo "error: stage.sh not found at ${_BRIK_RUNTIME_DIR}/stage.sh" >&2
        return "$BRIK_EXIT_INVALID_ENV"
    fi

    if [[ ! -f "${_BRIK_CORE_DIR}/_loader.sh" ]]; then
        echo "error: _loader.sh not found at ${_BRIK_CORE_DIR}/_loader.sh" >&2
        return "$BRIK_EXIT_INVALID_ENV"
    fi
}

# ---------------------------------------------------------------------------
# brik.wrapper.set_standard_env -- set BRIK_WORKSPACE, CONFIG_FILE, etc.
# ---------------------------------------------------------------------------

# Sets standard environment variables common to all platforms.
# Precondition: BRIK_HOME, BRIK_PROJECT_DIR, BRIK_PLATFORM must be set.
# BRIK_LOG_DIR may be pre-set by caller (e.g. Jenkins BUILD_TAG isolation).
brik.wrapper.set_standard_env() {
    export BRIK_WORKSPACE="${BRIK_WORKSPACE:-${BRIK_PROJECT_DIR}}"
    export BRIK_CONFIG_FILE="${BRIK_CONFIG_FILE:-${BRIK_PROJECT_DIR}/brik.yml}"
    export BRIK_LOG_DIR="${BRIK_LOG_DIR:-${BRIK_DEFAULT_LOG_DIR:-/tmp/brik/logs}}"
    export BRIK_LIB="${_BRIK_CORE_DIR}"
}

# ---------------------------------------------------------------------------
# brik.wrapper.bootstrap -- source runtime, loader, config, stages
# ---------------------------------------------------------------------------

# Sources the runtime (stage.sh, _loader.sh), loads config and condition
# modules, and sources all portable stage files.
# Precondition: BRIK_HOME set and validated via validate_home().
brik.wrapper.bootstrap() {
    # shellcheck source=/dev/null
    . "${_BRIK_RUNTIME_DIR}/stage.sh"
    # shellcheck source=/dev/null
    . "${_BRIK_CORE_DIR}/_loader.sh"

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
}

# ---------------------------------------------------------------------------
# brik.wrapper.load_config -- read brik.yml, export vars, prepare env
# ---------------------------------------------------------------------------

# Reads brik.yml, exports all config vars, prepares runtime environment.
# Precondition: bootstrap() called.
# Returns: 0 on success, $BRIK_EXIT_CONFIG_ERROR on config.read failure
brik.wrapper.load_config() {
    config.read "${BRIK_CONFIG_FILE}" || {
        log.error "failed to read config: ${BRIK_CONFIG_FILE}"
        return "$BRIK_EXIT_CONFIG_ERROR"
    }

    config.export_all "${BRIK_CONFIG_FILE}" || {
        log.warn "some config exports failed, continuing with defaults"
    }

    setup.prepare_env "${BRIK_BUILD_STACK:-}" || {
        log.warn "runtime preparation failed, some stages may fail"
    }
}

# ---------------------------------------------------------------------------
# brik.wrapper.run_stage -- validate and dispatch a stage
# ---------------------------------------------------------------------------

# Full stage dispatcher: validates stage name, shows banner on init,
# maps name to stages.* function, calls stage.run.
# Arguments: $1 = stage_name
# Returns: stage.run exit code, or $BRIK_EXIT_INVALID_INPUT for bad stage
brik.wrapper.run_stage() {
    local stage_name="$1"

    if [[ -z "$stage_name" ]]; then
        log.error "stage name is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    # Verify setup was called
    if [[ -z "${BRIK_HOME:-}" ]]; then
        echo "error: wrapper setup must be called before run_stage" >&2
        return "$BRIK_EXIT_INVALID_ENV"
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
            return "$BRIK_EXIT_INVALID_INPUT"
            ;;
    esac

    stage.run "$stage_name" "$logic_function" "${BRIK_WORKSPACE}" "${BRIK_CONFIG_FILE}"
    return $?
}

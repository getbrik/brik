#!/usr/bin/env bash
# @module local-wrapper
# @description Bridges local CLI execution to the Brik runtime (stage.run).
#
# This is a thin adapter that:
# 1. Sets up the local environment (BRIK_* from git)
# 2. Delegates common bootstrap and dispatch to base-wrapper.sh
# 3. Orchestrates the full pipeline: Init -> Release -> Build -> Lint||SAST||Scan||Test -> Package -> Container Scan -> Deploy -> Notify
#
# Usage from brik CLI:
#   source "${BRIK_HOME}/shared-libs/local/scripts/local-wrapper.sh"
#   brik.local.setup
#   brik.local.run_stage <stage_name>
#   brik.local.run_integrate [flags]

# Guard against double-sourcing
[[ -n "${_BRIK_LOCAL_WRAPPER_LOADED:-}" ]] && return 0
_BRIK_LOCAL_WRAPPER_LOADED=1

# Source shared wrapper logic
_BRIK_WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${_BRIK_WRAPPER_DIR}/../../common/scripts/base-wrapper.sh"

# ---------------------------------------------------------------------------
# Bootstrap: setup BRIK_HOME, source runtime, load stages
# ---------------------------------------------------------------------------

# Setup the Brik runtime environment for local execution.
# Populates BRIK_* variables from the local Git repository.
# Must be called once before any brik.local.run_stage calls.
# Exit codes: 0=success, BRIK_EXIT_INVALID_ENV=environment error, BRIK_EXIT_CONFIG_ERROR=config error
brik.local.setup() {
    brik.wrapper.validate_home "${BRIK_HOME:-}" || return $?

    export BRIK_PROJECT_DIR="${BRIK_PROJECT_DIR:-$(pwd)}"
    export BRIK_PLATFORM="local"

    brik.wrapper.set_standard_env
    # Source runtime before git context so log.warn is available
    brik.wrapper.bootstrap || return $?

    # Platform variable normalization from local Git (after runtime for log.warn)
    _brik_local_setup_git_context

    brik.wrapper.load_config || return $?

    log.info "brik local setup complete (BRIK_HOME=$BRIK_HOME)"
    return 0
}

# Host-side bootstrap for the containerized engine: runtime + registry only.
# The project config is parsed INSIDE the stage containers (load_config stays
# in brik.local.setup, the in-container path) -- the host needs log.*,
# BRIK_EXIT_* and registry.* to resolve runner images and stage order,
# nothing more, so a bare host without the project toolchain can drive a run.
brik.local.setup_host() {
    brik.wrapper.validate_home "${BRIK_HOME:-}" || return $?

    export BRIK_PROJECT_DIR="${BRIK_PROJECT_DIR:-$(pwd)}"
    export BRIK_PLATFORM="local"

    brik.wrapper.set_standard_env
    brik.wrapper.bootstrap || return $?

    log.debug "brik local host setup complete (containerized engine)"
    return 0
}

# Populate BRIK_* variables from the local Git repository.
# Resolves the git context against BRIK_PROJECT_DIR (set by the CLI from
# --workspace) so the host shell's cwd cannot leak in when brik runs
# against a project located elsewhere. Falls back to cwd when
# BRIK_PROJECT_DIR is unset (legacy callers and direct unit tests).
# If not inside a git repo, emits a warning and sets empty values.
_brik_local_setup_git_context() {
    local _project_dir="${BRIK_PROJECT_DIR:-$(pwd)}"

    if ! git -C "$_project_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        if declare -f log.warn >/dev/null 2>&1; then
            log.warn "not inside a git repository - git context variables will be empty"
        else
            echo "warning: not inside a git repository - git context variables will be empty" >&2
        fi
        export BRIK_BRANCH=""
        export BRIK_TAG=""
        export BRIK_COMMIT_SHA=""
        export BRIK_COMMIT_SHORT_SHA=""
        export BRIK_COMMIT_REF=""
        export BRIK_PIPELINE_SOURCE="local"
        export BRIK_MERGE_REQUEST_ID=""
        return 0
    fi

    export BRIK_BRANCH
    BRIK_BRANCH="$(git -C "$_project_dir" branch --show-current 2>/dev/null || echo "")"
    export BRIK_TAG
    BRIK_TAG="$(git -C "$_project_dir" describe --tags --exact-match 2>/dev/null || echo "")"
    export BRIK_COMMIT_SHA
    BRIK_COMMIT_SHA="$(git -C "$_project_dir" rev-parse HEAD 2>/dev/null || echo "")"
    export BRIK_COMMIT_SHORT_SHA
    BRIK_COMMIT_SHORT_SHA="$(git -C "$_project_dir" rev-parse --short HEAD 2>/dev/null || echo "")"
    export BRIK_COMMIT_REF="${BRIK_BRANCH:-${BRIK_TAG:-}}"
    export BRIK_PIPELINE_SOURCE="local"
    export BRIK_MERGE_REQUEST_ID=""
}

# ---------------------------------------------------------------------------
# Stage dispatcher
# ---------------------------------------------------------------------------

# Run a stage by name. Dispatches to portable stages.* functions via stage.run.
# Usage: brik.local.run_stage <stage_name>
# Exit codes: 0=success, BRIK_EXIT_INVALID_INPUT=invalid argument, BRIK_EXIT_INVALID_ENV=setup not called
brik.local.run_stage() {
    brik.wrapper.run_stage "$@"
}

# Run the deploy stage for an explicit CD deploy (mode 2). Thin: cli.deploy
# has already resolved the digest and set BRIK_DEPLOY_ONLY_ENV /
# BRIK_DEPLOY_IMAGE_REF; this just runs the deploy stage via the same path as
# the CI flow, so local and CI execute identical business logic.
# Usage: brik.local.run_deploy
brik.local.run_deploy() {
    brik.local.run_stage deploy
}

# ---------------------------------------------------------------------------
# Pipeline orchestration
# ---------------------------------------------------------------------------

# Run the full fixed-flow pipeline locally.
#
# Thin delegator: wrapper setup has already been done by brik.local.setup.
# We call pipeline.run in the lib layer, then ask report.render_terminal
# to surface a terminal-friendly recap from the produced aggregate-report.json.
# The recap is best-effort -- a render failure does not mask pipeline.run's
# exit code.
#
# Usage: brik.local.run_integrate [--continue-on-error] [--with-release]
#        [--with-package] [--with-deploy]
# Exit codes: pipeline.run's exit code
#   (0 all passed, BRIK_EXIT_FAILURE any failed, BRIK_EXIT_INVALID_INPUT bad flag).
brik.local.run_integrate() {
    local rc=0
    pipeline.run "$@"
    rc=$?
    report.render_terminal || true
    return "$rc"
}

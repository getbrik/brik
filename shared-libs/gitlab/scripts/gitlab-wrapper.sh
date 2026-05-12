#!/usr/bin/env bash
# @module gitlab-wrapper
# @description Bridges GitLab CI jobs to the Brik runtime (stage.run).
#
# This is a thin adapter that:
# 1. Sets up the GitLab-specific environment (BRIK_* from CI_*)
# 2. Delegates common bootstrap and dispatch to base-wrapper.sh
#
# Usage from GitLab CI job:
#   source "${BRIK_HOME}/shared-libs/gitlab/scripts/gitlab-wrapper.sh"
#   brik.gitlab.setup "${BRIK_HOME}"
#   brik.gitlab.run_stage <stage_name>

# Guard against double-sourcing
[[ -n "${_BRIK_GITLAB_WRAPPER_LOADED:-}" ]] && return 0
_BRIK_GITLAB_WRAPPER_LOADED=1

# Source shared wrapper logic
_BRIK_WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${_BRIK_WRAPPER_DIR}/../../common/scripts/base-wrapper.sh"

# Setup the Brik runtime environment.
# Must be called once before any brik.gitlab.run_stage calls.
# Usage: brik.gitlab.setup [brik_home]
brik.gitlab.setup() {
    brik.wrapper.validate_home "${1:-${BRIK_HOME:-}}" || return $?

    # Set project root from GitLab CI variable
    export BRIK_PROJECT_DIR="${BRIK_PROJECT_DIR:-${CI_PROJECT_DIR:-$(pwd)}}"
    export BRIK_PLATFORM="gitlab"

    # Place runtime files inside the workspace so GitLab can export them as artifacts
    export BRIK_LOG_DIR="${CI_PROJECT_DIR:-.}/.brik-logs"

    # Platform variable normalization (CI_* -> BRIK_*)
    export BRIK_BRANCH="${CI_COMMIT_BRANCH:-}"
    export BRIK_TAG="${CI_COMMIT_TAG:-}"
    export BRIK_COMMIT_SHA="${CI_COMMIT_SHA:-}"
    # Derive from the full SHA rather than CI_COMMIT_SHORT_SHA. GitLab's
    # CI_COMMIT_SHORT_SHA is 8 chars by default while git's `--short` and
    # the Jenkins wrapper emit 7. Image tags and finding messages embed
    # this value, so divergent widths break GitLab/Jenkins parity on the
    # same commit. Fall back to CI_COMMIT_SHORT_SHA when CI_COMMIT_SHA is
    # not set so test fixtures that only stub the short var keep working.
    if [[ -n "${CI_COMMIT_SHA:-}" ]]; then
        export BRIK_COMMIT_SHORT_SHA="${CI_COMMIT_SHA:0:7}"
    else
        export BRIK_COMMIT_SHORT_SHA="${CI_COMMIT_SHORT_SHA:-}"
    fi
    export BRIK_COMMIT_REF="${CI_COMMIT_REF_NAME:-}"
    export BRIK_PIPELINE_SOURCE="${CI_PIPELINE_SOURCE:-}"
    export BRIK_MERGE_REQUEST_ID="${CI_MERGE_REQUEST_IID:-}"

    brik.wrapper.set_standard_env
    brik.wrapper.bootstrap || return $?
    brik.wrapper.load_config || return $?

    log.info "brik gitlab setup complete (BRIK_HOME=$BRIK_HOME)"
    return 0
}

# Run a stage by name. Dispatches to portable stages.* functions via stage.run.
# Usage: brik.gitlab.run_stage <stage_name>
brik.gitlab.run_stage() {
    brik.wrapper.run_stage "$@"
}

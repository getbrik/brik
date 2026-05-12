#!/usr/bin/env bash
# @module jenkins-wrapper
# @description Bridges Jenkins pipelines to the Brik runtime (stage.run).
#
# This is a thin adapter that:
# 1. Sets up the Jenkins-specific environment (BRIK_* from Jenkins vars)
# 2. Delegates common bootstrap and dispatch to base-wrapper.sh
#
# Usage from Jenkins pipeline (via brikStage.groovy):
#   source "${BRIK_HOME}/shared-libs/jenkins/scripts/jenkins-wrapper.sh"
#   brik.jenkins.setup "${BRIK_HOME}"
#   brik.jenkins.run_stage <stage_name>

# Guard against double-sourcing
[[ -n "${_BRIK_JENKINS_WRAPPER_LOADED:-}" ]] && return 0
_BRIK_JENKINS_WRAPPER_LOADED=1

# Source shared wrapper logic
_BRIK_WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${_BRIK_WRAPPER_DIR}/../../common/scripts/base-wrapper.sh"

# Setup the Brik runtime environment for Jenkins.
# Must be called once before any brik.jenkins.run_stage calls.
# Usage: brik.jenkins.setup [brik_home]
brik.jenkins.setup() {
    brik.wrapper.validate_home "${1:-${BRIK_HOME:-}}" || return $?

    # Set project root from Jenkins WORKSPACE variable
    export BRIK_PROJECT_DIR="${BRIK_PROJECT_DIR:-${WORKSPACE:-$(pwd)}}"
    export BRIK_PLATFORM="jenkins"
    # Place runtime files inside the workspace so they persist across the
    # per-stage docker containers (each stage gets a fresh /tmp; only
    # WORKSPACE is mounted across all stage containers).
    export BRIK_LOG_DIR="${BRIK_LOG_DIR:-${WORKSPACE:-/tmp}/.brik-logs}"

    # Platform variable normalization (Jenkins -> BRIK_*)
    # GIT_BRANCH in Jenkins often has "origin/" prefix - strip it
    local raw_branch="${GIT_BRANCH:-}"
    export BRIK_BRANCH="${raw_branch#origin/}"

    export BRIK_TAG="${TAG_NAME:-}"
    # Recover BRIK_TAG from git only on true tag-scan builds (TAG_NAME and
    # GIT_BRANCH both empty). A Multibranch branch build whose HEAD happens
    # to coincide with a tag (e.g. `main` pushed with `v0.1.0` at the same
    # SHA) must stay classified as a snapshot, matching GitLab where
    # CI_COMMIT_TAG is set only on tag-triggered pipelines. Without this
    # guard, brik would emit context=release on a regular `main` push as
    # soon as a release tag exists at HEAD.
    if [[ -z "$BRIK_TAG" ]] && [[ -z "$BRIK_BRANCH" ]] && command -v git >/dev/null 2>&1; then
        BRIK_TAG="$(git -C "$BRIK_PROJECT_DIR" describe --tags --exact-match HEAD 2>/dev/null || echo "")"
        export BRIK_TAG
    fi
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

    brik.wrapper.set_standard_env
    brik.wrapper.bootstrap || return $?
    brik.wrapper.load_config || return $?

    log.info "brik jenkins setup complete (BRIK_HOME=$BRIK_HOME)"
    return 0
}

# Run a stage by name. Dispatches to portable stages.* functions via stage.run.
# Usage: brik.jenkins.run_stage <stage_name>
brik.jenkins.run_stage() {
    brik.wrapper.run_stage "$@"
}

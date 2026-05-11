#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.gating
# @description SC20 trigger gating for release/package/deploy stages.
#
# Each schedulable stage exposes a `trigger` block in brik.yml. Init
# reads it and exports the four booleans:
#
#   BRIK_<PREFIX>_TRIGGER_ON_TAG     "true"|"false"
#   BRIK_<PREFIX>_TRIGGER_ON_MAIN    "true"|"false"
#   BRIK_<PREFIX>_TRIGGER_ON_FEATURE "true"|"false"  (package/deploy only)
#   BRIK_<PREFIX>_TRIGGER_MANUAL     "true"|"false"
#
# plus a sentinel BRIK_<PREFIX>_TRIGGER_CONFIGURED="true" when the user
# wrote a trigger block (so legacy brik.yml files keep the historic
# always-run behavior).
#
# Concrete env-var set consumed below (also listed here for the
# schema-runtime drift detector, which greps lib/ for literal names):
#   BRIK_RELEASE_TRIGGER_ON_TAG, BRIK_RELEASE_TRIGGER_ON_MAIN,
#   BRIK_RELEASE_TRIGGER_MANUAL
#   BRIK_PACKAGE_TRIGGER_ON_TAG, BRIK_PACKAGE_TRIGGER_ON_MAIN,
#   BRIK_PACKAGE_TRIGGER_ON_FEATURE, BRIK_PACKAGE_TRIGGER_MANUAL
#   BRIK_DEPLOY_TRIGGER_ON_TAG, BRIK_DEPLOY_TRIGGER_ON_MAIN,
#   BRIK_DEPLOY_TRIGGER_ON_FEATURE, BRIK_DEPLOY_TRIGGER_MANUAL
#
# Public API:
#   gating.should_run_stage <PREFIX>
#     -> rc=0 if the current pipeline context matches at least one of
#        the configured trigger flags, rc=1 otherwise. rc=2 on invalid
#        input. Legacy (CONFIGURED unset) -> rc=0.
#
# Context inputs (all optional):
#   BRIK_COMMIT_TAG     - non-empty when running on a git tag
#   BRIK_COMMIT_BRANCH  - the current branch name (e.g. main, feat/x)
#   BRIK_DEFAULT_BRANCH - which branch counts as "main" (default: main)
#   BRIK_TRIGGER_MANUAL - "true" when the user manually fired the pipeline

# Guard against double-sourcing
[[ -n "${_BRIK_GATING_LOADED:-}" ]] && return 0
_BRIK_GATING_LOADED=1

# gating.should_run_stage <PREFIX>
gating.should_run_stage() {
    local prefix="${1:-}"
    if [[ -z "$prefix" ]]; then
        printf 'gating.should_run_stage: prefix is required\n' >&2
        return 2
    fi

    local configured_var="BRIK_${prefix}_TRIGGER_CONFIGURED"
    # Legacy: no trigger block on this stage -> always run.
    [[ "${!configured_var:-}" == "true" ]] || return 0

    local on_tag_var="BRIK_${prefix}_TRIGGER_ON_TAG"
    local on_main_var="BRIK_${prefix}_TRIGGER_ON_MAIN"
    local on_feature_var="BRIK_${prefix}_TRIGGER_ON_FEATURE"
    local manual_var="BRIK_${prefix}_TRIGGER_MANUAL"
    local on_tag="${!on_tag_var:-false}"
    local on_main="${!on_main_var:-false}"
    local on_feature="${!on_feature_var:-false}"
    local manual="${!manual_var:-false}"

    # on-tag: tag pushed -> any release/package/deploy with on-tag=true runs.
    if [[ "$on_tag" == "true" && -n "${BRIK_COMMIT_TAG:-}" ]]; then
        return 0
    fi

    # on-main / on-feature: branch context. Default branch resolves to
    # BRIK_DEFAULT_BRANCH or "main".
    local branch="${BRIK_COMMIT_BRANCH:-}"
    local default_branch="${BRIK_DEFAULT_BRANCH:-main}"
    if [[ -n "$branch" ]]; then
        if [[ "$on_main" == "true" && "$branch" == "$default_branch" ]]; then
            return 0
        fi
        if [[ "$on_feature" == "true" && "$branch" != "$default_branch" ]]; then
            return 0
        fi
    fi

    # manual: explicit user trigger.
    if [[ "$manual" == "true" && "${BRIK_TRIGGER_MANUAL:-}" == "true" ]]; then
        return 0
    fi

    return 1
}

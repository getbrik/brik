#!/usr/bin/env bash
# @module deploy.profile
# @description Deploy profile resolution and deep merge for workflow-based deployments.
#
# Provides convention defaults for trunk-based, git-flow, and github-flow
# workflows. Profile defaults are merged with user-provided brik.yml overrides
# using yq deep merge (user values take precedence).

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_DEPLOY_PROFILE_LOADED:-}" ]] && return 0
_BRIK_CORE_DEPLOY_PROFILE_LOADED=1

# Base directory for deploy profile data files.
# BASH_SOURCE[0] resolves to the profile.sh script location:
#   .../runtime/bash/lib/core/deploy/profile.sh
# Data files are at:
#   .../runtime/bash/lib/core/data/deploy-profiles/
_BRIK_DEPLOY_PROFILES_DIR="${BASH_SOURCE[0]%/*}/../data/deploy-profiles"

# Resolve the absolute path to a deploy profile YAML file.
# Usage: deploy.profile.resolve <workflow>
# Output: absolute path to the profile YAML file
# Returns: 0 on success, 2 on invalid/missing workflow
deploy.profile.resolve() {
    local workflow="$1"

    if [[ -z "$workflow" ]]; then
        log.error "workflow is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    case "$workflow" in
        trunk-based|git-flow|github-flow)
            printf '%s/%s.yml' "$_BRIK_DEPLOY_PROFILES_DIR" "$workflow"
            return 0
            ;;
        *)
            log.error "unknown workflow: $workflow (supported: trunk-based, git-flow, github-flow)"
            return "$BRIK_EXIT_INVALID_INPUT"
            ;;
    esac
}

# Deep merge a deploy profile with user-provided brik.yml overrides.
# The profile provides convention defaults; user brik.yml values take precedence.
# Writes the merged result to a temporary file and prints the path.
#
# Usage: deploy.profile.merge <workflow> <brik_yml_path>
# Output: path to temporary merged YAML file
# Returns: 0 on success, 2 on invalid input, 3 if yq missing, 6 if file not found
deploy.profile.merge() {
    local workflow="$1"
    local brik_yml_path="$2"

    if [[ -z "$workflow" ]]; then
        log.error "workflow is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ ! -f "$brik_yml_path" ]]; then
        log.error "brik.yml not found: $brik_yml_path"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    local profile_path
    profile_path="$(deploy.profile.resolve "$workflow")" || return $?

    if ! command -v yq >/dev/null 2>&1; then
        log.error "yq is required for profile merge but not found on PATH"
        return "$BRIK_EXIT_MISSING_DEP"
    fi

    # Create temporary file for the merged result
    local merged_file
    merged_file="$(mktemp /tmp/brik-profile-XXXXXX.yml)"
    chmod 600 "$merged_file"

    # Deep merge: profile is the base, user brik.yml overrides on top.
    # yq 'select(fileIndex == 0) * select(fileIndex == 1)' merges two files
    # with the second file's values taking precedence.
    local yq_stderr
    yq_stderr="$(yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
            "$profile_path" "$brik_yml_path" 2>&1 1>"$merged_file")"
    local yq_rc=$?
    if [[ $yq_rc -ne 0 ]]; then
        log.error "failed to merge profile with overrides: $yq_stderr"
        rm -f "$merged_file"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    printf '%s' "$merged_file"
    return 0
}

#!/usr/bin/env bash
# @module rollout.profile
# @description Deploy profile resolution and deep merge for workflow-based deployments.
#
# Provides convention defaults for trunk-based, git-flow, and github-flow
# workflows. Profile defaults are merged with user-provided brik.yml overrides
# using yq deep merge (user values take precedence).

# Guard against double-sourcing
[[ -n "${_BRIK_ROLLOUT_PROFILE_LOADED:-}" ]] && return 0
_BRIK_ROLLOUT_PROFILE_LOADED=1

# Base directory for deploy profile data files.
# BASH_SOURCE[0] resolves to the profile.sh script location:
#   .../lib/rollout/profile.sh
# Data files are at:
#   .../lib/rollout/data/deploy-profiles/
_BRIK_ROLLOUT_PROFILES_DIR="${BASH_SOURCE[0]%/*}/data/deploy-profiles"

# Resolve the absolute path to a deploy profile YAML file.
# Usage: rollout.profile.resolve <workflow>
# Output: absolute path to the profile YAML file
# Returns: 0 on success, 2 on invalid/missing workflow
rollout.profile.resolve() {
    local workflow="$1"

    if [[ -z "$workflow" ]]; then
        log.error "workflow is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    case "$workflow" in
        trunk-based|git-flow|github-flow)
            printf '%s/%s.yml' "$_BRIK_ROLLOUT_PROFILES_DIR" "$workflow"
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
# Usage: rollout.profile.merge <workflow> <brik_yml_path>
# Output: path to temporary merged YAML file
# Returns: 0 on success, 2 on invalid input, 3 if yq missing, 6 if file not found
rollout.profile.merge() {
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
    profile_path="$(rollout.profile.resolve "$workflow")" || return $?

    # Create temporary file for the merged result. The template keeps the X
    # run at the very end: busybox mktemp (Alpine runner images) rejects any
    # suffix after the X's (e.g. "...XXXXXX.yml"), which would make the merge
    # silently no-op and drop the whole profile. yq reads by content, so the
    # absent .yml extension is irrelevant.
    local merged_file
    merged_file="$(mktemp -t brik-profile.XXXXXX)"
    chmod 600 "$merged_file"

    # Deep merge: profile is the base, user brik.yml overrides on top.
    brik.use transverse.yaml
    if ! transverse.yaml.merge "$profile_path" "$brik_yml_path" --output "$merged_file"; then
        local rc=$?
        rm -f "$merged_file"
        return "$rc"
    fi

    printf '%s' "$merged_file"
    return 0
}

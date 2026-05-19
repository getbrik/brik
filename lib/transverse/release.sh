#!/usr/bin/env bash
# @module transverse/release
# @description Release-state compute helpers shared by stages.init (dotenv
#   export) and the planner (plan.json release block). Both consumers run
#   in separate processes -- the planner is the parent pipeline, init is
#   the child -- so the compute lives here as a small pure module rather
#   than as a runtime-shared variable.
#
# Three values:
#   profile      enum (trunk-based|git-flow|github-flow|none), from brik.yml
#   version      semver X.Y.Z derived from the latest git tag (stripped of
#                .release.tag_prefix), or "0.0.0" when no tag exists
#   is_candidate 1 when BRIK_COMMIT_TAG is set (a release tag push or the
#                profile-specific candidate condition), 0 otherwise

# Guard against double-sourcing.
[[ -n "${_BRIK_TRANSVERSE_RELEASE_LOADED:-}" ]] && return 0
_BRIK_TRANSVERSE_RELEASE_LOADED=1

# Read .release.profile from brik.yml. Defaults to "none".
# Requires BRIK_CONFIG_FILE to be set; falls back to "none" when the file
# is missing or unreadable so the caller never blocks on a missing config.
#
# Usage: release.compute_profile
release.compute_profile() {
    if [[ -z "${BRIK_CONFIG_FILE:-}" || ! -f "${BRIK_CONFIG_FILE}" ]]; then
        printf 'none'
        return 0
    fi
    if ! command -v yq >/dev/null 2>&1; then
        printf 'none'
        return 0
    fi
    local val
    val="$(yq -r '.release.profile // "none"' "${BRIK_CONFIG_FILE}" 2>/dev/null)" || val="none"
    [[ -z "$val" || "$val" == "null" ]] && val="none"
    printf '%s' "$val"
}

# Compute the project version. Strategy:
#   1. If git is available and the workspace has a tag at HEAD or earlier,
#      use the latest tag stripped of .release.tag_prefix (default "v").
#   2. Otherwise emit "0.0.0" -- a placeholder that downstream jobs see
#      as "no release ever cut yet", consistent with semver baseline.
#
# Phase 9.A scope: best-effort tag-based compute. Per the chantier,
# version.next_semver (auto-bump from conventional commits) is a separate
# follow-up; this helper stays read-only against existing tags.
#
# Usage: release.compute_version
release.compute_version() {
    local prefix="v"
    if [[ -n "${BRIK_CONFIG_FILE:-}" && -f "${BRIK_CONFIG_FILE}" ]] \
       && command -v yq >/dev/null 2>&1; then
        local cfg_prefix
        cfg_prefix="$(yq -r '.release.tag_prefix // "v"' "${BRIK_CONFIG_FILE}" 2>/dev/null)" || cfg_prefix="v"
        [[ -n "$cfg_prefix" && "$cfg_prefix" != "null" ]] && prefix="$cfg_prefix"
    fi

    local workspace="${BRIK_WORKSPACE:-$PWD}"
    if ! command -v git >/dev/null 2>&1; then
        printf '0.0.0'
        return 0
    fi
    local tag=""
    tag="$(git -C "$workspace" describe --tags --abbrev=0 2>/dev/null || true)"
    if [[ -z "$tag" ]]; then
        printf '0.0.0'
        return 0
    fi
    printf '%s' "${tag#"$prefix"}"
}

# 1 when BRIK_COMMIT_TAG is non-empty (release tag push), 0 otherwise.
# Phase 9.B-E will extend this to profile-specific candidate detection
# (e.g. trunk-based -> 1 on every default-branch push) by branching on
# release.compute_profile.
#
# Usage: release.compute_is_candidate
release.compute_is_candidate() {
    [[ -n "${BRIK_COMMIT_TAG:-}" ]] && printf '1' || printf '0'
}

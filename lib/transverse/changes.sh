#!/usr/bin/env bash
# @module changes
# @requires git
# @description Normalize the changed-files set across CI backends (GitLab CI,
#   Jenkins, local) for the Brik planner. The output is a NUL-separated list
#   of repo-relative paths on stdout. The source string (gitlab|jenkins|
#   local|none) is exported to BRIK_CHANGES_SOURCE so callers can serialize
#   it into plan.json without re-detecting.

# Guard against double-sourcing.
[[ -n "${_BRIK_TRANSVERSE_CHANGES_LOADED:-}" ]] && return 0
_BRIK_TRANSVERSE_CHANGES_LOADED=1

# Resolve <from_ref>..<to_ref> for the current backend.
# Outputs "<source> <from> <to>" on stdout, or "none" when nothing is usable.
# A missing <from> on a brand-new branch maps to source=none (no diff
# basis), not to a fake range -- callers must treat this as "cold start"
# (fall back to whole-repo or no-impact, never an empty file list).
_changes._resolve_range() {
    local workspace="${1:-.}"

    # GitLab: CI_COMMIT_BEFORE_SHA is 40 zeros on a new branch / first push.
    # CI_MERGE_REQUEST_DIFF_BASE_SHA is preferred in MR pipelines.
    if [[ -n "${CI_COMMIT_SHA:-}" ]]; then
        local from="${CI_MERGE_REQUEST_DIFF_BASE_SHA:-${CI_COMMIT_BEFORE_SHA:-}}"
        if [[ -n "$from" && "$from" != "0000000000000000000000000000000000000000" ]]; then
            printf 'gitlab %s %s' "$from" "$CI_COMMIT_SHA"
            return 0
        fi
    fi

    # Jenkins: GIT_PREVIOUS_SUCCESSFUL_COMMIT is the most stable basis
    # (avoids re-running the full pipeline on a retry); GIT_PREVIOUS_COMMIT
    # is the immediate predecessor.
    if [[ -n "${GIT_COMMIT:-}" ]]; then
        local from="${GIT_PREVIOUS_SUCCESSFUL_COMMIT:-${GIT_PREVIOUS_COMMIT:-}}"
        if [[ -n "$from" ]]; then
            printf 'jenkins %s %s' "$from" "$GIT_COMMIT"
            return 0
        fi
    fi

    # Local: honor an explicit override, otherwise diff against the
    # default branch's local tip (origin/main, origin/master, main, master).
    if [[ -n "${BRIK_CHANGES_FROM:-}" ]]; then
        printf 'local %s %s' "$BRIK_CHANGES_FROM" "${BRIK_CHANGES_TO:-HEAD}"
        return 0
    fi
    local candidate
    for candidate in origin/main origin/master main master; do
        if git -C "$workspace" rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
            printf 'local %s HEAD' "$candidate"
            return 0
        fi
    done

    printf 'none'
}

# Print the changed-files set as a NUL-separated stream of repo-relative
# paths on stdout. Exports BRIK_CHANGES_SOURCE and BRIK_CHANGES_RANGE for
# callers that need the provenance without re-detecting.
#
# When the range cannot be resolved (cold start on a fresh branch with no
# CI env), exports source=none and prints nothing. Callers should treat
# that as "impact selection cannot be trusted; default to run-all" rather
# than "no files changed".
#
# Usage: changes.diff [<workspace>]
changes.diff() {
    local workspace="${1:-${BRIK_WORKSPACE:-$PWD}}"

    local resolved source from to
    resolved="$(_changes._resolve_range "$workspace")"
    read -r source from to <<<"$resolved"

    export BRIK_CHANGES_SOURCE="$source"
    if [[ "$source" == "none" ]]; then
        export BRIK_CHANGES_RANGE=""
        return 0
    fi
    export BRIK_CHANGES_RANGE="${from}..${to}"

    # --name-only -z gives NUL-terminated entries safe for newlines /
    # special chars in paths. Stderr is dropped because git diff fails on
    # a missing base (e.g. shallow clone without the previous commit
    # fetched); the empty stream that follows is consistent with "I have
    # no reliable diff" and matches source=none semantics for the caller.
    git -C "$workspace" diff --name-only -z "${from}..${to}" 2>/dev/null \
        || git -C "$workspace" diff --name-only -z "$from" "$to" 2>/dev/null \
        || true
}

# Print the changed-files set as a newline-separated stream (each entry
# on its own line). Convenience for callers that don't need NUL safety;
# the planner uses changes.diff (NUL-separated) instead.
#
# Usage: changes.diff_lines [<workspace>]
changes.diff_lines() {
    local workspace="${1:-${BRIK_WORKSPACE:-$PWD}}"
    local f
    while IFS= read -r -d '' f; do
        printf '%s\n' "$f"
    done < <(changes.diff "$workspace")
}

# Print "source<TAB>from_ref<TAB>to_ref" on stdout for the resolved range,
# or "none<TAB><TAB>" when no diff basis exists. Lets the planner stamp
# the changes block into plan.json without invoking the diff itself.
#
# Usage: changes.metadata [<workspace>]
changes.metadata() {
    local workspace="${1:-${BRIK_WORKSPACE:-$PWD}}"
    local resolved source from to
    resolved="$(_changes._resolve_range "$workspace")"
    read -r source from to <<<"$resolved"
    printf '%s\t%s\t%s\n' "$source" "${from:-}" "${to:-}"
}

#!/usr/bin/env bash
# @module planning/plan_reader
# @requires jq
# @description Consumer API for a serialized plan.json. Used by
#   pipeline.run (D.4.8 gatekeeper), adapters (GitLab child, Jenkins,
#   local wrapper), and brik plan --explain.
#
# Default policy when no plan file exists: every stage should run. This
# preserves backward-compat with v0.5.x pipelines that don't invoke the
# planner yet -- the gatekeeper becomes a no-op until a plan is produced.

# Guard against double-sourcing.
[[ -n "${_BRIK_PLANNING_PLAN_READER_LOADED:-}" ]] && return 0
_BRIK_PLANNING_PLAN_READER_LOADED=1

# Resolve the plan file path. Order:
#   1. explicit <plan_file> arg
#   2. $BRIK_PLAN_FILE env var
#   3. default $BRIK_LOG_DIR/plan.json (then ${BRIK_WORKSPACE}/.brik-logs/plan.json)
#
# Prints the resolved path on stdout, or nothing when no candidate exists.
_plan_reader._resolve_path() {
    local explicit="${1:-}"
    if [[ -n "$explicit" && -f "$explicit" ]]; then
        printf '%s' "$explicit"
        return 0
    fi
    if [[ -n "${BRIK_PLAN_FILE:-}" && -f "$BRIK_PLAN_FILE" ]]; then
        printf '%s' "$BRIK_PLAN_FILE"
        return 0
    fi
    local candidate
    for candidate in \
        "${BRIK_LOG_DIR:-}/plan.json" \
        "${BRIK_WORKSPACE:-$PWD}/.brik-logs/plan.json" \
        "${PWD}/.brik-logs/plan.json"; do
        [[ -n "$candidate" && -f "$candidate" ]] && { printf '%s' "$candidate"; return 0; }
    done
    return 1
}

# Return 0 if <stage_id> should run according to <plan_file>.
# When no plan file exists, defaults to "run" (return 0) to keep the
# pipeline backward-compatible with non-plan-driven setups.
#
# Usage: pipeline.plan.should_run <stage_id> [<plan_file>]
pipeline.plan.should_run() {
    local stage_id="$1"
    local plan_file
    plan_file="$(_plan_reader._resolve_path "${2:-}")" || return 0
    command -v jq >/dev/null 2>&1 || return 0

    local decision
    decision="$(jq -r --arg id "$stage_id" \
        '.stages[]? | select(.id == $id) | .decision' "$plan_file" 2>/dev/null)"
    case "$decision" in
        skip) return 1 ;;
        run|"") return 0 ;;
        *)    return 0 ;;
    esac
}

# Print the reason code for <stage_id> from <plan_file>. Empty when no
# plan exists or the stage is not listed.
#
# Usage: pipeline.plan.reason <stage_id> [<plan_file>]
pipeline.plan.reason() {
    local stage_id="$1"
    local plan_file
    plan_file="$(_plan_reader._resolve_path "${2:-}")" || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r --arg id "$stage_id" \
        '.stages[]? | select(.id == $id) | .reason // ""' "$plan_file" 2>/dev/null
}

# Print runner_class for <stage_id>. Adapters use this to pick the
# container image for a child job. Empty when no plan exists.
#
# Usage: pipeline.plan.runner_class <stage_id> [<plan_file>]
pipeline.plan.runner_class() {
    local stage_id="$1"
    local plan_file
    plan_file="$(_plan_reader._resolve_path "${2:-}")" || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r --arg id "$stage_id" \
        '.stages[]? | select(.id == $id) | .runner_class // ""' "$plan_file" 2>/dev/null
}

# Print gate.mode for <stage_id>. Used by adapters that need to know
# whether a stage is opt-in (and might be optional) vs blocking.
#
# Usage: pipeline.plan.gate <stage_id> [<plan_file>]
pipeline.plan.gate() {
    local stage_id="$1"
    local plan_file
    plan_file="$(_plan_reader._resolve_path "${2:-}")" || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r --arg id "$stage_id" \
        '.stages[]? | select(.id == $id) | .gate.mode // ""' "$plan_file" 2>/dev/null
}

# Print the canonical stage order from the plan, one per line.
# Falls back to nothing when no plan exists (callers can use
# registry.stage.list as a default).
#
# Usage: pipeline.plan.stages [<plan_file>]
pipeline.plan.stages() {
    local plan_file
    plan_file="$(_plan_reader._resolve_path "${1:-}")" || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r '.stages[]?.id' "$plan_file" 2>/dev/null
}

# Print the fingerprint stored in the plan. Lets adapters cache or
# short-circuit when the plan has not changed across pipelines.
#
# Usage: pipeline.plan.fingerprint [<plan_file>]
pipeline.plan.fingerprint() {
    local plan_file
    plan_file="$(_plan_reader._resolve_path "${1:-}")" || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r '.fingerprint // ""' "$plan_file" 2>/dev/null
}

# Phase 9.A release accessors. Same resolution as the other readers:
# explicit plan_file > BRIK_PLAN_FILE > .brik-logs/plan.json. Empty
# stdout with rc=0 when no plan exists (backward-compat default).

# Print the git-workflow profile (trunk-based|git-flow|github-flow|none)
# the planner stamped into the plan. Adapters branch on this to decide
# candidate vs release routing for the promote stage (Phase 9.B-E).
#
# Usage: pipeline.plan.release_profile [<plan_file>]
pipeline.plan.release_profile() {
    local plan_file
    plan_file="$(_plan_reader._resolve_path "${1:-}")" || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r '.release.profile // ""' "$plan_file" 2>/dev/null
}

# Print the project version (X.Y.Z) the planner computed at plan time.
# Falls back to 0.0.0 when no git tag was reachable. Consumers should
# treat 0.0.0 as "no release ever cut yet", not as "version is invalid".
#
# Usage: pipeline.plan.release_version [<plan_file>]
pipeline.plan.release_version() {
    local plan_file
    plan_file="$(_plan_reader._resolve_path "${1:-}")" || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r '.release.version // ""' "$plan_file" 2>/dev/null
}

# Return 0 (rc) when the plan marks the current commit as a release
# candidate (release.is_candidate=true), 1 otherwise. No stdout. Mirrors
# the should_run/skip convention so callers can use it in `if`.
#
# Usage: pipeline.plan.is_candidate [<plan_file>]
pipeline.plan.is_candidate() {
    local plan_file
    plan_file="$(_plan_reader._resolve_path "${1:-}")" || return 1
    command -v jq >/dev/null 2>&1 || return 1
    local val
    val="$(jq -r '.release.is_candidate // false' "$plan_file" 2>/dev/null)"
    [[ "$val" == "true" ]]
}

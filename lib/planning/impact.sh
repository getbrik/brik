#!/usr/bin/env bash
# @module planning/impact
# @description Glob-matching primitives used by the planner to decide whether
#   a stage is impacted by the changed-files set.
#
# Three layers:
#   - impact.match_any         pure glob-vs-file matching (no registry I/O)
#   - impact.stage_patterns    resolves the effective glob set for a stage
#                              (own spec.impact.changes, OR use_stack_impact
#                              redirection to the active stack)
#   - impact.stage_is_impacted combines both (returns 0 if at least one
#                              changed file matches at least one pattern)

# Guard against double-sourcing.
[[ -n "${_BRIK_PLANNING_IMPACT_LOADED:-}" ]] && return 0
_BRIK_PLANNING_IMPACT_LOADED=1

# shellcheck source=../registry/registry.sh
. "${BASH_SOURCE[0]%/*}/../registry/registry.sh"

# Bash globstar lets `**` match across directory boundaries when we use
# [[ "$path" == $pattern ]]. Without it, `**/*.js` is two literal `*`s
# and only matches a single segment. We turn it on once at source time;
# it's a shell-wide opt-in and the only place we rely on it.
shopt -s globstar 2>/dev/null || true

# Return 0 (true) if <path> matches <pattern>. Pattern syntax is bash
# extended glob with globstar (`**` crosses directories). Lone `*` does
# NOT cross directories (matches POSIX glob behavior).
#
# Usage: impact.match_one <path> <pattern>
impact.match_one() {
    local path="$1" pattern="$2"
    [[ -z "$pattern" ]] && return 1
    # The unquoted $pattern is intentional: case treats it as a glob, which
    # is exactly the matching semantics we want (no filesystem expansion,
    # purely textual). Quoting would degrade glob to a literal-string match.
    # shellcheck disable=SC2254
    case "$path" in
        $pattern) return 0 ;;
        *)        return 1 ;;
    esac
}

# Return 0 if <path> matches at least one of <pattern...>. Short-circuits
# on the first match.
#
# Usage: impact.match_any <path> <pattern> [<pattern>...]
impact.match_any() {
    local path="$1"; shift
    local pat
    for pat in "$@"; do
        impact.match_one "$path" "$pat" && return 0
    done
    return 1
}

# Print, one per line, the resolved set of impact globs for <stage_id>.
# Resolution order:
#   1. spec.impact.changes (literal glob list owned by the stage)
#   2. spec.impact.use_stack_impact -> stack's source|test|build set
#   3. neither -> nothing printed (caller must decide: treat absence as
#      "always run" or "fall back to context-only").
#
# Usage: impact.stage_patterns <stage_id> [<stack_id>]
impact.stage_patterns() {
    local stage_id="$1"
    local stack_id="${2:-${BRIK_BUILD_STACK:-}}"

    local own
    own="$(registry.stage.impact_changes "$stage_id" 2>/dev/null | sed '/^$/d')" || true
    if [[ -n "$own" ]]; then
        printf '%s\n' "$own"
        return 0
    fi

    local use
    use="$(registry.stage.impact_use_stack_impact "$stage_id" 2>/dev/null || true)"
    [[ -z "$use" || -z "$stack_id" ]] && return 0

    case "$use" in
        source) registry.stack.impact_source "$stack_id" 2>/dev/null | sed '/^$/d' ;;
        test)   registry.stack.impact_test   "$stack_id" 2>/dev/null | sed '/^$/d' ;;
        build)  registry.stack.impact_build  "$stack_id" 2>/dev/null | sed '/^$/d' ;;
    esac
}

# Determine whether the stage is impacted by the changed-files set.
# Returns 0 (impacted, run the stage) or 1 (not impacted, candidate for
# skip).
#
# The changed-files set is read from <changes_file> (a NUL-separated file
# of repo-relative paths produced by changes.diff). The function may be
# called many times in a planning run, so reading from a stable file is
# cheaper than re-running `git diff` per stage.
#
# Two short-circuits:
#   - resolved pattern set is empty -> impacted (be conservative; the
#     stage chose not to declare impact, so we run it)
#   - changed file list is empty (no diff basis) -> impacted (cold start)
#
# Usage: impact.stage_is_impacted <stage_id> <stack_id> <changes_file>
impact.stage_is_impacted() {
    local stage_id="$1"
    local stack_id="${2:-}"
    local changes_file="${3:-}"

    local -a patterns=()
    mapfile -t patterns < <(impact.stage_patterns "$stage_id" "$stack_id")
    [[ ${#patterns[@]} -eq 0 ]] && return 0

    [[ -z "$changes_file" || ! -s "$changes_file" ]] && return 0

    local file
    while IFS= read -r -d '' file; do
        if impact.match_any "$file" "${patterns[@]}"; then
            return 0
        fi
    done <"$changes_file"
    return 1
}

# Print, one per line, the patterns that matched at least one file in
# the changed-files set. Used by the planner to record
# stages[].matched_globs in plan.json for explainability.
#
# Usage: impact.stage_matched_globs <stage_id> <stack_id> <changes_file>
impact.stage_matched_globs() {
    local stage_id="$1"
    local stack_id="${2:-}"
    local changes_file="${3:-}"

    local -a patterns=()
    mapfile -t patterns < <(impact.stage_patterns "$stage_id" "$stack_id")
    [[ ${#patterns[@]} -eq 0 ]] && return 0
    [[ -z "$changes_file" || ! -s "$changes_file" ]] && return 0

    local -A hits=()
    local file pat
    while IFS= read -r -d '' file; do
        for pat in "${patterns[@]}"; do
            [[ -n "${hits[$pat]:-}" ]] && continue
            if impact.match_one "$file" "$pat"; then
                hits[$pat]=1
            fi
        done
    done <"$changes_file"
    for pat in "${patterns[@]}"; do
        [[ -n "${hits[$pat]:-}" ]] && printf '%s\n' "$pat"
    done
    return 0
}

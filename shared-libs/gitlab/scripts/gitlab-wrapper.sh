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

    # Dry-run normalization. GitLab promotes CI/CD variables to env vars
    # automatically, but the contract for BRIK_DRY_RUN -- exact string
    # "true" enables, anything else disables -- is enforced here so that
    # the value lib/ sees is always canonical. Mirrors the Jenkins
    # booleanParam semantics declared in vars/brikIntegrate.groovy.
    _brik_gitlab_normalize_dry_run

    brik.wrapper.set_standard_env
    brik.wrapper.bootstrap || return $?
    brik.wrapper.load_config || return $?

    log.info "brik gitlab setup complete (BRIK_HOME=$BRIK_HOME)"
    return 0
}

# Normalize BRIK_DRY_RUN to a canonical "true"/"false" string. Unknown or
# misspelled values (1, yes, on, ...) are downgraded to "false" with a
# warning so that lib/ -- which compares against the literal "true" -- has
# a single source of truth. Unset or empty -> "false".
_brik_gitlab_normalize_dry_run() {
    local raw="${BRIK_DRY_RUN:-false}"
    case "$raw" in
        true)
            export BRIK_DRY_RUN="true"
            ;;
        false|"")
            export BRIK_DRY_RUN="false"
            ;;
        *)
            if declare -f log.warn >/dev/null 2>&1; then
                log.warn "BRIK_DRY_RUN has unexpected value '${raw}', treating as false (use 'true' to enable)"
            else
                echo "warning: BRIK_DRY_RUN has unexpected value '${raw}', treating as false (use 'true' to enable)" >&2
            fi
            export BRIK_DRY_RUN="false"
            ;;
    esac
}

# Pre-create the GitLab cache and artefact directories declared in the job
# templates (build.yml, test.yml, ...). The active stack only populates one
# or two of them, so GitLab logs "no matching files" for every other path
# on every run. Pre-creating each path with an empty .brik-keep file makes
# the cache/artefact step always find at least one entry and stay silent.
#
# Cache paths come from the canonical lib/stacks/_deps.sh::stacks.cache_paths.
# Artefact output dirs (coverage, reports, build, target, bin, dist) stay
# inline because they are stack-independent. Glob placeholders cover the
# artifacts:paths glob patterns (*.whl, *.tar.gz, reports/*.xml) that no
# stack output directory can satisfy.
#
# Arguments: $1 = workspace dir (optional, defaults to $BRIK_WORKSPACE).
# Operates inside a subshell so the caller's PWD is never altered.
# Returns: 0 on success or partial success; 4 if no workspace can be resolved.
# A read-only filesystem or per-path permission error is tolerated: one bad
# path must not break the rest of the stage.
_brik_gitlab._ensure_artefact_markers() {
    local workspace="${1:-${BRIK_WORKSPACE:-}}"

    if [[ -z "$workspace" ]]; then
        echo "error: _brik_gitlab._ensure_artefact_markers: workspace required (set BRIK_WORKSPACE or pass as \$1)" >&2
        return "$BRIK_EXIT_INVALID_ENV"
    fi
    if [[ ! -d "$workspace" ]]; then
        echo "error: _brik_gitlab._ensure_artefact_markers: workspace not a directory: $workspace" >&2
        return "$BRIK_EXIT_INVALID_ENV"
    fi

    # Ensure stacks.cache_paths is loaded. The _deps.sh double-source guard
    # makes this safe to call on every stage; BRIK_HOME is validated before
    # any caller reaches this function.
    if ! declare -f stacks.cache_paths >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        . "${BRIK_HOME}/lib/stacks/_deps.sh"
    fi

    # Stack cache paths -- single source of truth.
    local stack_paths=()
    local _p
    while IFS= read -r _p; do
        stack_paths+=("$_p")
    done < <(stacks.cache_paths)

    # Stage artefact output dirs (stack-independent, kept inline).
    local artefact_paths=(
        "coverage"
        "reports"
        "build"
        "target"
        "bin"
        "dist"
    )
    # Glob-pattern placeholders: artifacts:paths and reports:junit list
    # glob patterns (*.whl, *.tar.gz, reports/*.xml) that no stack-output
    # dir can satisfy. A zero-byte placeholder file matches the glob and
    # silences the warning without affecting real archives produced by the
    # stage.
    local glob_placeholders=(
        ".brik-keep.whl"
        ".brik-keep.tar.gz"
        "reports/.brik-keep.xml"
    )
    (
        cd "$workspace" || exit 0
        local p
        for p in "${stack_paths[@]}" "${artefact_paths[@]}"; do
            [[ -f "$p/.brik-keep" ]] && continue
            mkdir -p "$p" 2>/dev/null || continue
            : > "$p/.brik-keep" 2>/dev/null || true
        done
        for p in "${glob_placeholders[@]}"; do
            [[ -f "$p" ]] && continue
            mkdir -p "$(dirname "$p")" 2>/dev/null || continue
            : > "$p" 2>/dev/null || true
        done
    )
    return 0
}

# Pre-create the cache/artefact markers for a stage the plan skipped.
# A plan-skipped stage job exits (via /tmp/brik-plan-gate.sh) before
# brik.gitlab.run_stage runs, so GitLab's cache/artifact steps would log
# "no files to cache/upload" for the declared paths. Seeding the markers
# keeps a skipped job's log as quiet as a job that actually ran.
# Usage: brik.gitlab.mark_skipped [workspace]
brik.gitlab.mark_skipped() {
    _brik_gitlab._ensure_artefact_markers \
        "${1:-${BRIK_WORKSPACE:-${CI_PROJECT_DIR:-$PWD}}}" >/dev/null 2>&1 || true
}

# Run a stage by name. Dispatches to portable stages.* functions via stage.run.
# Usage: brik.gitlab.run_stage <stage_name>
brik.gitlab.run_stage() {
    # Pre-create cache/artefact markers so GitLab's cache and artifact steps
    # never log "no matching files" for stack paths the active build does
    # not populate. Skip silently when BRIK_WORKSPACE is not set (e.g. early
    # CLI errors before setup ran); the function's hard-fail mode is reserved
    # for direct callers.
    if [[ -n "${BRIK_WORKSPACE:-}" ]]; then
        _brik_gitlab._ensure_artefact_markers "$BRIK_WORKSPACE" >/dev/null 2>&1 || true
    fi

    brik.wrapper.run_stage "$@"
}

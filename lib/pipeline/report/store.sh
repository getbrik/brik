#!/usr/bin/env bash
# @module report.store
# @requires jq
# @description Backend storage API for the pipeline report.
#
# Owns the aggregate-report.json backing store: skeleton creation, the
# record/read API surface, and the atomic read-modify-write helpers. Split
# out of lib/pipeline/report.sh; loaded by the report.sh facade, which owns
# the shared dependencies (logging, error) and the jq duration library.
#
# Public API (see report.sh for the lifecycle contract):
#   report.init
#   report.record <stage> <category> <key> <value>
#   report.record_object <stage> <category> <key> <json_value>
#   report.has_status <stage>
#   report.read <stage> <category> <key> [default]

[[ -n "${_BRIK_REPORT_STORE_LOADED:-}" ]] && return 0
_BRIK_REPORT_STORE_LOADED=1

# shellcheck source=../logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../logging.sh"
# shellcheck source=../error.sh
[[ -z "${_BRIK_ERROR_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../error.sh"

# Resolve the backend JSON path from BRIK_LOG_DIR.
_report._backend_path() {
    local log_dir
    log_dir="$(_brik.log_dir._resolve)"
    printf '%s/aggregate-report.json' "$log_dir"
}

# Require jq on PATH. Returns BRIK_EXIT_MISSING_DEP if absent.
_report._require_jq() {
    command -v jq >/dev/null 2>&1 || {
        log.error "jq is required for report.*"
        return "$BRIK_EXIT_MISSING_DEP"
    }
}

# Create (or overwrite) the aggregate-report.json skeleton.
# Uses BRIK_RUN_ID as pipeline_id (falls back to epoch-pid if unset).
# Stamps pipeline.{id,project,platform,commit_ref,started_at} from the
# environment so the local backend carries the same identity surface as the
# CI aggregate (single-stage paths via stage.dispatch lazy-init also benefit).
report.init() {
    _report._require_jq || return "$?"

    local log_dir
    log_dir="$(_brik.log_dir._resolve)"
    mkdir -p "$log_dir" || {
        log.error "cannot create log directory: $log_dir"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    local backend
    backend="$(_report._backend_path)"
    local pipeline_id="${BRIK_RUN_ID:-$(date +%s)-$$}"
    local started_at
    started_at="$(date +"%Y-%m-%dT%H:%M:%S%z")"
    local platform="${BRIK_PLATFORM:-local}"
    local project="${BRIK_PROJECT_NAME:-unnamed}"
    local commit_ref="${BRIK_COMMIT_REF:-}"

    # KCOV_EXCL_START  -- jq script body is not bash code
    jq -n \
        --arg pid "$pipeline_id" \
        --arg started "$started_at" \
        --arg project "$project" \
        --arg platform "$platform" \
        --arg commit_ref "$commit_ref" \
        '{
            pipeline_id: $pid,
            started_at: $started,
            finished_at: null,
            pipeline: {
                id: $pid,
                project: $project,
                platform: $platform,
                started_at: $started,
                commit_ref: (if $commit_ref == "" then null else $commit_ref end)
            },
            stages: []
        }' \
        > "$backend" || {
        log.error "cannot initialize report: $backend"
        return "$BRIK_EXIT_IO_FAILURE"
    }
    # KCOV_EXCL_STOP
    log.debug "report initialized: $backend"
    return 0
}

# Append or upsert a key/value under a stage's tech or business section.
# Usage: report.record <stage> <category> <key> <value>
report.record() {
    [[ $# -eq 4 ]] || {
        error.raise "$BRIK_EXIT_INVALID_INPUT" \
            "report.record expects 4 arguments: stage category key value (got $#)"
        return "$?"
    }
    local stage="$1" category="$2" key="$3" value="$4"

    case "$category" in
        tech|business|env) ;;
        *)
            error.raise "$BRIK_EXIT_INVALID_INPUT" \
                "report.record: invalid category '$category' (expected tech|business|env)"
            return "$?"
            ;;
    esac

    _report._require_jq || return "$?"

    local backend
    backend="$(_report._backend_path)"
    [[ -f "$backend" ]] || {
        log.error "report not initialized: $backend (call report.init first)"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    _report._append_json "$backend" "$stage" "$category" "$key" "$value"
}

# Companion to report.record for nested JSON values (objects, arrays,
# booleans, numbers). value MUST be valid JSON; report.record stores
# values as JSON strings via --arg, which collapses nesting -- this
# helper uses --argjson so the structure is preserved.
#
# Usage: report.record_object <stage> <category> <key> <json_value>
report.record_object() {
    [[ $# -eq 4 ]] || {
        error.raise "$BRIK_EXIT_INVALID_INPUT" \
            "report.record_object expects 4 arguments: stage category key json_value (got $#)"
        return "$?"
    }
    local stage="$1" category="$2" key="$3" value="$4"

    case "$category" in
        tech|business|env) ;;
        *)
            error.raise "$BRIK_EXIT_INVALID_INPUT" \
                "report.record_object: invalid category '$category' (expected tech|business|env)"
            return "$?"
            ;;
    esac

    _report._require_jq || return "$?"

    if ! jq . >/dev/null 2>&1 <<<"$value"; then
        error.raise "$BRIK_EXIT_INVALID_INPUT" \
            "report.record_object: invalid JSON value for ${stage}.${category}.${key}"
        return "$?"
    fi

    local backend
    backend="$(_report._backend_path)"
    [[ -f "$backend" ]] || {
        log.error "report not initialized: $backend (call report.init first)"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    _report._append_json_object "$backend" "$stage" "$category" "$key" "$value"
}

# Check whether a stage already has a tech.status recorded in the report.
# Used by pipeline.run to avoid overwriting a status that a stage set itself
# (e.g. a config-skipped stage that records status=skipped before returning 0).
# Usage: report.has_status <stage>
# Returns: 0 if status is present, 1 if absent, BRIK_EXIT_INVALID_INPUT on bad arg.
report.has_status() {
    local stage="${1:-}"
    if [[ -z "$stage" ]]; then
        error.raise "$BRIK_EXIT_INVALID_INPUT" \
            "report.has_status expects 1 argument: stage"
        return "$?"
    fi

    local backend
    backend="$(_report._backend_path)"
    [[ -f "$backend" ]] || return 1

    command -v jq >/dev/null 2>&1 || return 1

    local status
    status="$(jq -r --arg s "$stage" \
        '.stages[] | select(.stage == $s) | .tech.status // empty' \
        "$backend" 2>/dev/null)" || return 1

    [[ -n "$status" ]]
}

# Read a recorded value from the backend JSON.
# Usage: report.read <stage> <category> <key> [default]
# Prints the recorded value, or default (or empty) when the key is absent.
# Returns 0 always when arguments are valid (so callers can rely on the
# printed string and use a default for absent keys without branching).
report.read() {
    if [[ $# -lt 3 || $# -gt 4 ]]; then
        error.raise "$BRIK_EXIT_INVALID_INPUT" \
            "report.read expects 3-4 arguments: stage category key [default] (got $#)"
        return "$?"
    fi
    local stage="$1" category="$2" key="$3" default="${4:-}"

    case "$category" in
        tech|business|env) ;;
        *)
            error.raise "$BRIK_EXIT_INVALID_INPUT" \
                "report.read: invalid category '$category' (expected tech|business|env)"
            return "$?"
            ;;
    esac

    _report._require_jq || return "$?"

    local backend
    backend="$(_report._backend_path)"
    [[ -f "$backend" ]] || {
        log.error "report not initialized: $backend (call report.init first)"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    local value
    value="$(jq -r --arg s "$stage" --arg c "$category" --arg k "$key" \
        '.stages[]? | select(.stage == $s) | .[$c][$k] // empty' \
        "$backend" 2>/dev/null)" || value=""

    if [[ -n "$value" ]]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$default"
    fi
    return 0
}

# Atomic read-modify-write of the backend JSON: create stage on first touch,
# then set .stages[name=stage].<category>.<key> = value.
_report._append_json() {
    local backend="$1" stage="$2" category="$3" key="$4" value="$5"

    local tmp
    tmp="$(mktemp "${backend}.XXXXXX")" || {
        log.error "cannot create temp file for report"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    # The jq read + mv must be atomic vs concurrent writers (Jenkins parallel
    # verify: lint/sast/scan/test share the same backend). Without the lock,
    # last-writer-wins discards updates whose read happened before our mv.
    local lock_file="${backend}.lock"
    local rc=0
    {
        if command -v flock >/dev/null 2>&1; then
            flock -x 9 || { log.error "cannot acquire report lock"; return "$BRIK_EXIT_IO_FAILURE"; }
        fi
        # KCOV_EXCL_START  -- jq script body is not bash code
        jq \
            --arg stage "$stage" \
            --arg category "$category" \
            --arg key "$key" \
            --arg value "$value" \
            '
            def ensure_stage(s):
              if any(.stages[]; .stage == s) then .
              else .stages += [{ stage: s, tech: {}, business: {}, env: {} }]
              end;
            ensure_stage($stage)
            | .stages |= map(
                if .stage == $stage then
                  .[$category][$key] = $value
                else .
                end
              )
            ' "$backend" > "$tmp" && mv "$tmp" "$backend"
        rc=$?
        # KCOV_EXCL_STOP
    } 9>>"$lock_file"

    if [[ $rc -ne 0 ]]; then
        rm -f "$tmp"
        log.error "cannot append to report: $backend"
        return "$BRIK_EXIT_IO_FAILURE"
    fi
    return 0
}

# Atomic read-modify-write variant of _report._append_json that stores
# the value as a JSON-typed term (object, array, scalar) via --argjson
# instead of a JSON-encoded string. Caller must have validated the JSON.
_report._append_json_object() {
    local backend="$1" stage="$2" category="$3" key="$4" value="$5"

    local tmp
    tmp="$(mktemp "${backend}.XXXXXX")" || {
        log.error "cannot create temp file for report"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    local lock_file="${backend}.lock"
    local rc=0
    {
        if command -v flock >/dev/null 2>&1; then
            flock -x 9 || { log.error "cannot acquire report lock"; return "$BRIK_EXIT_IO_FAILURE"; }
        fi
        # KCOV_EXCL_START  -- jq script body is not bash code
        jq \
            --arg stage "$stage" \
            --arg category "$category" \
            --arg key "$key" \
            --argjson value "$value" \
            '
            def ensure_stage(s):
              if any(.stages[]; .stage == s) then .
              else .stages += [{ stage: s, tech: {}, business: {}, env: {} }]
              end;
            ensure_stage($stage)
            | .stages |= map(
                if .stage == $stage then
                  .[$category][$key] = $value
                else .
                end
              )
            ' "$backend" > "$tmp" && mv "$tmp" "$backend"
        rc=$?
        # KCOV_EXCL_STOP
    } 9>>"$lock_file"

    if [[ $rc -ne 0 ]]; then
        rm -f "$tmp"
        log.error "cannot append object to report: $backend"
        return "$BRIK_EXIT_IO_FAILURE"
    fi
    return 0
}

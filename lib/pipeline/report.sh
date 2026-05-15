#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module report
# @description Persistent pipeline-level report aggregator.
#
# Records tech and business metrics per stage to a JSON backing store
# ($BRIK_LOG_DIR/aggregate-report.json) and renders Markdown + JSON outputs
# for human readers and CI artifacts.
#
# Lifecycle:
#   report.init                              # once, at pipeline start
#   report.record <stage> <cat> <key> <val>  # from each stage (cat = tech|business)
#   report.render [--format md|json|both]    # once, at pipeline end (default: both)

# Guard against double-sourcing
[[ -n "${_BRIK_REPORT_LOADED:-}" ]] && return 0
_BRIK_REPORT_LOADED=1

# Source dependencies
# shellcheck source=logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/logging.sh"
# shellcheck source=error.sh
[[ -z "${_BRIK_ERROR_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/error.sh"
# shellcheck source=../transverse/sarif.sh
[[ -z "${_BRIK_TRANSVERSE_SARIF_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../transverse/sarif.sh"
# shellcheck source=report_html.sh
[[ -z "${_BRIK_REPORT_HTML_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/report_html.sh"

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

    jq -n \
        --arg pid "$pipeline_id" \
        --arg started "$started_at" \
        '{ pipeline_id: $pid, started_at: $started, finished_at: null, stages: [] }' \
        > "$backend" || {
        log.error "cannot initialize report: $backend"
        return "$BRIK_EXIT_IO_FAILURE"
    }
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
        '.stages[] | select(.name == $s) | .tech.status // empty' \
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
        '.stages[]? | select(.name == $s) | .[$c][$k] // empty' \
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
              if any(.stages[]; .name == s) then .
              else .stages += [{ name: s, tech: {}, business: {}, env: {} }]
              end;
            ensure_stage($stage)
            | .stages |= map(
                if .name == $stage then
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
              if any(.stages[]; .name == s) then .
              else .stages += [{ name: s, tech: {}, business: {}, env: {} }]
              end;
            ensure_stage($stage)
            | .stages |= map(
                if .name == $stage then
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

# Write a per-stage report fragment to brik-artifacts/<stage>.json so CI
# platforms (GitLab, Jenkins) can ship it as a job artifact and notify can
# aggregate fragments back into a single aggregate-report at the end.
#
# The fragment is a snapshot of the backend aggregate-report.json entry for
# this stage, wrapped in the v1 fragment envelope (schema_version, stage,
# timestamp, rc, status, runner). When the backend has no entry for this
# stage, the fragment is a stub with status=skipped, rc=0.
#
# Output path:
#   - ${BRIK_WORKSPACE}/brik-artifacts/<stage>/<stage>.json when BRIK_WORKSPACE is set
#   - ${BRIK_LOG_DIR}/brik-artifacts/<stage>/<stage>.json otherwise (local fallback)
#
# Runner provenance:
#   - platform := BRIK_PLATFORM (default: local)
#   - image    := BRIK_RUNNER_IMAGE (omitted when unset)
#   - job_url  := CI_JOB_URL (GitLab) or BUILD_URL (Jenkins), omitted when unset
#
# Usage: report.write_fragment <stage_name>
# Returns: 0 on success, BRIK_EXIT_INVALID_INPUT on bad args,
#          BRIK_EXIT_MISSING_DEP if jq is absent, BRIK_EXIT_IO_FAILURE on
#          backend missing or write failure.
#
# Note: the parameter is named `stage_name` rather than `stage` to avoid
# dynamic-scope shadowing of any caller's `stage` local variable (Bash
# locals are visible to callees through dynamic scope).
report.write_fragment() {
    if [[ $# -ne 1 ]]; then
        error.raise "$BRIK_EXIT_INVALID_INPUT" \
            "report.write_fragment expects 1 argument: stage (got $#)"
        return "$?"
    fi
    local stage_name="$1"
    if [[ -z "$stage_name" ]]; then
        error.raise "$BRIK_EXIT_INVALID_INPUT" \
            "report.write_fragment: stage name must not be empty"
        return "$?"
    fi

    _report._require_jq || return "$?"

    local backend
    backend="$(_report._backend_path)"
    [[ -f "$backend" ]] || {
        log.error "report not initialized: $backend (call report.init first)"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    local fragment_dir="${BRIK_WORKSPACE:-$(_brik.log_dir._resolve)}/brik-artifacts"
    local stage_dir="${fragment_dir}/${stage_name}"
    mkdir -p "$stage_dir" || {
        log.error "cannot create fragment directory: $stage_dir"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    local fragment_path="${stage_dir}/${stage_name}.json"
    local timestamp
    timestamp="$(date +"%Y-%m-%dT%H:%M:%S%z")"
    local platform="${BRIK_PLATFORM:-local}"
    local image="${BRIK_RUNNER_IMAGE:-}"
    local job_url="${CI_JOB_URL:-${BUILD_URL:-}}"

    local tmp
    tmp="$(mktemp "${fragment_path}.XXXXXX")" || {
        log.error "cannot create temp fragment file"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    # KCOV_EXCL_START  -- jq script body is not bash code
    jq \
        --arg stage_name "$stage_name" \
        --arg timestamp "$timestamp" \
        --arg platform "$platform" \
        --arg image "$image" \
        --arg job_url "$job_url" \
        '
        ( [ .stages[] | select(.name == $stage_name) ][0] // {} ) as $entry
        | ( $entry.tech     // {} ) as $tech
        | ( $entry.business // {} ) as $business
        | ( $entry.env      // {} ) as $env
        | ( $tech.status    // "skipped" ) as $status
        | ( ($tech.exit_code // 0) | tonumber? // 0 ) as $rc
        | ( $tech.duration_ms ) as $duration_raw
        # v1.1 requires business.status. When the stage did not write one
        # (legacy producer, stub fragment for a stage absent from the
        # backend, ...), default from tech.status: success/skipped map to
        # success, failed maps to error. _stage._record_business overrides
        # this for stages that ran through the matrix.
        | ( if ($business | type) == "object" and ($business | has("status"))
            then $business
            else $business + { status: ( if $status == "failed" then "error" else "success" end ) }
            end ) as $business_v11
        | ( {
            schema_version: "1.1",
            stage: $stage_name,
            timestamp: $timestamp,
            rc: $rc,
            status: $status,
            runner: ( { platform: $platform }
                      + ( if $image   != "" then { image:   $image   } else {} end )
                      + ( if $job_url != "" then { job_url: $job_url } else {} end ) ),
            tech: $tech,
            business: $business_v11
          }
          + ( if $duration_raw == null or $duration_raw == "" then {}
              else { duration_ms: ($duration_raw | tonumber? // 0) } end )
          + ( if ($env | length) > 0 then { env: $env } else {} end ) )
        ' "$backend" > "$tmp" || {
        rm -f "$tmp"
        log.error "cannot build fragment for stage: $stage_name"
        return "$BRIK_EXIT_IO_FAILURE"
    }
    # KCOV_EXCL_STOP

    mv "$tmp" "$fragment_path" || {
        rm -f "$tmp"
        log.error "cannot write fragment: $fragment_path"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    log.debug "fragment written: $fragment_path"
    return 0
}

# Aggregate per-stage fragment files into a single aggregate-report.{md,json}
# under $BRIK_LOG_DIR. Used by stages.notify in CI mode where each upstream
# stage runs in its own container and ships its fragment as a job artifact.
# In local mode this function is not called (pipeline.run already produces
# the aggregate directly via report.record + report.render).
#
# Filtering rules:
#   - <dir>/aggregate-report.json is ignored (it is the aggregate target).
#   - Files that are not valid JSON are silently skipped.
#   - Files lacking the fragment signature (.stage and .schema_version) are
#     silently skipped (forward-compat with arbitrary brik-artifacts/ content).
#   - Files with schema_version not in {"1.0","1.1"} are warn-and-skipped
#     (decision 7: forward-compat with future v2 fragments). v1.0 stays
#     readable through the chantier 11 transition window so archived
#     fragments and external producers keep aggregating cleanly while
#     they migrate; the runtime itself emits v1.1.
#
# Pipeline metadata sources (decision 5: env-first in v1):
#   - pipeline.id        := BRIK_RUN_ID
#   - pipeline.platform  := BRIK_PLATFORM (default "local")
#   - pipeline.project   := BRIK_PROJECT_NAME (default "unnamed")
#   - pipeline.started_at:= earliest fragment timestamp, or now when none
#   - pipeline.finished_at:= now
#   - pipeline.status    := "failed" if any stage failed, else "success"
#
# Usage: report.aggregate_fragments <dir>
# Returns: 0 on success, BRIK_EXIT_INVALID_INPUT on bad args,
#          BRIK_EXIT_MISSING_DEP if jq is absent, BRIK_EXIT_IO_FAILURE on
#          missing dir or write failure.
report.aggregate_fragments() {
    if [[ $# -ne 1 ]]; then
        if [[ $# -eq 0 ]]; then
            error.raise "$BRIK_EXIT_INVALID_INPUT" \
                "report.aggregate_fragments expects 1 argument: directory (got 0)"
        else
            error.raise "$BRIK_EXIT_INVALID_INPUT" \
                "report.aggregate_fragments expects 1 argument: directory (got $#)"
        fi
        return "$?"
    fi
    local fragment_dir="$1"
    if [[ ! -d "$fragment_dir" ]]; then
        log.error "fragment directory not found: $fragment_dir"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    _report._require_jq || return "$?"

    local log_dir
    log_dir="$(_brik.log_dir._resolve)"
    mkdir -p "$log_dir" || {
        log.error "cannot create log directory: $log_dir"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    # Collect valid fragment paths into a tmp index file.
    local valid_list
    valid_list="$(mktemp)" || {
        log.error "cannot create temp index"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    shopt -s nullglob
    local f base
    for f in "$fragment_dir"/*/*.json; do
        base="$(basename "$f")"
        # Ignore the aggregate output if it lives in the same directory.
        [[ "$base" == "aggregate-report.json" ]] && continue
        # Must be valid JSON object with the fragment signature.
        if ! jq -e 'type == "object" and has("stage") and has("schema_version")' \
                "$f" >/dev/null 2>&1; then
            continue
        fi
        # Schema version gate: warn-and-skip on mismatch.
        local sv
        sv="$(jq -r '.schema_version' "$f" 2>/dev/null)"
        case "$sv" in
            1.0|1.1) ;;
            *)
                log.warn "fragment ${base}: unsupported schema_version '${sv}' (expected '1.0' or '1.1'), skipping"
                continue
                ;;
        esac
        printf '%s\n' "$f" >> "$valid_list"
    done
    shopt -u nullglob

    local pipeline_id="${BRIK_PIPELINE_ID:-${BRIK_RUN_ID:-$(date +%s)-$$}}"
    local platform="${BRIK_PLATFORM:-local}"
    local project="${BRIK_PROJECT_NAME:-unnamed}"
    local finished_at
    finished_at="$(date +"%Y-%m-%dT%H:%M:%S%z")"
    local pipeline_context="snapshot"
    [[ -n "${BRIK_COMMIT_TAG:-}" ]] && pipeline_context="release"

    # Findings policy projection (chantier 20260508 P1.5 / P3.F). The active
    # built-in preset comes from BRIK_QUALITY_FINDINGS_POLICY (export config
    # flow), with pragmatic as the documented default. P3 layers the org
    # policy cache on top: a non-null preset_override in the cache wins over
    # the project preset and flips source to "org-policy". The cache also
    # carries url + loaded_at + expiring_soon entries that surface alongside
    # the active preset for the operator.
    local policy_preset="${BRIK_QUALITY_FINDINGS_POLICY:-pragmatic}"
    local policy_source="brik.yml"
    local policy_org_url=""
    local policy_org_loaded_at=""
    local policy_expiring_soon='[]'

    local _policy_cache="${BRIK_POLICY_CACHE_PATH:-${BRIK_WORKSPACE:-/tmp/brik}/brik-artifacts/.policy.cache.json}"
    if [[ -f "$_policy_cache" ]] && command -v jq >/dev/null 2>&1; then
        local _override
        _override="$(jq -r '.preset_override // empty' "$_policy_cache" 2>/dev/null)"
        if [[ -n "$_override" ]]; then
            policy_preset="$_override"
            policy_source="org-policy"
        fi
        policy_org_url="$(jq -r '.url // empty' "$_policy_cache" 2>/dev/null)"
        policy_org_loaded_at="$(jq -r '.loaded_at // empty' "$_policy_cache" 2>/dev/null)"

        # Compute expiring_soon entries inline. Lookback window defaults to
        # 30 days and respects the BRIK_FINDINGS_EXPIRING_SOON_DAYS override.
        local _days="${BRIK_FINDINGS_EXPIRING_SOON_DAYS:-30}"
        local _now _soon_epoch _soon_date
        _now="$(date -u +%s)"
        _soon_epoch=$((_now + _days * 86400))
        _soon_date="$(date -u -d "@${_soon_epoch}" +%Y-%m-%d 2>/dev/null \
                   || date -u -r "${_soon_epoch}" +%Y-%m-%d 2>/dev/null \
                   || date -u +%Y-%m-%d)"
        # KCOV_EXCL_START -- jq script body is not bash code
        policy_expiring_soon="$(jq -c --arg soon "$_soon_date" '
            [
              (.cve_entries // [])[]
              | select(.expires <= $soon)
              | { type: "cve", id: .id, expires: .expires, reason: (.reason // "") }
            ]
            +
            [
              (.path_entries // [])[]
              | select(.expires <= $soon)
              | { type: "path", glob: .glob, expires: .expires, reason: (.reason // "") }
            ]
        ' "$_policy_cache" 2>/dev/null || printf '[]')"
        # KCOV_EXCL_STOP
    fi

    # Optional pipeline metadata: surface only when the source variable is
    # set, so the aggregate omits absent fields rather than emitting empty
    # strings (matches schema 'optional' semantics).
    local pipeline_url="${BRIK_PIPELINE_URL:-}"
    local dry_run="false"
    [[ "${BRIK_DRY_RUN:-}" == "true" ]] && dry_run="true"
    local commit_sha="${BRIK_COMMIT_SHA:-}"
    local commit_short_sha="${BRIK_COMMIT_SHORT_SHA:-}"
    local commit_ref="${BRIK_COMMIT_REF:-}"
    local commit_branch="${BRIK_COMMIT_BRANCH:-}"
    local commit_tag="${BRIK_COMMIT_TAG:-}"
    local commit_author="${BRIK_COMMIT_AUTHOR:-}"
    local commit_author_email="${BRIK_COMMIT_AUTHOR_EMAIL:-}"
    local commit_timestamp="${BRIK_COMMIT_TIMESTAMP:-}"
    local commit_message_subject="${BRIK_COMMIT_MESSAGE_SUBJECT:-}"
    local commit_repo_url="${BRIK_COMMIT_REPO_URL:-}"
    local triggered_by="${BRIK_TRIGGERED_BY:-}"

    local backend="${log_dir}/aggregate-report.json"
    local tmp
    tmp="$(mktemp "${backend}.XXXXXX")" || {
        rm -f "$valid_list"
        log.error "cannot create temp aggregate file"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    # Build a JSON array of valid fragments. Read paths into an array so
    # word-splitting is explicit (filenames with spaces stay safe) and the
    # static analyser stays quiet.
    local frags_json
    local -a frag_paths=()
    if [[ -s "$valid_list" ]]; then
        local _line
        while IFS= read -r _line; do
            [[ -n "$_line" ]] && frag_paths+=("$_line")
        done < "$valid_list"
    fi
    rm -f "$valid_list"

    if (( ${#frag_paths[@]} > 0 )); then
        frags_json="$(jq -s '.' "${frag_paths[@]}")" || {
            rm -f "$tmp"
            log.error "cannot read valid fragments"
            return "$BRIK_EXIT_IO_FAILURE"
        }
    else
        frags_json='[]'
    fi

    # KCOV_EXCL_START  -- jq script body is not bash code
    jq -n \
        --arg pid "$pipeline_id" \
        --arg platform "$platform" \
        --arg project "$project" \
        --arg context "$pipeline_context" \
        --arg finished_at "$finished_at" \
        --arg pipeline_url "$pipeline_url" \
        --arg commit_sha "$commit_sha" \
        --arg commit_short_sha "$commit_short_sha" \
        --arg commit_ref "$commit_ref" \
        --arg commit_branch "$commit_branch" \
        --arg commit_tag "$commit_tag" \
        --arg commit_author "$commit_author" \
        --arg commit_author_email "$commit_author_email" \
        --arg commit_timestamp "$commit_timestamp" \
        --arg commit_message_subject "$commit_message_subject" \
        --arg commit_repo_url "$commit_repo_url" \
        --arg triggered_by "$triggered_by" \
        --arg policy_preset "$policy_preset" \
        --arg policy_source "$policy_source" \
        --arg policy_org_url "$policy_org_url" \
        --arg policy_org_loaded_at "$policy_org_loaded_at" \
        --argjson policy_expiring_soon "$policy_expiring_soon" \
        --arg dry_run "$dry_run" \
        --argjson frags "$frags_json" \
        '
        ( $frags
          | map(.timestamp // null)
          | map(select(. != null))
          | sort
          | .[0] // $finished_at ) as $started
        | ( $frags | map(.status)
          | { total: length,
              passed:  map(select(. == "success")) | length,
              failed:  map(select(. == "failed"))  | length,
              skipped: map(select(. == "skipped")) | length } ) as $counts
        | ( $frags | map(.business.status // "success")
          | { success_count: map(select(. == "success")) | length,
              warning_count: map(select(. == "warning")) | length,
              error_count:   map(select(. == "error"))   | length } ) as $business_summary
        | ( if ($business_summary.error_count // 0)   > 0 then "error"
            elif ($business_summary.warning_count // 0) > 0 then "warning"
            else "success" end ) as $pipeline_business_status
        | ( if ($counts.failed // 0) > 0 then "failed" else "success" end ) as $pstatus
        | ( { preset: $policy_preset, source: $policy_source }
            + ( if $policy_org_url       != "" then { org_policy_url:       $policy_org_url       } else {} end )
            + ( if $policy_org_loaded_at != "" then { org_policy_loaded_at: $policy_org_loaded_at } else {} end )
            + ( if ($policy_expiring_soon | length) > 0 then { expiring_soon: $policy_expiring_soon } else {} end )
          ) as $policy
        | ( {}
            + ( if $commit_sha             != "" then { sha:             $commit_sha             } else {} end )
            + ( if $commit_short_sha       != "" then { short_sha:       $commit_short_sha       } else {} end )
            + ( if $commit_ref             != "" then { ref:             $commit_ref             } else {} end )
            + ( if $commit_branch          != "" then { branch:          $commit_branch          } else {} end )
            + ( if $commit_tag             != "" then { tag:             $commit_tag             } else {} end )
            + ( if $commit_author          != "" then { author:          $commit_author          } else {} end )
            + ( if $commit_author_email    != "" then { author_email:    $commit_author_email    } else {} end )
            + ( if $commit_timestamp       != "" then { timestamp:       $commit_timestamp       } else {} end )
            + ( if $commit_message_subject != "" then { message_subject: $commit_message_subject } else {} end )
            + ( if $commit_repo_url        != "" then { repo_url:        $commit_repo_url        } else {} end )
          ) as $commit
        | ( {
              id: $pid,
              platform: $platform,
              project: $project,
              context: $context,
              business: { status: $pipeline_business_status },
              started_at: $started,
              finished_at: $finished_at,
              status: $pstatus
            }
            + ( if $pipeline_url != "" then { url:          $pipeline_url } else {} end )
            + ( if ($commit | length) > 0 then { commit:    $commit       } else {} end )
            + ( if $triggered_by != "" then { triggered_by: $triggered_by } else {} end )
            + ( if $dry_run == "true" then { tech: { dry_run: true } } else {} end )
          ) as $pipeline
        | {
            schema_version: "1.1",
            pipeline: $pipeline,
            stages: $frags,
            summary: {
              stages: $counts,
              business: $business_summary,
              policy: $policy
            }
          }
        ' > "$tmp" || {
        rm -f "$tmp"
        log.error "cannot build aggregate JSON"
        return "$BRIK_EXIT_IO_FAILURE"
    }
    # KCOV_EXCL_STOP

    mv "$tmp" "$backend" || {
        rm -f "$tmp"
        log.error "cannot write aggregate report: $backend"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    # Inline per-stage SARIF findings into business.findings.items so the
    # aggregate document is self-sufficient for HTML/MD consumers (no need
    # to fetch the SARIF separately). Non-fatal: a missing or malformed
    # SARIF leaves the stage unchanged.
    _report._enrich_findings_items "$backend" "$fragment_dir" 2>/dev/null || \
        log.warn "could not enrich findings.items (non-fatal)"

    # Render the markdown alongside the JSON. Use the aggregate-shape
    # renderer because the aggregate document differs from the local
    # backend (.pipeline.id vs .pipeline_id, .stages[].stage vs .name,
    # status/rc at fragment level vs nested under tech).
    _report._render_aggregate_md "$backend" > "${log_dir}/aggregate-report.md" 2>/dev/null || \
        log.warn "could not render aggregate-report.md (non-fatal)"

    # Render the self-contained HTML view alongside the JSON + MD. Operators
    # open this in a browser to drill into findings without leaving the
    # archived CI artefact bundle. Non-fatal on failure.
    _report._render_html "$backend" > "${log_dir}/aggregate-report.html" 2>/dev/null || \
        log.warn "could not render aggregate-report.html (non-fatal)"

    log.debug "aggregate report written: $backend"
    return 0
}

# Walk each stage in the aggregate JSON, find SARIF references inside its
# business payload (any nested object shaped {format: "sarif", path: ...}),
# load each SARIF via sarif.extract_items, and inject the union as
# business.findings.items. Stages with zero referenced SARIFs (or where
# every referenced file is missing) are left untouched, preserving the
# additive contract documented on the aggregate schema.
_report._enrich_findings_items() {
    local backend="$1" fragment_dir="$2"
    [[ -f "$backend" ]] || return 0

    local workspace="${BRIK_WORKSPACE:-$(dirname "$fragment_dir")}"
    local stage_count
    stage_count="$(jq -r '.stages | length' "$backend" 2>/dev/null)" || return 0
    [[ "$stage_count" =~ ^[0-9]+$ ]] || return 0
    (( stage_count > 0 )) || return 0

    local i=0
    while (( i < stage_count )); do
        # Collect SARIF paths declared in this stage's business (any nesting).
        local paths_json
        paths_json="$(jq -c --argjson i "$i" '
            .stages[$i].business // {}
            | [.. | objects | select(.format? == "sarif") | .path? // empty]
            | unique
        ' "$backend" 2>/dev/null)" || { i=$((i + 1)); continue; }

        # Skip stage when no SARIF refs.
        local paths_count
        paths_count="$(printf '%s' "$paths_json" | jq -r 'length' 2>/dev/null)"
        [[ "$paths_count" =~ ^[0-9]+$ ]] || paths_count=0
        if (( paths_count == 0 )); then
            i=$((i + 1))
            continue
        fi

        # Walk paths, accumulate items from existing SARIFs only.
        local items_json='[]'
        local p_idx=0
        while (( p_idx < paths_count )); do
            local rel_path
            rel_path="$(printf '%s' "$paths_json" | jq -r --argjson k "$p_idx" '.[$k]')"
            p_idx=$((p_idx + 1))
            [[ -z "$rel_path" || "$rel_path" == "null" ]] && continue
            local abs_path="${workspace}/${rel_path}"
            [[ -f "$abs_path" ]] || continue
            local one
            one="$(sarif.extract_items "$abs_path" 2>/dev/null)" || continue
            [[ -n "$one" ]] || continue
            items_json="$(printf '%s\n%s' "$items_json" "$one" \
                | jq -cs 'add')" || items_json='[]'
        done

        local items_len
        items_len="$(printf '%s' "$items_json" | jq -r 'length' 2>/dev/null)"
        [[ "$items_len" =~ ^[0-9]+$ ]] || items_len=0
        if (( items_len == 0 )); then
            i=$((i + 1))
            continue
        fi

        # Merge items into stage business.findings.items via temp file.
        local tmp
        tmp="$(mktemp "${backend}.enrich.XXXXXX")" || { i=$((i + 1)); continue; }
        if jq -c --argjson i "$i" --argjson items "$items_json" '
              .stages[$i].business.findings = ((.stages[$i].business.findings // {}) + {items: $items})
            ' "$backend" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$backend" || rm -f "$tmp"
        else
            rm -f "$tmp"
        fi

        i=$((i + 1))
    done
    return 0
}

# Render the v1 aggregate JSON as Markdown on stdout. Distinct from
# _report._render_md, which targets the local backend shape (pipeline_id,
# stages[].name, tech.status). The aggregate produced by
# report.aggregate_fragments has pipeline.id, stages[].stage, fragment-level
# status/rc -- selectors here mirror schemas/report/v1/aggregate.schema.json.
_report._render_aggregate_md() {
    local backend="$1"
    # KCOV_EXCL_START  -- jq script body is not bash code
    jq -r '
        # ----- Phase 2 helpers --------------------------------------------
        # Stage execution order: matches the documented fixed flow. Stages
        # not on the list sort to the end (rank 99) but keep their input
        # order via a stable secondary key.
        def stage_rank($name):
          ["init","release","build",
           "lint","sast","scan","test",
           "package","container-scan","deploy","notify"]
          | index($name) // 99;

        def severity_rank($s):
          if   $s == "critical" then 4
          elif $s == "high"     then 3
          elif $s == "medium"   then 2
          elif $s == "low"      then 1
          else 0 end;

        def status_glyph($s):
          if   $s == "success" then "[OK]"
          elif $s == "failed"  then "[FAIL]"
          elif $s == "skipped" then "[SKIP]"
          elif $s == "warning" then "[WARN]"
          else "[?]" end;

        def pad2($n):
          ($n | tostring) | if length == 1 then "0" + . else . end;

        # 80 -> "80ms", 1142 -> "1s", 33339 -> "33s", 141000 -> "2m21s".
        def human_duration_ms($ms):
          if $ms == null or (($ms | type) != "number") then "-"
          elif $ms < 1000 then "\($ms)ms"
          else
            ($ms / 1000 | floor) as $s
            | if $s < 60 then "\($s)s"
              elif $s < 3600 then
                ($s / 60 | floor) as $m | ($s % 60) as $sec
                | "\($m)m\(pad2($sec))s"
              else
                ($s / 3600 | floor) as $h | (($s % 3600) / 60 | floor) as $m
                | "\($h)h\(pad2($m))m"
              end
          end;

        # Best-effort ISO 8601 to epoch seconds. Handles "...Z" and
        # "...+0000" forms; returns null on anything else (renders as "-").
        def parse_iso($s):
          if $s == null then null
          elif ($s | type) != "string" then null
          elif ($s | test("Z$")) then
            (try ($s | fromdateiso8601) catch null)
          elif ($s | test("[+-][0-9]{4}$")) then
            (try ($s | strptime("%Y-%m-%dT%H:%M:%S%z") | mktime) catch null)
          else null end;

        # Total pipeline duration in ms from started_at/finished_at, or null
        # when either timestamp is missing or unparseable.
        def total_duration_ms:
          (parse_iso(.pipeline.started_at)) as $b
          | (parse_iso(.pipeline.finished_at)) as $e
          | if $b == null or $e == null then null
            else (($e - $b) * 1000)
            end;

        # ----- Findings management sections (P6.B, unchanged) -------------
        def by_sev_summary($bs):
          [
            (if ($bs.critical // 0) > 0 then "C:\($bs.critical)" else empty end),
            (if ($bs.high     // 0) > 0 then "H:\($bs.high)"     else empty end),
            (if ($bs.medium   // 0) > 0 then "M:\($bs.medium)"   else empty end),
            (if ($bs.low      // 0) > 0 then "L:\($bs.low)"      else empty end),
            (if ($bs.info     // 0) > 0 then "I:\($bs.info)"     else empty end)
          ] | join(" ");

        def by_source_summary($bs):
          ($bs // {}) | to_entries
          | map(select(.value > 0))
          | map("\(.key)=\(.value)")
          | join(", ");

        def render_active_policy:
          (.summary.policy // null) as $p
          | if $p == null then empty
            else
              "## Active policy",
              "",
              "- **Preset:** \($p.preset // "pragmatic")",
              "- **Source:** \($p.source // "built-in")",
              (if ($p.org_policy_url       // "") != "" then "- **Org policy URL:** `\($p.org_policy_url)`" else empty end),
              (if ($p.org_policy_loaded_at // "") != "" then "- **Loaded at:** \($p.org_policy_loaded_at)" else empty end),
              ""
            end;

        def failing_count(s):
          ((s.business.findings.failing | objects | .total)
           // (s.business.findings.failing | numbers)
           // 0);

        def render_failing:
          (any(.stages[]?; failing_count(.) > 0)) as $has
          | "## Failing findings",
            "",
            (if $has then
              ("| Stage | Failing | Total | Severities |", "|---|---|---|---|"),
              (.stages[]?
               | . as $s
               | select(failing_count($s) > 0)
               | "| \(.stage) | \(failing_count($s)) | \(.business.findings.total // 0) | \(by_sev_summary(.business.findings.by_severity // {})) |")
             else
              "_No failing findings._"
             end),
            "";

        def render_ignored:
          (any(.stages[]?; (.business.findings.ignored.total // 0) > 0)) as $has
          | "## Ignored findings",
            "",
            (if $has then
              ("| Stage | Ignored | Sources | By severity |", "|---|---|---|---|"),
              (.stages[]?
               | select((.business.findings.ignored.total // 0) > 0)
               | "| \(.stage) | \(.business.findings.ignored.total // 0) | \(by_source_summary(.business.findings.ignored.by_source // {})) | \(by_sev_summary(.business.findings.ignored.by_severity // {})) |")
             else
              "_No ignored findings._"
             end),
            "";

        def render_expiring:
          (.summary.policy.expiring_soon // []) as $exp
          | if ($exp | length) == 0 then empty
            else
              "## Expiring soon",
              "",
              "| Entry | Expires | Days remaining |",
              "|---|---|---|",
              ($exp[] | "| \(.id // "-") | \(.expires // "-") | \(.days_remaining // "-") |"),
              ""
            end;

        # ----- Phase 2: Top findings (most severe) ------------------------
        # Aggregates business.findings.items[] across all stages, sorts by
        # severity desc + score desc, caps at 20 rows. Auto-skips when no
        # stage carries items (back-compat for builds before Phase 1).
        def render_top_findings:
          [.stages[]? | (.business.findings.items // [])[]] as $all
          | if ($all | length) == 0 then empty
            else
              "## Top findings (most severe)",
              "",
              "| Severity | ID | Package | Fix | Tool |",
              "|---|---|---|---|---|",
              ($all
               | sort_by([- severity_rank(.severity), - ((.score // 0))])
               | .[0:20]
               | .[]
               | (
                   "| " + (.severity // "info")
                   + " | " + (if (.help_uri // "") != "" then "[\(.id)](\(.help_uri))" else (.id // "-") end)
                   + " | " + (if .package != null then "\(.package.name) \(.package.version)" else "-" end)
                   + " | " + (if (.fix.available // false) then "-> " + (.fix.versions | join(", ")) else "-" end)
                   + " | " + (.tool.name // "-")
                   + " |"
                 )),
              ""
            end;

        # ----- Phase 2: stages table (ordered, glyphed, human, linked) ----
        def render_stages_table:
          "## Stages",
          "",
          "| Stage | Status | Duration | Job |",
          "|---|---|---|---|",
          (.stages // []
           | sort_by([stage_rank(.stage), .stage])
           | .[]
           | (
               "| " + (.stage // "-")
               + " | " + status_glyph(.status // "?") + " " + (.status // "-")
                       + (if ((.tech.dry_run // false) | tostring) == "true" then " _(dry-run)_" else "" end)
               + " | " + human_duration_ms(.duration_ms)
               + " | " + (if (.runner.job_url // "") != "" then "[job](\(.runner.job_url))" else "-" end)
               + " |"
             )),
          "";

        # ----- Phase 2: business as flat dotted scalars -------------------
        # Per stage: walk paths to scalars, skip array-index paths, skip the
        # findings sub-tree (covered by Failing/Ignored/Top sections above),
        # render "- **dotted.key:** value". Skips stages with empty business.
        def render_business_block($b):
          ($b // {}) as $bb
          | [
              $bb | paths(scalars) as $p
              | select(($p[0] // "") != "findings")
              | select(all($p[]; type == "string"))
              | { key: ($p | join(".")), value: ($bb | getpath($p)) }
            ]
          | map(select(.value != null and (.value | tostring) != ""))
          | sort_by(.key);

        def render_business_section:
          (
            .stages // []
            | sort_by([stage_rank(.stage), .stage])
            | map(select(.business != null))
            | map(. + { _lines: render_business_block(.business) })
            | map(select((._lines | length) > 0))
          ) as $stages_with_business
          | if ($stages_with_business | length) == 0 then empty
            else
              ("## Business", "",
               ($stages_with_business[]
                | ("### \(.stage)\(if ((.tech.dry_run // false) | tostring) == "true" then " _(dry-run)_" else "" end)",
                   "",
                   (._lines[] | "- **\(.key):** \(.value)"),
                   "")))
            end;

        # ----- Top-level render -------------------------------------------
        (total_duration_ms) as $totms
        | "# Pipeline Report",
          "",
          (if (.pipeline.tech.dry_run // false) == true
           then ("> **DRY-RUN** — BRIK_DRY_RUN=true: destructive actions were skipped (no tag pushed, no registry publish, no real deploy).",
                 "")
           else empty
           end),
          (if (.pipeline.url // "") != ""
           then "- **Pipeline ID:** [\(.pipeline.id // "-")](\(.pipeline.url))"
           else "- **Pipeline ID:** \(.pipeline.id // "-")"
           end),
          "- **Project:** \(.pipeline.project // "-")",
          "- **Platform:** \(.pipeline.platform // "-")",
          "- **Status:** \(status_glyph(.pipeline.status // "?")) \(.pipeline.status // "-")",
          "- **Started:** \(.pipeline.started_at // "-")",
          "- **Finished:** \(.pipeline.finished_at // "-")",
          "- **Total duration:** \(human_duration_ms($totms))",
          "",
          render_stages_table,
          "## Summary",
          "",
          "- **Total stages:** \(.summary.stages.total // 0)",
          "- **Passed:** \(.summary.stages.passed // 0)",
          "- **Failed:** \(.summary.stages.failed // 0)",
          "- **Skipped:** \(.summary.stages.skipped // 0)",
          "",
          "## Business outcome",
          "",
          "- **Status:** \(status_glyph(.pipeline.business.status // "?")) \(.pipeline.business.status // "-")",
          "- **Counts:** success=\(.summary.business.success_count // 0), warning=\(.summary.business.warning_count // 0), error=\(.summary.business.error_count // 0)",
          "",
          render_active_policy,
          render_failing,
          render_ignored,
          render_expiring,
          render_top_findings,
          render_business_section
    ' "$backend"
    # KCOV_EXCL_STOP
}

# Render the pipeline report. Default writes both aggregate-report.md and
# aggregate-report.json into $BRIK_LOG_DIR. --format md|json restricts output.
# --output <path> redirects the chosen format to a custom path.
report.render() {
    _report._require_jq || return "$?"

    local format="both"
    local output=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format)
                case "${2:-}" in
                    md|json|html|both) format="$2" ;;
                    *)
                        error.raise "$BRIK_EXIT_INVALID_INPUT" \
                            "report.render: unknown --format '${2:-}' (expected md|json|html|both)"
                        return "$?"
                        ;;
                esac
                shift 2
                ;;
            --output)
                output="${2:-}"
                if [[ -z "$output" ]]; then
                    error.raise "$BRIK_EXIT_INVALID_INPUT" \
                        "report.render: --output requires a path"
                    return "$?"
                fi
                shift 2
                ;;
            *)
                error.raise "$BRIK_EXIT_INVALID_INPUT" \
                    "report.render: unknown argument '$1'"
                return "$?"
                ;;
        esac
    done

    local backend
    backend="$(_report._backend_path)"
    [[ -f "$backend" ]] || {
        log.error "report not initialized: $backend (call report.init first)"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    # Stamp finished_at on the backend JSON.
    local finished_at
    finished_at="$(date +"%Y-%m-%dT%H:%M:%S%z")"
    local tmp
    tmp="$(mktemp "${backend}.XXXXXX")" || return "$BRIK_EXIT_IO_FAILURE"
    jq --arg finished "$finished_at" '.finished_at = $finished' "$backend" > "$tmp" || {
        rm -f "$tmp"
        log.error "cannot stamp finished_at on report"
        return "$BRIK_EXIT_IO_FAILURE"
    }
    mv "$tmp" "$backend" || {
        rm -f "$tmp"
        return "$BRIK_EXIT_IO_FAILURE"
    }

    local log_dir
    log_dir="$(_brik.log_dir._resolve)"

    case "$format" in
        md)
            local md_out="${output:-${log_dir}/aggregate-report.md}"
            _report._render_md "$backend" > "$md_out" || {
                log.error "cannot write md report: $md_out"
                return "$BRIK_EXIT_IO_FAILURE"
            }
            ;;
        json)
            local json_out="${output:-${log_dir}/aggregate-report.json}"
            if [[ "$json_out" != "$backend" ]]; then
                cp "$backend" "$json_out" || {
                    log.error "cannot copy json report to: $json_out"
                    return "$BRIK_EXIT_IO_FAILURE"
                }
            fi
            ;;
        html)
            local html_out="${output:-${log_dir}/aggregate-report.html}"
            _report._render_html "$backend" > "$html_out" || {
                log.error "cannot write html report: $html_out"
                return "$BRIK_EXIT_IO_FAILURE"
            }
            ;;
        both)
            _report._render_md "$backend" > "${log_dir}/aggregate-report.md" || {
                log.error "cannot write md report"
                return "$BRIK_EXIT_IO_FAILURE"
            }
            _report._render_html "$backend" > "${log_dir}/aggregate-report.html" || \
                log.warn "could not render aggregate-report.html (non-fatal)"
            # JSON backend already lives at ${log_dir}/aggregate-report.json.
            ;;
    esac
    return 0
}

# Render the backend JSON as Markdown on stdout.
_report._render_md() {
    local backend="$1"
    # KCOV_EXCL_START  -- jq script body is not bash code
    jq -r '
        "# Pipeline Report",
        "",
        (if (.pipeline.tech.dry_run // false) == true
         then ("> **DRY-RUN** — BRIK_DRY_RUN=true: destructive actions were skipped (no tag pushed, no registry publish, no real deploy).",
               "")
         else empty
         end),
        "- **Pipeline ID:** \(.pipeline_id)",
        "- **Started:** \(.started_at)",
        "- **Finished:** \(.finished_at // "-")",
        "",
        "## Stages",
        "",
        "| Stage | Status | Duration (ms) | Exit code |",
        "|---|---|---|---|",
        (.stages[] | "| \(.name) | \(.tech.status // "-")\(if ((.tech.dry_run // false) | tostring) == "true" then " _(dry-run)_" else "" end) | \(.tech.duration_ms // "-") | \(.tech.exit_code // "-") |"),
        "",
        "## Business",
        "",
        (
          .stages[]
          | select(.business != null and (.business | length) > 0)
          | ("### \(.name)\(if ((.tech.dry_run // false) | tostring) == "true" then " _(dry-run)_" else "" end)",
             "",
             (.business | to_entries[] | "- **\(.key):** \(.value)"),
             "")
        )
    ' "$backend"
    # KCOV_EXCL_STOP
}

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

# Resolve the backend JSON path from BRIK_LOG_DIR.
_report._backend_path() {
    local log_dir="${BRIK_LOG_DIR:-${BRIK_DEFAULT_LOG_DIR:-/tmp/brik/logs}}"
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

    local log_dir="${BRIK_LOG_DIR:-${BRIK_DEFAULT_LOG_DIR:-/tmp/brik/logs}}"
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
        tech|business) ;;
        *)
            error.raise "$BRIK_EXIT_INVALID_INPUT" \
                "report.record: invalid category '$category' (expected tech|business)"
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
        tech|business) ;;
        *)
            error.raise "$BRIK_EXIT_INVALID_INPUT" \
                "report.record_object: invalid category '$category' (expected tech|business)"
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
              else .stages += [{ name: s, tech: {}, business: {} }]
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
              else .stages += [{ name: s, tech: {}, business: {} }]
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

    local fragment_dir="${BRIK_WORKSPACE:-${BRIK_LOG_DIR:-${BRIK_DEFAULT_LOG_DIR:-/tmp/brik/logs}}}/brik-artifacts"
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
        | ( $tech.status    // "skipped" ) as $status
        | ( ($tech.exit_code // 0) | tonumber? // 0 ) as $rc
        | ( $tech.duration_ms ) as $duration_raw
        | ( {
            schema_version: "1.0",
            stage: $stage_name,
            timestamp: $timestamp,
            rc: $rc,
            status: $status,
            runner: ( { platform: $platform }
                      + ( if $image   != "" then { image:   $image   } else {} end )
                      + ( if $job_url != "" then { job_url: $job_url } else {} end ) ),
            tech: $tech,
            business: $business
          }
          + ( if $duration_raw == null or $duration_raw == "" then {}
              else { duration_ms: ($duration_raw | tonumber? // 0) } end ) )
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
#   - Files with schema_version != "1.0" are warn-and-skipped (decision 7:
#     forward-compat with future v2 fragments).
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

    local log_dir="${BRIK_LOG_DIR:-${BRIK_DEFAULT_LOG_DIR:-/tmp/brik/logs}}"
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
        if [[ "$sv" != "1.0" ]]; then
            log.warn "fragment ${base}: unsupported schema_version '${sv}' (expected '1.0'), skipping"
            continue
        fi
        printf '%s\n' "$f" >> "$valid_list"
    done
    shopt -u nullglob

    local pipeline_id="${BRIK_PIPELINE_ID:-${BRIK_RUN_ID:-$(date +%s)-$$}}"
    local platform="${BRIK_PLATFORM:-local}"
    local project="${BRIK_PROJECT_NAME:-unnamed}"
    local finished_at
    finished_at="$(date +"%Y-%m-%dT%H:%M:%S%z")"

    # Optional pipeline metadata: surface only when the source variable is
    # set, so the aggregate omits absent fields rather than emitting empty
    # strings (matches schema 'optional' semantics).
    local pipeline_url="${BRIK_PIPELINE_URL:-}"
    local commit_sha="${BRIK_COMMIT_SHA:-}"
    local commit_short_sha="${BRIK_COMMIT_SHORT_SHA:-}"
    local commit_ref="${BRIK_COMMIT_REF:-}"
    local commit_branch="${BRIK_COMMIT_BRANCH:-}"
    local commit_tag="${BRIK_COMMIT_TAG:-}"
    local commit_author="${BRIK_COMMIT_AUTHOR:-}"
    local commit_author_email="${BRIK_COMMIT_AUTHOR_EMAIL:-}"
    local commit_timestamp="${BRIK_COMMIT_TIMESTAMP:-}"
    local commit_message_subject="${BRIK_COMMIT_MESSAGE_SUBJECT:-}"
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
        --arg triggered_by "$triggered_by" \
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
        | ( $frags
          | map(select((.tech.warning // false) == true)
                | { stage: .stage, reason: (.tech.warning_reason // "") }) ) as $warnings
        | ( if ($counts.failed // 0) > 0 then "failed" else "success" end ) as $pstatus
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
          ) as $commit
        | ( {
              id: $pid,
              platform: $platform,
              project: $project,
              started_at: $started,
              finished_at: $finished_at,
              status: $pstatus
            }
            + ( if $pipeline_url != "" then { url:          $pipeline_url } else {} end )
            + ( if ($commit | length) > 0 then { commit:    $commit       } else {} end )
            + ( if $triggered_by != "" then { triggered_by: $triggered_by } else {} end )
          ) as $pipeline
        | {
            schema_version: "1.0",
            pipeline: $pipeline,
            stages: $frags,
            summary: {
              stages: $counts,
              warnings: $warnings
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

    # Render the markdown alongside the JSON. Use the aggregate-shape
    # renderer because the aggregate document differs from the local
    # backend (.pipeline.id vs .pipeline_id, .stages[].stage vs .name,
    # status/rc at fragment level vs nested under tech).
    _report._render_aggregate_md "$backend" > "${log_dir}/aggregate-report.md" 2>/dev/null || \
        log.warn "could not render aggregate-report.md (non-fatal)"

    log.debug "aggregate report written: $backend"
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
        "# Pipeline Report",
        "",
        "- **Pipeline ID:** \(.pipeline.id // "-")",
        "- **Project:** \(.pipeline.project // "-")",
        "- **Platform:** \(.pipeline.platform // "-")",
        "- **Status:** \(.pipeline.status // "-")",
        "- **Started:** \(.pipeline.started_at // "-")",
        "- **Finished:** \(.pipeline.finished_at // "-")",
        "",
        "## Stages",
        "",
        "| Stage | Status | Duration (ms) | Exit code |",
        "|---|---|---|---|",
        (.stages[] | "| \(.stage // "-") | \(.status // "-") | \(.duration_ms // "-") | \(.rc // "-") |"),
        "",
        "## Summary",
        "",
        "- **Total stages:** \(.summary.stages.total // 0)",
        "- **Passed:** \(.summary.stages.passed // 0)",
        "- **Failed:** \(.summary.stages.failed // 0)",
        "- **Skipped:** \(.summary.stages.skipped // 0)",
        "",
        "## Business",
        "",
        (
          .stages[]
          | select(.business != null and (.business | length) > 0)
          | ("### \(.stage)",
             "",
             (.business | to_entries[] | "- **\(.key):** \(.value)"),
             "")
        )
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
                    md|json|both) format="$2" ;;
                    *)
                        error.raise "$BRIK_EXIT_INVALID_INPUT" \
                            "report.render: unknown --format '${2:-}' (expected md|json|both)"
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

    local log_dir="${BRIK_LOG_DIR:-${BRIK_DEFAULT_LOG_DIR:-/tmp/brik/logs}}"

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
        both)
            _report._render_md "$backend" > "${log_dir}/aggregate-report.md" || {
                log.error "cannot write md report"
                return "$BRIK_EXIT_IO_FAILURE"
            }
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
        "- **Pipeline ID:** \(.pipeline_id)",
        "- **Started:** \(.started_at)",
        "- **Finished:** \(.finished_at // "-")",
        "",
        "## Stages",
        "",
        "| Stage | Status | Duration (ms) | Exit code |",
        "|---|---|---|---|",
        (.stages[] | "| \(.name) | \(.tech.status // "-") | \(.tech.duration_ms // "-") | \(.tech.exit_code // "-") |"),
        "",
        "## Business",
        "",
        (
          .stages[]
          | select(.business != null and (.business | length) > 0)
          | ("### \(.name)",
             "",
             (.business | to_entries[] | "- **\(.key):** \(.value)"),
             "")
        )
    ' "$backend"
    # KCOV_EXCL_STOP
}

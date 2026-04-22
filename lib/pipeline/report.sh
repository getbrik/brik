#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module report
# @description Persistent pipeline-level report aggregator.
#
# Records tech and business metrics per stage to a JSON backing store
# ($BRIK_LOG_DIR/pipeline-report.json) and renders Markdown + JSON outputs
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
    printf '%s/pipeline-report.json' "$log_dir"
}

# Require jq on PATH. Returns BRIK_EXIT_MISSING_DEP if absent.
_report._require_jq() {
    command -v jq >/dev/null 2>&1 || {
        log.error "jq is required for report.*"
        return "$BRIK_EXIT_MISSING_DEP"
    }
}

# Create (or overwrite) the pipeline-report.json skeleton.
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
        ' "$backend" > "$tmp" || {
        rm -f "$tmp"
        log.error "cannot append to report: $backend"
        return "$BRIK_EXIT_IO_FAILURE"
    }
    # KCOV_EXCL_STOP

    mv "$tmp" "$backend" || {
        rm -f "$tmp"
        return "$BRIK_EXIT_IO_FAILURE"
    }
    return 0
}

# Render the pipeline report. Default writes both pipeline-report.md and
# pipeline-report.json into $BRIK_LOG_DIR. --format md|json restricts output.
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
            local md_out="${output:-${log_dir}/pipeline-report.md}"
            _report._render_md "$backend" > "$md_out" || {
                log.error "cannot write md report: $md_out"
                return "$BRIK_EXIT_IO_FAILURE"
            }
            ;;
        json)
            local json_out="${output:-${log_dir}/pipeline-report.json}"
            if [[ "$json_out" != "$backend" ]]; then
                cp "$backend" "$json_out" || {
                    log.error "cannot copy json report to: $json_out"
                    return "$BRIK_EXIT_IO_FAILURE"
                }
            fi
            ;;
        both)
            _report._render_md "$backend" > "${log_dir}/pipeline-report.md" || {
                log.error "cannot write md report"
                return "$BRIK_EXIT_IO_FAILURE"
            }
            # JSON backend already lives at ${log_dir}/pipeline-report.json.
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

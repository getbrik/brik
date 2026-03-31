#!/usr/bin/env bash
# @module summary
# @description Summary generation for the Brik runtime.
#
# Produces a JSON summary for each stage execution.
# Falls back to plain text if jq is unavailable.

# Guard against double-sourcing
[[ -n "${_BRIK_SUMMARY_LOADED:-}" ]] && return 0
_BRIK_SUMMARY_LOADED=1

# Source dependencies
# shellcheck source=logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/logging.sh"
# shellcheck source=context.sh
[[ -z "${_BRIK_CONTEXT_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/context.sh"

# Build a summary JSON for a stage execution.
# Writes the summary to ${BRIK_LOG_DIR}/<stage_name>-summary.json.
# Returns 0 on success. Errors in summary generation do NOT propagate.
summary.build() {
    local stage_name="$1"
    local context_file="$2"
    local log_file="$3"
    local exit_code="$4"

    local status="SUCCESS"
    [[ "$exit_code" -ne 0 ]] && status="FAILED"

    local started_at=""
    started_at="$(context.get "$context_file" "BRIK_STARTED_AT" 2>/dev/null)" || started_at=""
    local finished_at
    finished_at="$(date +"%Y-%m-%dT%H:%M:%S%z")"

    # Calculate duration in seconds (millisecond precision not available in pure bash)
    local duration_ms=0
    if [[ -n "$started_at" ]]; then
        local start_epoch end_epoch
        start_epoch="$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$started_at" "+%s" 2>/dev/null)" || start_epoch=0
        end_epoch="$(date "+%s")"
        if [[ "$start_epoch" -gt 0 ]]; then
            duration_ms=$(( (end_epoch - start_epoch) * 1000 ))
        fi
    fi

    # Collect errors from log file
    local errors_json="[]"
    if [[ -f "$log_file" ]] && command -v jq >/dev/null 2>&1; then
        local error_lines
        error_lines="$(grep '\[ERROR\]' "$log_file" 2>/dev/null | sed 's/.*\[ERROR\] \[.*\] //' || true)"
        if [[ -n "$error_lines" ]]; then
            errors_json="$(printf '%s\n' "$error_lines" | jq -R -s 'split("\n") | map(select(length > 0))')"
        fi
    fi

    local log_dir="${BRIK_LOG_DIR:-/tmp/brik/logs}"
    local summary_path="${log_dir}/${stage_name}-summary.json"

    if command -v jq >/dev/null 2>&1; then
        jq -n \
            --arg stage_name "$stage_name" \
            --arg status "$status" \
            --argjson exit_code "$exit_code" \
            --arg started_at "$started_at" \
            --arg finished_at "$finished_at" \
            --argjson duration_ms "$duration_ms" \
            --arg log_file "${log_file:-}" \
            --argjson errors "$errors_json" \
            '{
                stage_name: $stage_name,
                status: $status,
                exit_code: $exit_code,
                started_at: $started_at,
                finished_at: $finished_at,
                duration_ms: $duration_ms,
                log_file: $log_file,
                artifacts: [],
                warnings: [],
                errors: $errors
            }' > "$summary_path" 2>/dev/null
    else
        # Fallback: simple text-based summary
        log.warn "jq not available, writing text summary"
        {
            printf 'stage_name=%s\n' "$stage_name"
            printf 'status=%s\n' "$status"
            printf 'exit_code=%s\n' "$exit_code"
            printf 'started_at=%s\n' "$started_at"
            printf 'finished_at=%s\n' "$finished_at"
            printf 'duration_ms=%s\n' "$duration_ms"
            printf 'log_file=%s\n' "${log_file:-}"
        } > "$summary_path" 2>/dev/null
    fi

    log.debug "summary written to: $summary_path"
    return 0
}

# Write JSON data to a file.
summary.write_json() {
    local data="$1"
    local output_path="$2"
    printf '%s\n' "$data" > "$output_path" || {
        log.error "cannot write summary to: $output_path"
        return 6
    }
    return 0
}

# Print a human-readable summary to stderr.
summary.print_human() {
    local summary_path="$1"
    if [[ ! -f "$summary_path" ]]; then
        log.warn "summary file not found: $summary_path"
        return 0
    fi

    if command -v jq >/dev/null 2>&1; then
        local stage status exit_code duration
        stage="$(jq -r '.stage_name' "$summary_path" 2>/dev/null)"
        status="$(jq -r '.status' "$summary_path" 2>/dev/null)"
        exit_code="$(jq -r '.exit_code' "$summary_path" 2>/dev/null)"
        duration="$(jq -r '.duration_ms' "$summary_path" 2>/dev/null)"
        printf '\n--- Stage Summary ---\n' >&2
        printf 'Stage:     %s\n' "$stage" >&2
        printf 'Status:    %s\n' "$status" >&2
        printf 'Exit code: %s\n' "$exit_code" >&2
        printf 'Duration:  %s ms\n' "$duration" >&2
        printf '---------------------\n' >&2
    else
        cat "$summary_path" >&2
    fi
    return 0
}

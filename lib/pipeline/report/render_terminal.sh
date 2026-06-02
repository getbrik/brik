#!/usr/bin/env bash
# @module report.render_terminal
# @requires jq
# @description Terminal recap renderers for the pipeline report.
#
# Split out of lib/pipeline/report.sh. render_terminal is the post-pipeline
# CLI summary surfaced by the local wrapper; render_aggregate_terminal is the
# full ASCII recap (header, stages table, summary, business, findings) printed
# from the notify stage. Both read the aggregate JSON, never write data files.
# Loaded by the report.sh facade.
#
# Depends on facade-provided globals (resolved at runtime):
#   _BRIK_JQ_DURATION_DEFS   (jq duration library, defined in report.sh)
# The render.* lib is loaded lazily via `brik.use transverse.render`.

[[ -n "${_BRIK_REPORT_RENDER_TERMINAL_LOADED:-}" ]] && return 0
_BRIK_REPORT_RENDER_TERMINAL_LOADED=1

# shellcheck source=../logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../logging.sh"
# shellcheck source=../error.sh
[[ -z "${_BRIK_ERROR_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../error.sh"

# Render a terminal-friendly recap of the aggregate report on stdout.
#
# Counterpart to report.render (which produces md/json/html artifacts):
# this is the post-pipeline CLI summary surfaced by the local wrapper at
# the end of `brik run pipeline`. ANSI colors auto-detect from $TERM and
# stdout isatty; output stays plain when piped or running in a dumb term.
#
# Status labels per stage:
#   PASS   tech.status == success
#   FAIL   tech.status == failed
#   SKIP   tech.status == skipped (or missing)
#
# Note on related output: lib/stages/notify.sh::_notify._emit_recap_table
# also renders a recap, but from inside the notify stage during pipeline
# execution and with a different format (format.table, business metrics
# per stage). The two are intentionally distinct: live-log convenience vs
# end-of-CLI summary. They share the aggregate JSON, not the formatting.
#
# Usage: report.render_terminal [<report_path>]
# Default path: $BRIK_LOG_DIR/aggregate-report.json
# Exit codes:
#   0                       success, or jq missing (best-effort skip)
#   BRIK_EXIT_IO_FAILURE    report file does not exist
#   BRIK_EXIT_FAILURE       report cannot be parsed
report.render_terminal() {
    local report_path="${1:-$(_brik.log_dir._resolve)/aggregate-report.json}"

    if [[ ! -f "$report_path" ]]; then
        log.warn "pipeline report not found: $report_path"
        return "$BRIK_EXIT_IO_FAILURE"
    fi
    if ! command -v jq >/dev/null 2>&1; then
        log.warn "jq not available, skipping summary"
        return 0
    fi

    # Centralized color handling via render.color (auto-detects TTY,
    # CI markers, NO_COLOR; cached at source time so $() inherits the
    # right decision). Each helper returns empty when colors are
    # disabled.
    brik.use transverse.render 2>/dev/null || true
    local green red gray bold reset
    green="$(render.color green)"
    red="$(render.color red)"
    gray="$(render.color gray)"
    bold="$(render.color bold)"
    reset="$(render.color reset)"

    # Extract per-stage rows as TAB-separated: name<TAB>status<TAB>duration_ms
    local rows
    rows="$(jq -r '.stages[] | [.stage, (.tech.status // "skipped"), (.tech.duration_ms // "0")] | @tsv' "$report_path")" || {
        log.warn "failed to parse pipeline report: $report_path"
        return "$BRIK_EXIT_FAILURE"
    }

    local passed=0 failed=0 skipped=0 ran=0 total_duration_ms=0
    local name status_raw duration_ms label color duration_str

    echo ""
    echo "${bold}--- Pipeline Summary ---${reset}"

    while IFS=$'\t' read -r name status_raw duration_ms; do
        [[ -z "$name" ]] && continue
        case "$status_raw" in
            success)
                label="PASS"; color="$green"
                (( ++passed )); (( ++ran ))
                duration_str="${duration_ms}ms"
                total_duration_ms=$(( total_duration_ms + duration_ms ))
                ;;
            failed)
                label="FAIL"; color="$red"
                (( ++failed )); (( ++ran ))
                duration_str="${duration_ms}ms"
                total_duration_ms=$(( total_duration_ms + duration_ms ))
                ;;
            *)
                label="SKIP"; color="$gray"
                (( ++skipped ))
                duration_str=""
                ;;
        esac
        printf "  %-14s %s%-4s%s" "$name" "$color" "$label" "$reset"
        [[ -n "$duration_str" ]] && printf "  %s" "$duration_str"
        echo ""
    done <<< "$rows"

    echo "${bold}------------------------${reset}"

    local result_color="$green"
    local result_label="PASS"
    if [[ $failed -gt 0 ]]; then
        result_color="$red"
        result_label="FAIL"
    fi

    echo "${bold}Result: ${result_color}${result_label}${reset} (${passed}/${ran} passed, ${skipped} skipped)"
    echo "${bold}Duration: $(( total_duration_ms / 1000 ))s${reset}"
    echo ""
}

# Render the full aggregate report on stdout using the render lib (ASCII
# box-drawing, no markdown). Designed as the replacement for the
# glow-based stdout rendering previously used by the notify stage:
# preserves the operator-relevant sections (header, stages table, summary
# counts, business outcome, findings counts, active policy) while keeping
# the markdown archive (aggregate-report.md) untouched for HTML report and
# downstream tooling.
#
# Per-stage business sections (the long "## Business" block with one
# subsection per stage) are NOT rendered here: they're available in the
# markdown archive and in aggregate-report.json. Keeping them out of the
# CI log avoids drowning the operator in detail.
#
# Usage: report.render_aggregate_terminal [<aggregate_json_path>]
# Default path: $BRIK_LOG_DIR/aggregate-report.json
# Exit codes:
#   0                       success, or jq missing (best-effort skip)
#   BRIK_EXIT_IO_FAILURE    report file does not exist
#   BRIK_EXIT_FAILURE       report cannot be parsed
report.render_aggregate_terminal() {
    local report_path="${1:-$(_brik.log_dir._resolve)/aggregate-report.json}"

    if [[ ! -f "$report_path" ]]; then
        log.warn "aggregate report not found: $report_path"
        return "$BRIK_EXIT_IO_FAILURE"
    fi
    if ! command -v jq >/dev/null 2>&1; then
        log.warn "jq not available, skipping aggregate render"
        return 0
    fi
    brik.use transverse.render 2>/dev/null || true

    # Header
    local pipeline_id project platform biz_status started finished duration_ms duration_str
    pipeline_id="$(jq -r '.pipeline.id // .pipeline_id // "-"' "$report_path" 2>/dev/null)"
    project="$(jq -r '.pipeline.project // .project // "-"' "$report_path" 2>/dev/null)"
    platform="$(jq -r '.pipeline.platform // "-"' "$report_path" 2>/dev/null)"
    biz_status="$(jq -r '.pipeline.business.status // "unknown"' "$report_path" 2>/dev/null)"
    started="$(jq -r '.pipeline.started_at // "-"' "$report_path" 2>/dev/null)"
    finished="$(jq -r '.pipeline.finished_at // "-"' "$report_path" 2>/dev/null)"

    # Total pipeline wallclock duration in ms (finished_at - started_at).
    # Returns 0 when either timestamp is missing or unparseable; the
    # formatter below maps that to "-".
    duration_ms="$(jq -r '
        def parse_iso($s):
            if $s == null then null
            elif ($s | type) != "string" then null
            elif ($s | test("Z$")) then (try ($s | fromdateiso8601) catch null)
            elif ($s | test("[+-][0-9]{4}$"))
                then (try ($s | strptime("%Y-%m-%dT%H:%M:%S%z") | mktime) catch null)
            else null end;
        (parse_iso(.pipeline.started_at)) as $b
        | (parse_iso(.pipeline.finished_at)) as $e
        | if $b == null or $e == null then 0
          else (($e - $b) * 1000) | floor
          end
    ' "$report_path" 2>/dev/null || printf '0')"
    [[ "$duration_ms" =~ ^[0-9]+$ ]] || duration_ms=0
    # 0 means "unknown" (missing/unparseable timestamps) -> "-". Otherwise
    # format through the canonical human_duration_ms so this KV matches the
    # Stages table and the Markdown report exactly (one source of truth).
    if (( duration_ms == 0 )); then
        duration_str="-"
    else
        duration_str="$(jq -rn --argjson ms "$duration_ms" "${_BRIK_JQ_DURATION_DEFS}"' human_duration_ms($ms)')"
    fi

    render.blank
    render.section "Pipeline Report"
    render.kv "Pipeline ID" "$pipeline_id" --key-width 14
    render.kv "Project"     "$project"     --key-width 14
    render.kv "Platform"    "$platform"    --key-width 14
    render.kv "Status"      "${biz_status^^}" --key-width 14
    render.kv "Started"     "$started"     --key-width 14
    render.kv "Finished"    "$finished"    --key-width 14
    render.kv "Duration"    "$duration_str" --key-width 14
    render.blank

    # Stages table -- Stage | Status | Business | Duration
    # Status + Business cells carry plain uppercase keywords so
    # render.table can compute clean column widths without emoji
    # drift, and so --color-by Business can drive per-row coloring
    # via render.color_for_status. Business follows tech.status:
    # when a stage is skipped (no execution), the business outcome
    # is N/A rather than "success", which would imply work was done.
    #
    # The stage list is driven by plan.json's canonical execution
    # order when available (next to the aggregate report). This
    # preserves the Init -> Release -> Build -> ... -> Notify flow
    # in the table, and backfills any stage missing from fragments
    # (e.g. adapters like Jenkins that don't emit skip-fragments)
    # as SKIPPED / N/A so the view is consistent across adapters.
    # Fallback (no plan.json): render whatever stages the aggregate
    # already carries, in storage order.
    local plan_path plan_json
    plan_path="$(dirname "$report_path")/plan.json"
    if [[ -f "$plan_path" ]] && jq -e 'type == "object"' "$plan_path" >/dev/null 2>&1; then
        plan_json="$(cat "$plan_path")"
    else
        plan_json='null'
    fi

    # The stage currently rendering this view (typically notify itself
    # when it aggregates). We classify a "missing fragment for the
    # current stage" as RUNNING rather than SKIPPED so notify's own row
    # reflects reality: at render time, notify hasn't yet written its
    # fragment because it is the one printing this table.
    local current_stage="${BRIK_STAGE_NAME:-}"

    render.section "Stages"
    {
        printf 'Stage\tStatus\tBusiness\tDuration\n'
        jq -r --argjson plan "$plan_json" \
              --arg current "$current_stage" \
              --arg pipeline_biz "$biz_status" "${_BRIK_JQ_DURATION_DEFS}"'
            # human_duration_ms comes from ${_BRIK_JQ_DURATION_DEFS}
            # (top of report.sh), prepended to this program above. It
            # supersedes the former fmt_ms, which capped output at seconds
            # (a 2m stage rendered "120s" here while the Duration KV above
            # rendered "2m00s") and accepts the same string/null inputs.
            def tech_keyword($s):
                if   $s == "success" then "SUCCESS"
                elif $s == "failed"  then "FAILED"
                elif $s == "skipped" then "SKIPPED"
                elif $s == "warning" then "WARNING"
                elif $s == "running" then "RUNNING"
                elif $s == "not_run" then "NOT-RUN"
                else ($s | tostring | ascii_upcase) end;
            # When a stage is the in-flight stage (typically notify
            # aggregating its own pipeline), surface the pipeline-level
            # business outcome in the Business cell so the row already
            # reflects the verdict the operator is reading rather than
            # a placeholder. That also drives the row color through
            # --color-by Business: green for SUCCESS pipelines, yellow
            # for WARNING, red for ERROR.
            def biz_keyword($b; $tech):
                if   $tech == "skipped" or $tech == "not_run" then "N/A"
                elif $tech == "running" then ($pipeline_biz | ascii_upcase)
                elif $b   == "success"  then "SUCCESS"
                elif $b   == "warning"  then "WARNING"
                elif $b   == "error"    then "ERROR"
                elif $b   == null       then "-"
                else ($b | tostring | ascii_upcase) end;

            (.stages | map({ key: (.stage // .name // .id // "?"), value: . }) | from_entries) as $by_id
            | ( if ($plan|type) == "object" and ($plan.stages|type) == "array"
                then $plan.stages | map(.id)
                else .stages | map(.stage // .name // .id // "?")
                end ) as $order
            | $order[] as $sid
            | ($by_id[$sid] // {}) as $s
            | (($s | length) == 0) as $missing
            | (if $missing and $sid == $current then "running"
               elif $missing then "skipped"
               else ($s.lifecycle // $s.tech.status // $s.status // "skipped")
               end) as $tech
            | [
                $sid,
                tech_keyword($tech),
                biz_keyword((if $missing then null else $s.business.status end); $tech),
                human_duration_ms((if $missing then null else ($s.tech.duration_ms // $s.duration_ms) end))
              ] | @tsv
        ' "$report_path"
    } | render.table --color-by Business
    render.blank

    # Counts: total / passed / failed / running / skipped. Total tracks
    # the same canonical list driving the table (so totals match what the
    # operator just read above, including N/A backfills and the RUNNING
    # marker for the in-flight stage). Running is at most 1 (the current
    # stage). Skipped is the remainder, so total = passed + failed +
    # running + skipped holds.
    local total passed failed running skipped not_run
    total="$(jq -r --argjson plan "$plan_json" '
        if ($plan|type) == "object" and ($plan.stages|type) == "array"
        then $plan.stages | length
        else .stages | length
        end' "$report_path" 2>/dev/null)"
    # Counts read the canonical lifecycle when present (a warning stage ran, so
    # it counts as passed), falling back to tech.status/status for aggregates
    # produced before lifecycle stamping.
    passed="$(jq -r '[.stages[] | (.lifecycle // .tech.status // .status) | select(. == "success" or . == "warning")] | length' "$report_path" 2>/dev/null)"
    failed="$(jq -r '[.stages[] | select((.lifecycle // .tech.status // .status) == "failed")] | length' "$report_path" 2>/dev/null)"
    not_run="$(jq -r '[.stages[] | select((.lifecycle // "") == "not_run")] | length' "$report_path" 2>/dev/null)"
    running=0
    if [[ -n "$current_stage" ]] && jq -e --arg current "$current_stage" --argjson plan "$plan_json" '
        ($plan|type) == "object" and ($plan.stages|type) == "array"
        and ([$plan.stages[] | .id] | index($current)) != null
        and ([.stages[] | (.stage // .name // .id // "?")] | index($current)) == null
    ' "$report_path" >/dev/null 2>&1; then
        running=1
    fi
    skipped=$(( total - passed - failed - running - not_run ))

    render.section "Summary"
    render.kv "Total stages" "$total"   --key-width 14
    render.kv "Passed"       "$passed"  --key-width 14
    render.kv "Failed"       "$failed"  --key-width 14
    render.kv "Skipped"      "$skipped" --key-width 14
    (( not_run > 0 )) && render.kv "Not run" "$not_run" --key-width 14
    (( running > 0 )) && render.kv "Running" "$running" --key-width 14
    render.blank

    # Business outcome with per-status counts
    local biz_success biz_warning biz_error
    biz_success="$(jq -r '[.stages[] | select(.business.status == "success")] | length' "$report_path" 2>/dev/null)"
    biz_warning="$(jq -r '[.stages[] | select(.business.status == "warning")] | length' "$report_path" 2>/dev/null)"
    biz_error="$(jq -r '[.stages[] | select(.business.status == "error")]   | length' "$report_path" 2>/dev/null)"

    render.section "Business outcome"
    render.kv "Status" "${biz_status^^}" --key-width 14
    render.kv "Counts" "success=${biz_success}, warning=${biz_warning}, error=${biz_error}" --key-width 14
    render.blank

    # Findings counts (just totals; details live in the markdown archive)
    local failing_total ignored_total
    failing_total="$(jq -r '[.stages[] | (.business.findings.failing.total // 0)] | add // 0' "$report_path" 2>/dev/null)"
    ignored_total="$(jq -r '[.stages[] | (.business.findings.ignored.total // 0)] | add // 0' "$report_path" 2>/dev/null)"

    render.section "Findings"
    render.kv "Failing" "$failing_total" --key-width 14
    render.kv "Ignored" "$ignored_total" --key-width 14
    render.blank
}

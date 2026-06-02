#!/usr/bin/env bash
# @module report.render_md
# @requires jq
# @description Markdown renderers for the pipeline report.
#
# Split out of lib/pipeline/report.sh. Renders the v1 aggregate JSON
# (_report._render_aggregate_md) and the local backend shape
# (_report._render_md) as Markdown, and owns report.render which writes the
# md/json/html artifacts. Loaded by the report.sh facade.
#
# Depends on facade-provided globals/functions (resolved at runtime):
#   _BRIK_JQ_DURATION_DEFS   (jq duration library, defined in report.sh)
#   _report._stage_order     (report/fragment.sh)
#   _report._render_html     (report_html/render.sh)

[[ -n "${_BRIK_REPORT_RENDER_MD_LOADED:-}" ]] && return 0
_BRIK_REPORT_RENDER_MD_LOADED=1

# shellcheck source=../logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../logging.sh"
# shellcheck source=../error.sh
[[ -z "${_BRIK_ERROR_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../error.sh"

# Render the v1 aggregate JSON as Markdown on stdout. Distinct from
# _report._render_md, which targets the local backend shape (pipeline_id,
# stages[].name, tech.status). The aggregate produced by
# report.aggregate_fragments has pipeline.id, stages[].stage, fragment-level
# status/rc -- selectors here mirror schemas/report/v1/aggregate.schema.json.
_report._render_aggregate_md() {
    local backend="$1"
    local _stage_order
    _stage_order="$(_report._stage_order)"
    # KCOV_EXCL_START  -- jq script body is not bash code
    jq -r --arg stage_order "$_stage_order" "${_BRIK_JQ_DURATION_DEFS}"'
        # ----- Phase 2 helpers --------------------------------------------
        # Stage execution order: sourced from registry.stage.list when the
        # registry is loaded (single source of truth), else the documented
        # fixed-flow fallback (see _report._stage_order). Stages not on the
        # list sort to the end (rank 99) but keep their input order via a
        # stable secondary key.
        def stage_rank($name):
          ($stage_order | split(" ")) | index($name) // 99;

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
          elif $s == "not_run" then "[NOT-RUN]"
          elif $s == "running" then "[RUNNING]"
          else "[?]" end;

        # pad2 / human_duration_ms come from ${_BRIK_JQ_DURATION_DEFS}
        # (top of report.sh), prepended to this program above.

        # 0 -> "0B", 1142 -> "1.1KB", 1500000 -> "1.4MB". Used to render
        # artifact sizes in the stages table Metrics column.
        def round1($x): (($x * 10) | round) / 10;
        def human_size($b):
          if $b == null or (($b | type) != "number") then "-"
          elif $b < 1024    then "\($b)B"
          elif $b < 1048576 then "\(round1($b / 1024.0))KB"
          else                   "\(round1($b / 1048576.0))MB"
          end;

        # Business status label (success/warning/error) emitted in the
        # Business column of the stages table. "-" when the stage has
        # no business payload (rare; legacy local-only stages).
        def biz_label($b):
          if $b == null or $b.status == null then "-"
          else $b.status
          end;

        # Single-line summary of the business payload for the Metrics
        # column. Picks the first applicable signal, ordered by
        # operator-relevance: failing/total findings, tests passed/total,
        # artifact size, image full name, commit short sha.
        def metrics_for($b):
          if $b == null then "-"
          elif ($b.findings.total // null) != null then
            "findings \((($b.findings.failing | objects | .total) // ($b.findings.failing | numbers) // 0))/\($b.findings.total)"
          elif ($b.tests.total // null) != null then
            "\($b.tests.passed // 0)/\($b.tests.total) passed"
          elif ($b.artifact.size_bytes // null) != null then
            "artifact \(human_size($b.artifact.size_bytes))"
          elif ($b.image.full_name // null) != null then
            "image \($b.image.full_name)"
          elif ($b.commit.short_sha // null) != null then
            "commit \($b.commit.short_sha)"
          else "-"
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

        # ----- Business outcome context -----------------------------------
        # Names the stages contributing to the warning/error buckets and
        # adds a one-line note explaining what a "warning" business status
        # means: the stage finished technically but emitted findings that
        # stay within the active policy thresholds (e.g. container-scan
        # reporting CVEs that are below the configured fail line).
        def render_business_context:
          ([ .stages[]? | select((.business.status // "") == "warning") | (.stage // "-") ]) as $warns
          | ([ .stages[]? | select((.business.status // "") == "error")   | (.stage // "-") ]) as $errs
          | if (($warns | length) + ($errs | length)) == 0 then empty
            else
              (if ($warns | length) > 0
                then "- **Warning stages:** \($warns | join(", "))"
                else empty end),
              (if ($errs | length) > 0
                then "- **Error stages:** \($errs | join(", "))"
                else empty end),
              "",
              "_A stage reports `warning` when it finished technically but its findings stay within the active policy thresholds; it reports `error` when those thresholds are breached. See the Failing/Ignored sections below for the per-finding breakdown._",
              ""
            end;

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
        # Columns:
        #   Stage     -- stage id (init, build, lint, ...)
        #   Status    -- canonical lifecycle stamped at aggregation
        #                (success/warning/failed/skipped/not_run/running),
        #                falling back to tech status for pre-lifecycle reports
        #   Business  -- business outcome (success/warning/error) from
        #                business.status
        #   Duration  -- human-readable elapsed time
        #   Metrics   -- one-line summary of the most relevant business
        #                signal per stage (findings ratio, tests passed,
        #                artifact size, image full name, commit sha)
        #   Job       -- link to the CI job page
        # Business + Metrics were previously surfaced only via the live
        # CI log recap (_notify._emit_recap_table). Folding them into the
        # markdown report avoids duplication and means the published
        # aggregate-report.md is the single source of truth for both
        # live and archived consumption.
        def render_stages_table:
          "## Stages",
          "",
          "| Stage | Status | Business | Duration | Metrics | Job |",
          "|---|---|---|---|---|---|",
          (.stages // []
           | sort_by([stage_rank(.stage), .stage])
           | .[]
           | (
               "| " + (.stage // "-")
               + " | " + status_glyph(.lifecycle // .status // "?") + " " + (.lifecycle // .status // "-")
                       + (if ((.tech.dry_run // false) | tostring) == "true" then " _(dry-run)_" else "" end)
               + " | " + biz_label(.business // null)
               + " | " + human_duration_ms(.duration_ms)
               + " | " + metrics_for(.business // null)
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
          render_business_context,
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
        (.stages[] | "| \(.stage) | \(.tech.status // "-")\(if ((.tech.dry_run // false) | tostring) == "true" then " _(dry-run)_" else "" end) | \(.tech.duration_ms // "-") | \(.tech.exit_code // "-") |"),
        "",
        "## Business",
        "",
        (
          .stages[]
          | select(.business != null and (.business | length) > 0)
          | ("### \(.stage)\(if ((.tech.dry_run // false) | tostring) == "true" then " _(dry-run)_" else "" end)",
             "",
             (.business | to_entries[] | "- **\(.key):** \(.value)"),
             "")
        )
    ' "$backend"
    # KCOV_EXCL_STOP
}

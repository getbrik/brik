#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module report/lifecycle
# @description Pure classifier for the canonical per-stage lifecycle.
#
# Single source of truth for the cycle of life of a stage in the aggregate
# report. report.aggregate_fragments stamps stages[].lifecycle +
# lifecycle_reason from this function. The HTML, terminal, and notify-recap
# renderers are migrated to consume that field in Phase 2 (until then they keep
# their own classification); centralizing the rule here is what lets that
# migration remove their historical divergence.

# Guard against double-sourcing
[[ -n "${_BRIK_REPORT_LIFECYCLE_LOADED:-}" ]] && return 0
_BRIK_REPORT_LIFECYCLE_LOADED=1

# Classify a stage into one canonical lifecycle state plus a human reason.
#
# Pure: reads only its positional arguments, prints "<lifecycle>\t<reason>"
# on stdout, touches no shell state and no files.
#
# Lifecycle values: success | warning | failed | skipped | not_run | running.
# The legacy technical `status` (success|failed|skipped) is unchanged
# elsewhere; this value is additive and merges the technical, business, and
# plan axes into the single state operators read.
#
# Usage:
#   _report._classify_lifecycle <tech_status> <business_status> \
#       <plan_decision> <has_fragment> <upstream_failed> <is_current_stage>
#
# Arguments:
#   tech_status      success|failed|skipped|""  (empty when no fragment)
#   business_status  success|warning|error|""   (empty when no fragment)
#   plan_decision    run|skip|unknown|""
#   has_fragment     true|false  -- a real fragment was recorded on disk
#   upstream_failed  true|false  -- a transitive dependency-graph ancestor failed
#   is_current_stage true|false  -- this stage is the one rendering the report
_report._classify_lifecycle() {
    local tech_status="$1"
    local business_status="$2"
    local plan_decision="$3"
    local has_fragment="$4"
    local upstream_failed="$5"
    local is_current_stage="$6"

    local lifecycle reason

    if [[ "$has_fragment" == "true" ]]; then
        # The stage ran and recorded a fragment: classify from its own
        # technical + business outcome. tech_status is authoritative for
        # failure; business.status promotes a technically-green stage to
        # 'warning' (degraded but non-blocking, per the chantier #1 matrix).
        if [[ "$tech_status" == "failed" ]]; then
            lifecycle="failed";  reason="stage failed"
        elif [[ "$tech_status" == "skipped" ]]; then
            lifecycle="skipped"; reason="skipped"
        elif [[ "$business_status" == "warning" ]]; then
            lifecycle="warning"; reason="completed with warnings"
        elif [[ "$business_status" == "error" ]]; then
            # Defensive: a business error without a technical failure is an
            # inconsistency. Surface it as a non-fatal warning rather than a
            # clean success, never as failed (the run itself did not fail).
            lifecycle="warning"; reason="business error without technical failure"
        else
            lifecycle="success"; reason="ok"
        fi
    else
        # No fragment on disk. Distinguish in-flight (running) from
        # planner-skip, upstream-blocked (not_run), not-reached, and absent.
        # Precedence (council amendment): running > skip > upstream > run.
        if [[ "$is_current_stage" == "true" ]]; then
            lifecycle="running"; reason="in flight"
        elif [[ "$plan_decision" == "skip" ]]; then
            lifecycle="skipped"; reason="planner: skipped"
        elif [[ "$upstream_failed" == "true" ]]; then
            lifecycle="not_run"; reason="blocked by upstream failure"
        elif [[ "$plan_decision" == "run" ]]; then
            lifecycle="not_run"; reason="not reached"
        else
            lifecycle="skipped"; reason="not in plan"
        fi
    fi

    printf '%s\t%s\n' "$lifecycle" "$reason"
}

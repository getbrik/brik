#!/usr/bin/env bash
# @module transverse.findings.gate
# @requires jq
# @description Orchestration + gating stage of the findings pipeline:
#   run a tool SARIF through ingest -> policy -> aggregate (process),
#   compose a verify-scan gate (scan_gate), and decide pass/fail from the
#   recorded failing count (gate). Split out of lib/transverse/findings.sh;
#   loaded by the findings.sh facade.
#
# Cross-module calls resolved at runtime via the facade:
#   findings.from_sarif / from_json   (findings/ingest.sh)
#   findings.apply_policy             (findings/policy.sh)
#   findings.aggregate                (findings/aggregate.sh)
#   fix_classifier.classify_sarif     (transverse/fix_classifier.sh)
#   _brik.log_dir._resolve            (pipeline/logging.sh)

[[ -n "${_BRIK_MODULE_TRANSVERSE_FINDINGS_GATE_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_FINDINGS_GATE_LOADED=1

# Run a stage's tool SARIF through the unified ingest -> policy ->
# aggregate pipeline. This is the single integration point every
# SARIF-native verify stage calls after the tool finishes; it preserves
# the two-file layout (tool SARIF kept verbatim, post-policy SARIF
# written next to it as findings.sarif).
#
# Behaviour:
#   - tool_sarif missing                  -> silent no-op (return 0).
#   - tool_sarif structurally invalid     -> skip policy step, aggregate
#                                            the raw tool output so L4 v1
#                                            counters still surface.
#   - apply_policy fails                  -> aggregate the raw tool
#                                            output (no findings.sarif).
#   - happy path                          -> findings.sarif written, then
#                                            aggregated for L4 v1+v2.
#
# Args:
#   $1 stage      -- stage name (used as the L4 backend key).
#   $2 tool_sarif -- absolute or workspace-relative path to the tool's
#                    native SARIF output.
findings.process() {
    if [[ $# -lt 2 ]]; then
        printf 'findings.process: missing arguments (expected: stage tool_sarif)\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    local stage="$1" tool_sarif="$2"
    if [[ -z "$stage" ]]; then
        printf 'findings.process: stage must not be empty\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    [[ -f "$tool_sarif" ]] || return 0

    if ! findings.from_sarif "$stage" "$tool_sarif" 2>/dev/null; then
        # Invalid SARIF: aggregate the tool output so the L4 v1 contract
        # (total/by_severity/cwe) still records what we could parse.
        findings.aggregate "$stage" "$tool_sarif" 2>/dev/null || true
        return 0
    fi

    # SC13: annotate fix-exists classification on every result before policy
    # application. Best-effort: a failure here (jq error, classifier module
    # absent) leaves the SARIF unannotated; apply_policy keeps working and
    # business.evaluate falls back to the conservative has_fix default.
    if declare -f fix_classifier.classify_sarif >/dev/null 2>&1; then
        fix_classifier.classify_sarif "$tool_sarif" "$stage" 2>/dev/null || true
    fi

    local findings_sarif
    findings_sarif="$(dirname "$tool_sarif")/findings.sarif"
    if findings.apply_policy "$tool_sarif" "$findings_sarif" 2>/dev/null; then
        findings.aggregate "$stage" "$findings_sarif" 2>/dev/null || true
    else
        # apply_policy failure (invalid preset, jq error, ...) is unusual
        # enough to deserve a visible warning; the operator might be
        # mis-configured. Fall back to aggregating the raw tool SARIF so
        # the L4 backend still records counts (build may still gate on
        # pre-policy findings, which is the safer behaviour).
        printf 'findings.process: apply_policy failed for stage %s; aggregating raw tool SARIF without policy annotations\n' \
            "$stage" >&2
        findings.aggregate "$stage" "$tool_sarif" 2>/dev/null || true
    fi
    return 0
}

# Verify-scan gate composition: run findings.process on a stage's SARIF
# (if present) and decide the stage outcome from findings.gate. When no
# SARIF is on disk the helper returns the original tool exit code so call
# sites preserve their pre-policy semantics for tool-failure paths.
#
# Defensive: trust the gate only when business.findings actually landed
# in the L4 backend. A silent record_object failure (disk full, lock
# contention, ...) leaves the entry absent; in that case the helper
# falls back to the tool exit code instead of declaring an unconditional
# pass, which would otherwise hide a critical finding behind an
# infrastructure error.
#
# Args:
#   $1 stage       -- stage name to look up in the L4 backend.
#   $2 tool_rc     -- exit code returned by the tool runner; used as the
#                     fallback when no SARIF was produced or when the
#                     policy step did not record anything.
#   $3 sarif_path  -- absolute or workspace-relative path to the tool's
#                     native SARIF; when present, drives policy gating.
findings.scan_gate() {
    if [[ $# -lt 3 ]]; then
        printf 'findings.scan_gate: missing arguments (expected: stage tool_rc sarif_path)\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    local stage="$1" tool_rc="$2" sarif_path="$3"
    if [[ -z "$stage" ]]; then
        printf 'findings.scan_gate: stage must not be empty\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ -f "$sarif_path" ]]; then
        findings.process "$stage" "$sarif_path" 2>/dev/null || true

        # Verify business.findings actually landed before trusting the gate.
        local backend
        backend="$(_brik.log_dir._resolve)/aggregate-report.json"
        if [[ -f "$backend" ]] && command -v jq >/dev/null 2>&1; then
            local _has_entry
            _has_entry="$(jq -r --arg s "$stage" \
                '.stages[] | select(.stage == $s) | .business.findings | if . == null then "no" else "yes" end' \
                "$backend" 2>/dev/null)"
            if [[ "$_has_entry" == "yes" ]]; then
                if findings.gate "$stage" 2>/dev/null; then
                    return 0
                fi
                return "$BRIK_EXIT_CHECK_FAILED"
            fi
        fi
    fi
    return "$tool_rc"
}

# Pass/fail gate based on the policy-annotated business.findings.failing
# count for a given stage. Returns BRIK_EXIT_CHECK_FAILED when failing > 0
# so the calling stage can propagate the failure back to the pipeline; any
# other condition (no backend, no business entry, missing jq) is a silent
# pass so the gate never falsely fails a pipeline that hasn't recorded
# findings yet.
#
# Args:
#   $1 stage -- stage name to look up in the aggregate-report.json backend.
findings.gate() {
    if [[ $# -lt 1 ]]; then
        printf 'findings.gate: missing argument (expected: stage)\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    local stage="$1"
    if [[ -z "$stage" ]]; then
        printf 'findings.gate: stage must not be empty\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local backend
    backend="$(_brik.log_dir._resolve)/aggregate-report.json"
    [[ -f "$backend" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    # Defensive shared lock during the read: mv is atomic on POSIX so a
    # torn read is unlikely with the writer's tmp+mv pattern, but the
    # shared lock additionally serialises the read with concurrent
    # writers in Jenkins parallel verify so the gate cannot observe a
    # transient state during a record_object update.
    local lock_file="${backend}.lock"
    local failing
    if command -v flock >/dev/null 2>&1; then
        failing="$(
            {
                flock -s 9
                jq -r --arg s "$stage" \
                    '.stages[] | select(.stage == $s) | ((.business.findings.failing | objects | .total) // (.business.findings.failing | numbers) // 0)' \
                    "$backend"
            } 9>>"$lock_file" 2>/dev/null
        )"
    else
        failing="$(jq -r --arg s "$stage" \
            '.stages[] | select(.stage == $s) | ((.business.findings.failing | objects | .total) // (.business.findings.failing | numbers) // 0)' \
            "$backend" 2>/dev/null)"
    fi
    failing="${failing:-0}"

    if (( failing > 0 )); then
        return "$BRIK_EXIT_CHECK_FAILED"
    fi
    return 0
}

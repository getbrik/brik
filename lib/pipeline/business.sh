#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module business
# @description Business outcome filter.
#
# Transforms a stage's (technical status, side-band signals, pipeline
# context, fix-exists classification) into the typed business outcome
# (status, reason).
#
# Pure function: reads named flags as inputs, returns the result as JSON
# on stdout, never touches the report backend or shell state.
#
# Matrix (10 rows, per docs/chantiers/20260511_pipeline-behavior-model.md):
#
#   tech.status | side-band                    | context  | business.status
#   ------------+------------------------------+----------+----------------
#   success     | none                         | *        | success
#   success     | findings.ignored.total > 0   | *        | warning
#   success     | findings.failing.no_fix > 0  | *        | warning
#   failed      | fix_class = has_fix          | snapshot | warning
#   failed      | fix_class = has_fix          | release  | error
#   failed      | fix_class = no_fix           | snapshot | warning
#   failed      | fix_class = no_fix           | release  | warning
#   failed      | fix_class = unknown          | snapshot | warning
#   failed      | fix_class = unknown          | release  | error
#   skipped (not-applicable) | *               | *        | success
#
# fix_class priority when multiple failing counters are non-zero:
#   has_fix > unknown > no_fix-only.
# Default fix_class when all three counters are zero (no failing
# classification metadata produced by the stage) is has_fix: conservative
# treatment (BLOCK in release) for stages that fail without producing a
# classification.

# Guard against double-sourcing
[[ -n "${_BRIK_BUSINESS_LOADED:-}" ]] && return 0
_BRIK_BUSINESS_LOADED=1

# Source logging + error if not already loaded so error.raise + log.* are
# available when this module is sourced standalone (e.g. in ShellSpec).
# shellcheck source=logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/logging.sh"
# shellcheck source=error.sh
[[ -z "${_BRIK_ERROR_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/error.sh"

# Validate that a positional value is a non-negative integer for a given
# flag name. Used by the input-validation pass before applying the matrix.
_business._validate_count() {
    local flag="$1" value="$2"
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        error.raise "$BRIK_EXIT_INVALID_INPUT" \
            "business.evaluate: ${flag} must be a non-negative integer (got '${value}')"
        return "$?"
    fi
}

# Compute the business outcome of a stage.
#
# Usage:
#   business.evaluate \
#     --tech-status               success|failed|skipped \
#     --context                   snapshot|release \
#     [--findings-ignored         <integer>=0] \
#     [--findings-failing-has-fix <integer>=0] \
#     [--findings-failing-no-fix  <integer>=0] \
#     [--findings-failing-unknown <integer>=0] \
#     [--tech-kind                <string>=""]
#
# Stdout: JSON object {"status": "...", "reason": "..."}.
# Return: 0 on success, BRIK_EXIT_INVALID_INPUT (2) on malformed inputs.
business.evaluate() {
    local tech_status="" context="" tech_kind=""
    local findings_ignored="0"
    local failing_has_fix="0" failing_no_fix="0" failing_unknown="0"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tech-status)
                tech_status="${2:-}"
                shift 2
                ;;
            --context)
                context="${2:-}"
                shift 2
                ;;
            --findings-ignored)
                findings_ignored="${2:-}"
                shift 2
                ;;
            --findings-failing-has-fix)
                failing_has_fix="${2:-}"
                shift 2
                ;;
            --findings-failing-no-fix)
                failing_no_fix="${2:-}"
                shift 2
                ;;
            --findings-failing-unknown)
                failing_unknown="${2:-}"
                shift 2
                ;;
            --tech-kind)
                tech_kind="${2:-}"
                shift 2
                ;;
            *)
                error.raise "$BRIK_EXIT_INVALID_INPUT" \
                    "business.evaluate: unknown flag '$1'"
                return "$?"
                ;;
        esac
    done

    case "$tech_status" in
        success|failed|skipped) ;;
        "")
            error.raise "$BRIK_EXIT_INVALID_INPUT" \
                "business.evaluate: --tech-status is required (one of success|failed|skipped)"
            return "$?"
            ;;
        *)
            error.raise "$BRIK_EXIT_INVALID_INPUT" \
                "business.evaluate: --tech-status must be one of success|failed|skipped (got '${tech_status}')"
            return "$?"
            ;;
    esac

    case "$context" in
        snapshot|release) ;;
        "")
            error.raise "$BRIK_EXIT_INVALID_INPUT" \
                "business.evaluate: --context is required (one of snapshot|release)"
            return "$?"
            ;;
        *)
            error.raise "$BRIK_EXIT_INVALID_INPUT" \
                "business.evaluate: --context must be one of snapshot|release (got '${context}')"
            return "$?"
            ;;
    esac

    _business._validate_count "--findings-ignored"            "$findings_ignored"  || return "$?"
    _business._validate_count "--findings-failing-has-fix"    "$failing_has_fix"   || return "$?"
    _business._validate_count "--findings-failing-no-fix"     "$failing_no_fix"    || return "$?"
    _business._validate_count "--findings-failing-unknown"    "$failing_unknown"   || return "$?"

    local status reason
    case "$tech_status" in
        success)
            # Side-band precedence: ignored wins over failing.no_fix when both
            # are non-zero (policy-accepted is the stronger signal: someone has
            # already taken a decision on those findings).
            if (( findings_ignored > 0 )); then
                status="warning"
                reason="findings accepted by policy"
            elif (( failing_no_fix > 0 )); then
                status="warning"
                reason="findings without upstream fix"
            else
                status="success"
                reason=""
            fi
            ;;
        failed)
            local kind_label="${tech_kind:-failure}"
            local fix_class
            if   (( failing_has_fix > 0 ));  then fix_class="has_fix"
            elif (( failing_unknown > 0 ));  then fix_class="unknown"
            elif (( failing_no_fix > 0 ));   then fix_class="no_fix"
            else                                  fix_class="has_fix"  # conservative default
            fi

            case "${fix_class}_${context}" in
                has_fix_snapshot)
                    status="warning"
                    reason="${kind_label} (fix available)"
                    ;;
                has_fix_release)
                    status="error"
                    reason="${kind_label} (fix available, not applied)"
                    ;;
                no_fix_snapshot)
                    status="warning"
                    reason="${kind_label} (no fix available)"
                    ;;
                no_fix_release)
                    # Entreprise decides: tagged 'accepted' to make the
                    # trade-off explicit in the report.
                    status="warning"
                    reason="${kind_label} (no fix available, accepted)"
                    ;;
                unknown_snapshot)
                    status="warning"
                    reason="${kind_label} (fix classification unknown)"
                    ;;
                unknown_release)
                    status="error"
                    reason="${kind_label} (fix classification unknown, strict)"
                    ;;
            esac
            ;;
        skipped)
            status="success"
            reason="not applicable"
            ;;
    esac

    printf '{"status":"%s","reason":"%s"}\n' "$status" "$reason"
}

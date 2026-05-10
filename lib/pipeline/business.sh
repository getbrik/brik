#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module business
# @description Business outcome filter.
#
# Transforms a stage's (technical status, side-band signals, pipeline
# context) into the typed business outcome (status, reason).
#
# Pure function: reads named flags as inputs, returns the result as JSON
# on stdout, never touches the report backend or shell state.
#
# Matrix:
#
#   tech.status | side-band              | context  | business.status
#   ------------+------------------------+----------+----------------
#   success     | none                   | *        | success
#   success     | findings.ignored > 0   | *        | warning
#   failed      | *                      | snapshot | warning
#   failed      | *                      | release  | error
#   skipped     | *                      | *        | success

# Guard against double-sourcing
[[ -n "${_BRIK_BUSINESS_LOADED:-}" ]] && return 0
_BRIK_BUSINESS_LOADED=1

# Source logging + error if not already loaded so error.raise + log.* are
# available when this module is sourced standalone (e.g. in ShellSpec).
# shellcheck source=logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/logging.sh"
# shellcheck source=error.sh
[[ -z "${_BRIK_ERROR_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/error.sh"

# Compute the business outcome of a stage.
#
# Usage:
#   business.evaluate \
#     --tech-status success|failed|skipped \
#     --context     snapshot|release \
#     [--findings-ignored <integer>=0] \
#     [--tech-kind <string>=""]
#
# Stdout: JSON object {"status": "...", "reason": "..."}.
# Return: 0 on success, BRIK_EXIT_INVALID_INPUT on malformed inputs.
business.evaluate() {
    local tech_status="" context="" tech_kind="" findings_ignored="0"

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

    if ! [[ "$findings_ignored" =~ ^[0-9]+$ ]]; then
        error.raise "$BRIK_EXIT_INVALID_INPUT" \
            "business.evaluate: --findings-ignored must be a non-negative integer (got '${findings_ignored}')"
        return "$?"
    fi

    local status reason
    case "$tech_status" in
        success)
            if (( findings_ignored > 0 )); then
                status="warning"
                reason="${findings_ignored} findings ignored by policy"
            else
                status="success"
                reason=""
            fi
            ;;
        failed)
            local kind_label="${tech_kind:-failure}"
            if [[ "$context" == "release" ]]; then
                status="error"
                reason="failed in release context (${kind_label})"
            else
                status="warning"
                reason="failed in snapshot context (${kind_label})"
            fi
            ;;
        skipped)
            status="success"
            reason="not applicable"
            ;;
    esac

    printf '{"status":"%s","reason":"%s"}\n' "$status" "$reason"
}

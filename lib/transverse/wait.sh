#!/usr/bin/env bash
# @module transverse.wait
# @description Generic poll-until-timeout helper.
#
# transverse.wait.until factors out the "while elapsed < timeout; check; sleep"
# pattern duplicated across gitops.wait_sync and rollout.health.wait.
# The check function returns 0 to indicate success (stop polling) and non-zero
# to continue waiting. The helper handles logging, timeout tracking, dry-run,
# and input validation.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_WAIT_LOADED:-}" ]] && return 0
_BRIK_MODULE_WAIT_LOADED=1

# transverse.wait.until - poll a check function until success or timeout.
#
# Usage:
#   transverse.wait.until <check_fn>
#                         [--timeout <sec>]    default 300
#                         [--interval <sec>]   default 10, must be >= 1
#                         [--message <str>]    prefix for log lines
#                         [--dry-run]          skip polling; honours BRIK_DRY_RUN
#
# <check_fn> may carry arguments embedded in the string (split on whitespace);
# the first word must be a declared function.
#
# Returns:
#   0                          on success before timeout
#   BRIK_EXIT_INVALID_INPUT    on argument validation failure
#   BRIK_EXIT_TIMEOUT          when timeout elapses with no success
transverse.wait.until() {
    local check_fn="" timeout="300" interval="10" message=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)  timeout="$2";   shift 2 ;;
            --interval) interval="$2";  shift 2 ;;
            --message)  message="$2";   shift 2 ;;
            --dry-run)  dry_run="true"; shift ;;
            --*)
                log.error "unknown option: $1"
                return "$BRIK_EXIT_INVALID_INPUT"
                ;;
            *)
                if [[ -z "$check_fn" ]]; then
                    check_fn="$1"
                    shift
                else
                    log.error "unknown option: $1"
                    return "$BRIK_EXIT_INVALID_INPUT"
                fi
                ;;
        esac
    done

    if [[ -z "$check_fn" ]]; then
        log.error "check function is required (first positional argument)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local fn_name="${check_fn%% *}"
    if ! declare -f "$fn_name" >/dev/null 2>&1; then
        log.error "check function is not a declared function: $fn_name"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
        log.error "timeout must be a positive integer, got: $timeout"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if ! [[ "$interval" =~ ^[0-9]+$ ]] || [[ "$interval" -lt 1 ]]; then
        log.error "interval must be a positive integer >= 1, got: $interval"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local prefix="${message:-transverse.wait.until}"

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] ${prefix}: check=${fn_name} timeout=${timeout}s interval=${interval}s"
        return 0
    fi

    log.info "${prefix}: polling ${fn_name} (timeout=${timeout}s, interval=${interval}s)"

    local -a check_cmd
    read -ra check_cmd <<< "$check_fn"

    local elapsed=0
    while [[ "$elapsed" -lt "$timeout" ]]; do
        if "${check_cmd[@]}" 2>/dev/null; then
            log.info "${prefix}: completed after ${elapsed}s"
            return 0
        fi
        log.info "${prefix}: pending (${elapsed}s/${timeout}s), waiting ${interval}s..."
        sleep "$interval"
        elapsed=$(( elapsed + interval ))
    done

    log.error "${prefix}: timeout after ${timeout}s"
    return "$BRIK_EXIT_TIMEOUT"
}

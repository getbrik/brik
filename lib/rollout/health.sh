#!/usr/bin/env bash
# @module rollout.health
# @requires curl, kubectl
# @description Post-deployment health check functions for Brik pipelines.
#
# Functions:
#   rollout.health.check    - Single HTTP health check via curl
#   rollout.health.wait     - Poll URL until healthy or timeout
#   rollout.health.k8s_wait - Wait for Kubernetes rollout via kubectl

# Guard against double-sourcing
[[ -n "${_BRIK_ROLLOUT_HEALTH_LOADED:-}" ]] && return 0
_BRIK_ROLLOUT_HEALTH_LOADED=1

# Perform a single HTTP health check.
# Returns 0 if the HTTP status code matches the expected code, BRIK_EXIT_CHECK_FAILED otherwise.
#
# Usage: rollout.health.check --url <url> [--expected-status <code>]
rollout.health.check() {
    local url="" expected_status="200"
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --url)             url="$2";             shift 2 ;;
            --expected-status) expected_status="$2"; shift 2 ;;
            --dry-run)         dry_run="true";       shift ;;
            --target|--env)    shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$url" ]]; then
        log.error "url is required (--url)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if ! [[ "$url" =~ ^https?:// ]]; then
        log.error "health check URL must use http or https scheme: $url"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if ! [[ "$expected_status" =~ ^[0-9]{3}$ ]]; then
        log.error "expected-status must be a 3-digit HTTP status code, got: $expected_status"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would check health: curl ${url} (expected ${expected_status})"
        return 0
    fi

    pipeline.require_tool curl || return "$BRIK_EXIT_MISSING_DEP"

    local actual_status
    actual_status="$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 --connect-timeout 5 "$url")"

    if [[ "$actual_status" == "$expected_status" ]]; then
        log.info "health check passed: ${url} returned ${actual_status}"
        return 0
    else
        log.warn "health check failed: ${url} returned ${actual_status} (expected ${expected_status})"
        return "$BRIK_EXIT_CHECK_FAILED"
    fi
}

# Internal: single-shot HTTP status match. Used as check-fn for wait loop.
# Usage: _rollout.health._url_status_check <url> <expected_status>
_rollout.health._url_status_check() {
    local url="$1" expected_status="$2"
    local actual_status
    actual_status="$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 --connect-timeout 5 "$url" 2>/dev/null)" || true
    [[ "$actual_status" == "$expected_status" ]]
}

# Poll a URL repeatedly until the expected HTTP status is returned or timeout is reached.
# Delegates the polling loop to transverse.wait.until.
# Returns 0 if healthy before timeout, BRIK_EXIT_TIMEOUT if timeout reached.
#
# Usage: rollout.health.wait --url <url> [--timeout <seconds>] [--interval <seconds>]
#        [--expected-status <code>] [--dry-run]
rollout.health.wait() {
    local url="" timeout="300" interval="10" expected_status="200"
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --url)             url="$2";             shift 2 ;;
            --timeout)         timeout="$2";         shift 2 ;;
            --interval)        interval="$2";        shift 2 ;;
            --expected-status) expected_status="$2"; shift 2 ;;
            --dry-run)         dry_run="true";       shift ;;
            --target|--env)    shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$url" ]]; then
        log.error "url is required (--url)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if ! [[ "$url" =~ ^https?:// ]]; then
        log.error "health check URL must use http or https scheme: $url"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if ! [[ "$expected_status" =~ ^[0-9]{3}$ ]]; then
        log.error "expected-status must be a 3-digit HTTP status code, got: $expected_status"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    pipeline.require_tool curl || return "$BRIK_EXIT_MISSING_DEP"

    brik.use transverse.wait
    local -a wait_args=(
        "_rollout.health._url_status_check $url $expected_status"
        --timeout  "$timeout"
        --interval "$interval"
        --message  "health ${url}"
    )
    [[ "$dry_run" == "true" ]] && wait_args+=(--dry-run)

    transverse.wait.until "${wait_args[@]}"
}

# Wait for a Kubernetes deployment rollout to complete.
# Uses kubectl rollout status with a timeout.
#
# Usage: rollout.health.k8s_wait --namespace <ns> --deployment <name>
#        [--timeout <seconds>] [--dry-run]
rollout.health.k8s_wait() {
    local namespace="" deployment="" timeout="300"
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --namespace)  namespace="$2";  shift 2 ;;
            --deployment) deployment="$2"; shift 2 ;;
            --timeout)    timeout="$2";    shift 2 ;;
            --dry-run)    dry_run="true";  shift ;;
            --target|--env) shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$namespace" ]]; then
        log.error "namespace is required (--namespace)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ -z "$deployment" ]]; then
        log.error "deployment is required (--deployment)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
        log.error "timeout must be a positive integer, got: $timeout"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    pipeline.require_tool kubectl || return "$BRIK_EXIT_MISSING_DEP"

    local -a cmd=(kubectl rollout status "deployment/${deployment}" -n "$namespace" "--timeout=${timeout}s")

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] ${cmd[*]}"
        return 0
    fi

    log.info "waiting for rollout: deployment/${deployment} in namespace ${namespace}"
    "${cmd[@]}" || {
        log.error "rollout status check failed for deployment/${deployment}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "rollout completed successfully: deployment/${deployment}"
    return 0
}

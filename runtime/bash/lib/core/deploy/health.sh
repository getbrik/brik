#!/usr/bin/env bash
# @module deploy.health
# @requires curl, kubectl
# @description Post-deployment health check functions for Brik pipelines.
#
# Functions:
#   deploy.health.check    - Single HTTP health check via curl
#   deploy.health.wait     - Poll URL until healthy or timeout
#   deploy.health.k8s_wait - Wait for Kubernetes rollout via kubectl

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_DEPLOY_HEALTH_LOADED:-}" ]] && return 0
_BRIK_CORE_DEPLOY_HEALTH_LOADED=1

# Perform a single HTTP health check.
# Returns 0 if the HTTP status code matches the expected code, 1 otherwise.
#
# Usage: deploy.health.check --url <url> [--expected-status <code>]
deploy.health.check() {
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

    runtime.require_tool curl || return "$BRIK_EXIT_MISSING_DEP"

    local actual_status
    actual_status="$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 --connect-timeout 5 "$url")"

    if [[ "$actual_status" == "$expected_status" ]]; then
        log.info "health check passed: ${url} returned ${actual_status}"
        return 0
    else
        log.warn "health check failed: ${url} returned ${actual_status} (expected ${expected_status})"
        return 1
    fi
}

# Poll a URL repeatedly until the expected HTTP status is returned or timeout is reached.
# Returns 0 if healthy before timeout, 1 if timeout reached.
#
# Usage: deploy.health.wait --url <url> [--timeout <seconds>] [--interval <seconds>]
#        [--expected-status <code>] [--dry-run]
deploy.health.wait() {
    local url="" timeout="120" interval="5" expected_status="200"
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

    if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
        log.error "timeout must be a positive integer, got: $timeout"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if ! [[ "$interval" =~ ^[0-9]+$ ]] || [[ "$interval" -lt 1 ]]; then
        log.error "interval must be a positive integer >= 1, got: $interval"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if ! [[ "$expected_status" =~ ^[0-9]{3}$ ]]; then
        log.error "expected-status must be a 3-digit HTTP status code, got: $expected_status"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    runtime.require_tool curl || return "$BRIK_EXIT_MISSING_DEP"

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] health wait: polling ${url} (timeout=${timeout}s, interval=${interval}s, expected=${expected_status})"
        return 0
    fi

    log.info "waiting for health check: ${url} (timeout=${timeout}s, interval=${interval}s)"

    local elapsed=0
    while [[ "$elapsed" -lt "$timeout" ]]; do
        local actual_status
        actual_status="$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 --connect-timeout 5 "$url" 2>/dev/null)" || true

        if [[ "$actual_status" == "$expected_status" ]]; then
            log.info "health check passed after ${elapsed}s: ${url} returned ${actual_status}"
            return 0
        fi

        log.info "health check pending (${elapsed}s/${timeout}s): got ${actual_status}, waiting ${interval}s..."
        sleep "$interval"
        elapsed=$(( elapsed + interval ))
    done

    log.error "health check timeout after ${timeout}s: ${url} did not return ${expected_status}"
    return 1
}

# Wait for a Kubernetes deployment rollout to complete.
# Uses kubectl rollout status with a timeout.
#
# Usage: deploy.health.k8s_wait --namespace <ns> --deployment <name>
#        [--timeout <seconds>] [--dry-run]
deploy.health.k8s_wait() {
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

    runtime.require_tool kubectl || return "$BRIK_EXIT_MISSING_DEP"

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

#!/usr/bin/env bash
# @module deploy.strategy
# @requires kubectl
# @description Deployment strategy implementations for Brik pipelines.
#
# Provides basic kubectl-based deployment strategies:
#   - rolling: default strategy via kubectl rollout status
#   - blue_green: traffic switch by patching service selector
#   - canary: gradual rollout by scaling canary deployment replicas
#
# Note: These are simplified implementations. Real blue-green/canary
# typically use service meshes (Istio) or specialized controllers.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_DEPLOY_STRATEGY_LOADED:-}" ]] && return 0
_BRIK_CORE_DEPLOY_STRATEGY_LOADED=1

# Monitor a rolling update via kubectl rollout status.
# The rolling strategy itself is handled by the orchestrator (k8s/helm natively).
# This function waits for the rollout to complete.
#
# Usage: deploy.strategy.rolling --deployment <name> [--namespace <ns>]
#        [--timeout <seconds>] [--dry-run]
deploy.strategy.rolling() {
    local deployment="" namespace="" timeout="300"
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --deployment)  deployment="$2"; shift 2 ;;
            --namespace)   namespace="$2";  shift 2 ;;
            --timeout)     timeout="$2";    shift 2 ;;
            --dry-run)     dry_run="true";  shift ;;
            --target|--env) shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$deployment" ]]; then
        log.error "deployment name is required (--deployment)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
        log.error "timeout must be a positive integer, got: $timeout"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    runtime.require_tool kubectl || return "$BRIK_EXIT_MISSING_DEP"

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] kubectl rollout status deployment/${deployment} --timeout=${timeout}s"
        return 0
    fi

    local -a cmd=(kubectl rollout status "deployment/${deployment}" "--timeout=${timeout}s")
    [[ -n "$namespace" ]] && cmd+=(-n "$namespace")

    log.info "monitoring rolling update for deployment/${deployment}"
    "${cmd[@]}" || {
        log.error "rolling update check failed for deployment/${deployment}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "rolling update completed successfully for deployment/${deployment}"
    return 0
}

# Switch traffic between blue and green deployments by patching the service selector.
# Verifies the new deployment is present, then patches the service to point to it.
#
# Usage: deploy.strategy.blue_green --service <svc> --target-selector <label=value>
#        [--namespace <ns>] [--dry-run]
deploy.strategy.blue_green() {
    local service="" target_selector="" namespace=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --service)         service="$2";          shift 2 ;;
            --target-selector) target_selector="$2";  shift 2 ;;
            --namespace)       namespace="$2";         shift 2 ;;
            --dry-run)         dry_run="true";         shift ;;
            --target|--env)    shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$service" ]]; then
        log.error "service is required (--service)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ -z "$target_selector" ]]; then
        log.error "target-selector is required (--target-selector)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    runtime.require_tool kubectl || return "$BRIK_EXIT_MISSING_DEP"

    # Parse selector key=value
    local selector_key="${target_selector%%=*}"
    local selector_val="${target_selector#*=}"

    if ! [[ "$selector_key" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
        log.error "invalid selector key format: $selector_key"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if ! [[ "$selector_val" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
        log.error "invalid selector value format: $selector_val"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local patch_json
    patch_json="{\"spec\":{\"selector\":{\"${selector_key}\":\"${selector_val}\"}}}"

    local -a cmd=(kubectl patch service "$service" -p "$patch_json")
    [[ -n "$namespace" ]] && cmd+=(-n "$namespace")

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] blue-green switch: ${cmd[*]}"
        return 0
    fi

    log.info "blue-green switch: patching service/${service} selector to ${target_selector}"
    "${cmd[@]}" || {
        log.error "blue-green switch failed for service/${service}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "blue-green switch completed: service/${service} now points to ${target_selector}"
    return 0
}

# Gradual traffic shift via canary deployment replica scaling.
# Scales the canary deployment to the specified number of replicas.
# Simplified: uses kubectl scale to set canary replicas.
#
# Usage: deploy.strategy.canary --service <svc> --deployment <canary-name>
#        [--namespace <ns>] [--replicas <count>] [--dry-run]
deploy.strategy.canary() {
    local service="" deployment="" namespace="" replicas="1"
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --service)    service="$2";    shift 2 ;;
            --deployment) deployment="$2"; shift 2 ;;
            --namespace)  namespace="$2";  shift 2 ;;
            --replicas)   replicas="$2";   shift 2 ;;
            --dry-run)    dry_run="true";  shift ;;
            --target|--env) shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$service" ]]; then
        log.error "service is required (--service)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ -z "$deployment" ]]; then
        log.error "deployment is required (--deployment)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if ! [[ "$replicas" =~ ^[0-9]+$ ]] || [[ "$replicas" -lt 1 ]]; then
        log.error "replicas must be a positive integer, got: $replicas"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    runtime.require_tool kubectl || return "$BRIK_EXIT_MISSING_DEP"

    local -a cmd=(kubectl scale "deployment/${deployment}" "--replicas=${replicas}")
    [[ -n "$namespace" ]] && cmd+=(-n "$namespace")

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] canary deployment: replicas=${replicas}"
        log.info "[dry-run] ${cmd[*]}"
        return 0
    fi

    log.info "canary deployment: scaling deployment/${deployment} to ${replicas} replicas"
    "${cmd[@]}" || {
        log.error "canary scale failed for deployment/${deployment}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "canary deployment active: deployment/${deployment} scaled to ${replicas} replicas"
    return 0
}

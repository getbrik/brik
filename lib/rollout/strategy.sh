#!/usr/bin/env bash
# @module rollout.strategy
# @description Deployment strategy orchestrator with functional composition.
#
# rollout.strategy.run dispatches deployment by strategy type (rolling,
# blue-green, canary), calling user-provided --deploy-fn and --rollback-fn.
#
# Internal kubectl-based helpers are kept as fallback implementations:
#   _rollout.strategy._rolling_kubectl  (delegates to rollout.health.k8s_wait)
#   _rollout.strategy._blue_green_kubectl
#   _rollout.strategy._canary_kubectl

# Guard against double-sourcing
[[ -n "${_BRIK_ROLLOUT_STRATEGY_LOADED:-}" ]] && return 0
_BRIK_ROLLOUT_STRATEGY_LOADED=1

# ---------------------------------------------------------------------------
# rollout.strategy.run - Strategy orchestrator
# ---------------------------------------------------------------------------

# Execute a deployment using the specified strategy.
# --deploy-fn and --rollback-fn are strings split on spaces into arrays.
# The first word must be a declared Bash function (validated via declare -f).
#
# Usage: rollout.strategy.run --type <rolling|blue-green|canary>
#        --deploy-fn <function+args> [--rollback-fn <function+args>] [--dry-run]
#
# Returns: 0=success, 1=deploy failed + rollback failed, 2=invalid input,
#          5=deploy failed + rollback succeeded
rollout.strategy.run() {
    local strategy_type="" deploy_fn_str="" rollback_fn_str=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)        strategy_type="$2";  shift 2 ;;
            --deploy-fn)   deploy_fn_str="$2";  shift 2 ;;
            --rollback-fn) rollback_fn_str="$2"; shift 2 ;;
            --dry-run)     dry_run="true";       shift ;;
            --target|--env) shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$strategy_type" ]]; then
        log.error "type is required (--type)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    case "$strategy_type" in
        rolling|blue-green|canary) ;;
        *) log.error "unknown strategy type: $strategy_type (expected: rolling, blue-green, canary)"
           return "$BRIK_EXIT_INVALID_INPUT" ;;
    esac

    if [[ -z "$deploy_fn_str" ]]; then
        log.error "deploy-fn is required (--deploy-fn)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    # Parse deploy-fn string into array. Locals are underscore-prefixed
    # so they cannot shadow a caller's same-named variables under Bash
    # dynamic scoping (a wrapper deploy-fn that reads its caller's
    # `deploy_args` would otherwise see this empty array instead).
    local -a _strategy_deploy_cmd
    read -ra _strategy_deploy_cmd <<< "$deploy_fn_str"
    local _strategy_deploy_fn_name="${_strategy_deploy_cmd[0]}"
    # shellcheck disable=SC2034
    local -a _strategy_deploy_args=("${_strategy_deploy_cmd[@]:1}")

    if ! declare -f "$_strategy_deploy_fn_name" >/dev/null 2>&1; then
        log.error "deploy-fn is not a declared function: $_strategy_deploy_fn_name"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    # Parse rollback-fn if provided
    local -a _strategy_rollback_cmd=()
    local _strategy_rollback_fn_name=""
    local -a _strategy_rollback_args=()
    if [[ -n "$rollback_fn_str" ]]; then
        read -ra _strategy_rollback_cmd <<< "$rollback_fn_str"
        _strategy_rollback_fn_name="${_strategy_rollback_cmd[0]}"
        # shellcheck disable=SC2034
        _strategy_rollback_args=("${_strategy_rollback_cmd[@]:1}")
        if ! declare -f "$_strategy_rollback_fn_name" >/dev/null 2>&1; then
            log.error "rollback-fn is not a declared function: $_strategy_rollback_fn_name"
            return "$BRIK_EXIT_INVALID_INPUT"
        fi
    fi

    local -a common_args=()
    [[ "$dry_run" == "true" ]] && common_args+=(--dry-run)

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] strategy=${strategy_type} deploy-fn=${deploy_fn_str}"
        if [[ -n "$rollback_fn_str" ]]; then
            log.info "[dry-run] rollback-fn=${rollback_fn_str}"
        fi
    fi

    log.info "deploying with strategy: ${strategy_type}"

    case "$strategy_type" in
        rolling)
            _rollout.strategy._exec_rolling \
                _strategy_deploy_fn_name _strategy_deploy_args \
                _strategy_rollback_fn_name _strategy_rollback_args common_args
            ;;
        blue-green)
            _rollout.strategy._exec_blue_green \
                _strategy_deploy_fn_name _strategy_deploy_args \
                _strategy_rollback_fn_name _strategy_rollback_args common_args
            ;;
        canary)
            _rollout.strategy._exec_canary \
                _strategy_deploy_fn_name _strategy_deploy_args \
                _strategy_rollback_fn_name _strategy_rollback_args common_args
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Strategy execution helpers
# ---------------------------------------------------------------------------

# Rolling: deploy, if fail -> rollback
_rollout.strategy._exec_rolling() {
    local -n _dfn=$1 _dargs=$2 _rfn=$3 _rargs=$4 _cargs=$5

    "$_dfn" "${_dargs[@]}" "${_cargs[@]}" || {
        log.error "deploy failed (strategy: rolling)"
        _rollout.strategy._try_rollback "$_rfn" _rargs _cargs
        return $?
    }

    log.info "rolling deployment completed successfully"
    return 0
}

# Blue-green: deploy to inactive env, then switch traffic
# In a simplified model, deploy-fn deploys to the inactive side,
# and success means we can consider it switched.
_rollout.strategy._exec_blue_green() {
    local -n _dfn=$1 _dargs=$2 _rfn=$3 _rargs=$4 _cargs=$5

    "$_dfn" "${_dargs[@]}" "${_cargs[@]}" || {
        log.error "deploy failed (strategy: blue-green)"
        _rollout.strategy._try_rollback "$_rfn" _rargs _cargs
        return $?
    }

    log.info "blue-green deployment completed successfully"
    return 0
}

# Canary: deploy-fn runs the canary, success means promote.
# Simplified: same as rolling for now (canary logic depends on mesh/controller).
_rollout.strategy._exec_canary() {
    local -n _dfn=$1 _dargs=$2 _rfn=$3 _rargs=$4 _cargs=$5

    "$_dfn" "${_dargs[@]}" "${_cargs[@]}" || {
        log.error "deploy failed (strategy: canary)"
        _rollout.strategy._try_rollback "$_rfn" _rargs _cargs
        return $?
    }

    log.info "canary deployment completed successfully"
    return 0
}

# Try rollback; return 5 if rollback succeeds, 1 if rollback also fails
_rollout.strategy._try_rollback() {
    local rfn="$1"
    local -n _rb_args=$2 _rb_cargs=$3

    if [[ -z "$rfn" ]]; then
        log.warn "no rollback-fn provided, cannot rollback"
        return "$BRIK_EXIT_FAILURE"
    fi

    log.info "attempting rollback via: ${rfn}"
    "$rfn" "${_rb_args[@]}" "${_rb_cargs[@]}" || {
        log.error "rollback also failed"
        return "$BRIK_EXIT_FAILURE"
    }

    log.info "rollback succeeded"
    return "$BRIK_EXIT_EXTERNAL_FAIL"
}

# ---------------------------------------------------------------------------
# Internal kubectl helpers (kept as concrete implementations)
# ---------------------------------------------------------------------------

# Rolling kubectl helper - delegates to rollout.health.k8s_wait.
# Usage: _rollout.strategy._rolling_kubectl --deployment <name>
#        [--namespace <ns>] [--timeout <s>] [--dry-run]
_rollout.strategy._rolling_kubectl() {
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

    # Delegate to rollout.health.k8s_wait if namespace provided
    if [[ -n "$namespace" ]]; then
        brik.use rollout.health
        local -a k8s_args=(--namespace "$namespace" --deployment "$deployment" --timeout "$timeout")
        [[ "$dry_run" == "true" ]] && k8s_args+=(--dry-run)
        rollout.health.k8s_wait "${k8s_args[@]}"
        return $?
    fi

    # Fallback: direct kubectl (no namespace)
    pipeline.require_tool kubectl || return "$BRIK_EXIT_MISSING_DEP"

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] kubectl rollout status deployment/${deployment} --timeout=${timeout}s"
        return 0
    fi

    local -a cmd=(kubectl rollout status "deployment/${deployment}" "--timeout=${timeout}s")

    log.info "monitoring rolling update for deployment/${deployment}"
    "${cmd[@]}" || {
        log.error "rolling update check failed for deployment/${deployment}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "rolling update completed successfully for deployment/${deployment}"
    return 0
}

# Blue-green kubectl helper.
# Usage: _rollout.strategy._blue_green_kubectl --service <svc>
#        --target-selector <label=value> [--namespace <ns>] [--dry-run]
_rollout.strategy._blue_green_kubectl() {
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

    pipeline.require_tool kubectl || return "$BRIK_EXIT_MISSING_DEP"

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

# Canary kubectl helper.
# Usage: _rollout.strategy._canary_kubectl --service <svc> --deployment <name>
#        [--namespace <ns>] [--replicas <count>] [--dry-run]
_rollout.strategy._canary_kubectl() {
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

    pipeline.require_tool kubectl || return "$BRIK_EXIT_MISSING_DEP"

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

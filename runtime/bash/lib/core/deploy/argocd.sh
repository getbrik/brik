#!/usr/bin/env bash
# @module deploy.argocd
# @requires argocd
# @description ArgoCD specialized functions for GitOps deployments.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_DEPLOY_ARGOCD_LOADED:-}" ]] && return 0
_BRIK_CORE_DEPLOY_ARGOCD_LOADED=1

# Validate an ArgoCD app name against Kubernetes naming convention.
_deploy.argocd._validate_app_name() {
    local app_name="$1"
    if [[ -z "$app_name" ]]; then
        log.error "app_name is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if ! [[ "$app_name" =~ ^[a-z0-9][a-z0-9.-]*$ ]]; then
        log.error "invalid ArgoCD app name (must match Kubernetes naming convention): $app_name"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
}

# Sync an ArgoCD application.
# Usage: deploy.argocd.sync <app_name>
deploy.argocd.sync() {
    local app_name="${1:-}"

    _deploy.argocd._validate_app_name "$app_name" || return $?

    runtime.require_tool argocd || return "$BRIK_EXIT_MISSING_DEP"

    if [[ "${BRIK_DRY_RUN:-}" == "true" ]]; then
        log.info "[dry-run] would run: argocd app sync ${app_name}"
        return 0
    fi

    log.info "syncing argocd app: ${app_name}"
    argocd app sync "$app_name" || {
        log.error "argocd app sync failed for: ${app_name}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "argocd sync completed: ${app_name}"
    return 0
}

# Wait for an ArgoCD application to become healthy.
# Usage: deploy.argocd.wait_healthy <app_name> [--timeout <seconds>]
deploy.argocd.wait_healthy() {
    local app_name="${1:-}"

    _deploy.argocd._validate_app_name "$app_name" || return $?

    shift
    local timeout=300

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout) timeout="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
        log.error "timeout must be a positive integer, got: $timeout"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    runtime.require_tool argocd || return "$BRIK_EXIT_MISSING_DEP"

    if [[ "${BRIK_DRY_RUN:-}" == "true" ]]; then
        log.info "[dry-run] would run: argocd app wait ${app_name} --health --timeout ${timeout}"
        return 0
    fi

    log.info "waiting for argocd app to be healthy: ${app_name} (timeout: ${timeout}s)"
    argocd app wait "$app_name" --health --timeout "$timeout" || {
        log.error "argocd app wait failed for: ${app_name}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "argocd app is healthy: ${app_name}"
    return 0
}

# Rollback an ArgoCD application to the previous version.
# Usage: deploy.argocd.rollback <app_name>
deploy.argocd.rollback() {
    local app_name="${1:-}"

    _deploy.argocd._validate_app_name "$app_name" || return $?

    runtime.require_tool argocd || return "$BRIK_EXIT_MISSING_DEP"

    if [[ "${BRIK_DRY_RUN:-}" == "true" ]]; then
        log.info "[dry-run] would run: argocd app rollback ${app_name}"
        return 0
    fi

    log.info "rolling back argocd app: ${app_name}"
    argocd app rollback "$app_name" || {
        log.error "argocd app rollback failed for: ${app_name}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "argocd rollback completed: ${app_name}"
    return 0
}

# Show the diff between the live state and the desired state of an ArgoCD application.
# Usage: deploy.argocd.diff <app_name>
# Returns 0 if no diff, 1 if diff exists.
deploy.argocd.diff() {
    local app_name="${1:-}"

    _deploy.argocd._validate_app_name "$app_name" || return $?

    runtime.require_tool argocd || return "$BRIK_EXIT_MISSING_DEP"

    if [[ "${BRIK_DRY_RUN:-}" == "true" ]]; then
        log.info "[dry-run] would run: argocd app diff ${app_name}"
        return 0
    fi

    log.info "checking diff for argocd app: ${app_name}"
    argocd app diff "$app_name"
    return $?
}

# Show the health and sync status of an ArgoCD application.
# Usage: deploy.argocd.status <app_name>
deploy.argocd.status() {
    local app_name="${1:-}"

    _deploy.argocd._validate_app_name "$app_name" || return $?

    runtime.require_tool argocd || return "$BRIK_EXIT_MISSING_DEP"

    if [[ "${BRIK_DRY_RUN:-}" == "true" ]]; then
        log.info "[dry-run] would run: argocd app get ${app_name}"
        return 0
    fi

    log.info "getting status for argocd app: ${app_name}"
    argocd app get "$app_name" || {
        log.error "argocd app get failed for: ${app_name}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    return 0
}

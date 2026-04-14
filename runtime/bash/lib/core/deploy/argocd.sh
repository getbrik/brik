#!/usr/bin/env bash
# @module deploy.argocd
# @requires argocd
# @description ArgoCD specialized functions for GitOps deployments.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_DEPLOY_ARGOCD_LOADED:-}" ]] && return 0
_BRIK_CORE_DEPLOY_ARGOCD_LOADED=1

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Validate an ArgoCD app name against Kubernetes naming convention.
_deploy.argocd._validate_app_name() {
    local app_name="$1"
    if [[ -z "$app_name" ]]; then
        log.error "app is required (--app)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if ! [[ "$app_name" =~ ^[a-z0-9][a-z0-9.-]*$ ]]; then
        log.error "invalid ArgoCD app name (must match Kubernetes naming convention): $app_name"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
}

# Build common argocd CLI flags for --server and --auth-token-var.
# Populates the caller's cmd array via nameref.
_deploy.argocd._add_server_auth() {
    local -n _cmd=$1
    local server="${2:-${ARGOCD_SERVER:-}}"
    local auth_token_var="$3"

    if [[ -n "$server" ]]; then
        _cmd+=(--server "$server" --insecure)
    fi
    if [[ -n "$auth_token_var" ]]; then
        local token="${!auth_token_var:-}"
        if [[ -z "$token" ]]; then
            log.error "auth token variable is empty or unset: $auth_token_var"
            return "$BRIK_EXIT_INVALID_ENV"
        fi
        _cmd+=(--auth-token "$token")
    elif [[ -n "${ARGOCD_AUTH_TOKEN:-}" ]]; then
        _cmd+=(--auth-token "$ARGOCD_AUTH_TOKEN")
    fi
}

# ---------------------------------------------------------------------------
# deploy.argocd.sync
# ---------------------------------------------------------------------------

# Sync an ArgoCD application.
# Usage: deploy.argocd.sync --app <name> [--server <url>] [--auth-token-var <VAR>]
#        [--prune] [--async] [--dry-run]
deploy.argocd.sync() {
    local app_name="" server="" auth_token_var=""
    local prune="false" async="false"
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --app)            app_name="$2";       shift 2 ;;
            --server)         server="$2";         shift 2 ;;
            --auth-token-var) auth_token_var="$2"; shift 2 ;;
            --prune)          prune="true";        shift ;;
            --async)          async="true";        shift ;;
            --dry-run)        dry_run="true";      shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    _deploy.argocd._validate_app_name "$app_name" || return $?

    runtime.require_tool argocd || return "$BRIK_EXIT_MISSING_DEP"

    local -a cmd=(argocd app sync "$app_name")
    _deploy.argocd._add_server_auth cmd "$server" "$auth_token_var" || return $?
    [[ "$prune" == "true" ]] && cmd+=(--prune)
    [[ "$async" == "true" ]] && cmd+=(--async)

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would run: ${cmd[*]}"
        return 0
    fi

    log.info "syncing argocd app: ${app_name}"
    "${cmd[@]}" || {
        log.error "argocd app sync failed for: ${app_name}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "argocd sync completed: ${app_name}"
    return 0
}

# ---------------------------------------------------------------------------
# deploy.argocd.wait_healthy
# ---------------------------------------------------------------------------

# Wait for an ArgoCD application to become healthy.
# Usage: deploy.argocd.wait_healthy --app <name> [--server <url>]
#        [--auth-token-var <VAR>] [--timeout <s>] [--dry-run]
deploy.argocd.wait_healthy() {
    local app_name="" server="" auth_token_var=""
    local timeout=300
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --app)            app_name="$2";       shift 2 ;;
            --server)         server="$2";         shift 2 ;;
            --auth-token-var) auth_token_var="$2"; shift 2 ;;
            --timeout)        timeout="$2";        shift 2 ;;
            --dry-run)        dry_run="true";      shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    _deploy.argocd._validate_app_name "$app_name" || return $?

    if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
        log.error "timeout must be a positive integer, got: $timeout"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    runtime.require_tool argocd || return "$BRIK_EXIT_MISSING_DEP"

    local -a cmd=(argocd app wait "$app_name" --health --timeout "$timeout")
    _deploy.argocd._add_server_auth cmd "$server" "$auth_token_var" || return $?

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would run: ${cmd[*]}"
        return 0
    fi

    log.info "waiting for argocd app to be healthy: ${app_name} (timeout: ${timeout}s)"
    "${cmd[@]}" || {
        log.error "argocd app wait failed for: ${app_name}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "argocd app is healthy: ${app_name}"
    return 0
}

# ---------------------------------------------------------------------------
# deploy.argocd.rollback
# ---------------------------------------------------------------------------

# Rollback an ArgoCD application.
# Usage: deploy.argocd.rollback --app <name> [--revision <rev>]
#        [--server <url>] [--auth-token-var <VAR>] [--dry-run]
deploy.argocd.rollback() {
    local app_name="" revision="" server="" auth_token_var=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --app)            app_name="$2";       shift 2 ;;
            --revision)       revision="$2";       shift 2 ;;
            --server)         server="$2";         shift 2 ;;
            --auth-token-var) auth_token_var="$2"; shift 2 ;;
            --dry-run)        dry_run="true";      shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    _deploy.argocd._validate_app_name "$app_name" || return $?

    runtime.require_tool argocd || return "$BRIK_EXIT_MISSING_DEP"

    local -a cmd=(argocd app rollback "$app_name")
    [[ -n "$revision" ]] && cmd+=("$revision")
    _deploy.argocd._add_server_auth cmd "$server" "$auth_token_var" || return $?

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would run: ${cmd[*]}"
        return 0
    fi

    log.info "rolling back argocd app: ${app_name}"
    "${cmd[@]}" || {
        log.error "argocd app rollback failed for: ${app_name}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "argocd rollback completed: ${app_name}"
    return 0
}

# ---------------------------------------------------------------------------
# deploy.argocd.diff
# ---------------------------------------------------------------------------

# Show the diff between the live state and the desired state.
# Usage: deploy.argocd.diff --app <name> [--server <url>] [--auth-token-var <VAR>]
# Returns 0 if no diff, 1 if diff exists.
deploy.argocd.diff() {
    local app_name="" server="" auth_token_var=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --app)            app_name="$2";       shift 2 ;;
            --server)         server="$2";         shift 2 ;;
            --auth-token-var) auth_token_var="$2"; shift 2 ;;
            --dry-run)        dry_run="true";      shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    _deploy.argocd._validate_app_name "$app_name" || return $?

    runtime.require_tool argocd || return "$BRIK_EXIT_MISSING_DEP"

    local -a cmd=(argocd app diff "$app_name")
    _deploy.argocd._add_server_auth cmd "$server" "$auth_token_var" || return $?

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would run: ${cmd[*]}"
        return 0
    fi

    log.info "checking diff for argocd app: ${app_name}"
    "${cmd[@]}"
    return $?
}

# ---------------------------------------------------------------------------
# deploy.argocd.status
# ---------------------------------------------------------------------------

# Get the status of an ArgoCD application as JSON on stdout.
# Usage: deploy.argocd.status --app <name> [--server <url>] [--auth-token-var <VAR>]
# stdout: JSON {health_status, sync_status, revision, message}
deploy.argocd.status() {
    local app_name="" server="" auth_token_var=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --app)            app_name="$2";       shift 2 ;;
            --server)         server="$2";         shift 2 ;;
            --auth-token-var) auth_token_var="$2"; shift 2 ;;
            --dry-run)        dry_run="true";      shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    _deploy.argocd._validate_app_name "$app_name" || return $?

    runtime.require_tool argocd || return "$BRIK_EXIT_MISSING_DEP"
    runtime.require_tool jq     || return "$BRIK_EXIT_MISSING_DEP"

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would run: argocd app get ${app_name} -o json"
        return 0
    fi

    local -a cmd=(argocd app get "$app_name" -o json)
    _deploy.argocd._add_server_auth cmd "$server" "$auth_token_var" || return $?

    log.info "getting status for argocd app: ${app_name}"
    local raw_json
    raw_json=$("${cmd[@]}") || {
        log.error "argocd app get failed for: ${app_name}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    printf '%s' "$raw_json" | jq -r '{
        health_status: .status.health.status,
        sync_status: .status.sync.status,
        revision: .status.sync.revision,
        message: (.status.conditions // [] | map(.message) | join("; "))
    }' || {
        log.error "failed to parse argocd status JSON"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    return 0
}

# ---------------------------------------------------------------------------
# deploy.argocd.is_synced
# ---------------------------------------------------------------------------

# Boolean wrapper: returns 0 if app is Healthy+Synced, 1 otherwise.
# Designed as --check-fn for deploy.gitops.wait_sync.
# Usage: deploy.argocd.is_synced --app <name> [--server <url>] [--auth-token-var <VAR>]
deploy.argocd.is_synced() {
    local app_name="" server="" auth_token_var=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --app)            app_name="$2";       shift 2 ;;
            --server)         server="$2";         shift 2 ;;
            --auth-token-var) auth_token_var="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    _deploy.argocd._validate_app_name "$app_name" || return $?

    local -a status_args=(--app "$app_name")
    [[ -n "$server" ]] && status_args+=(--server "$server")
    [[ -n "$auth_token_var" ]] && status_args+=(--auth-token-var "$auth_token_var")

    local json
    json=$(deploy.argocd.status "${status_args[@]}") || return $?

    local health sync_st
    health=$(printf '%s' "$json" | jq -r '.health_status') || return "$BRIK_EXIT_EXTERNAL_FAIL"
    sync_st=$(printf '%s' "$json" | jq -r '.sync_status') || return "$BRIK_EXIT_EXTERNAL_FAIL"

    if [[ "$health" == "Healthy" && "$sync_st" == "Synced" ]]; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# deploy.argocd.deploy
# ---------------------------------------------------------------------------

# High-level compose function: push_manifests + sync + wait_healthy.
# Usage: deploy.argocd.deploy --app <name> --repo <url> --branch <branch>
#        --path <target> --source <rendered> [--git-token-var <VAR>]
#        [--server <url>] [--auth-token-var <VAR>] [--timeout <s>] [--dry-run]
deploy.argocd.deploy() {
    local app_name="" repo="" branch="" target_path="" source_dir=""
    local git_token_var="" server="" auth_token_var=""
    local timeout=300
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --app)            app_name="$2";       shift 2 ;;
            --repo)           repo="$2";           shift 2 ;;
            --branch)         branch="$2";         shift 2 ;;
            --path)           target_path="$2";    shift 2 ;;
            --source)         source_dir="$2";     shift 2 ;;
            --git-token-var)  git_token_var="$2";  shift 2 ;;
            --server)         server="$2";         shift 2 ;;
            --auth-token-var) auth_token_var="$2"; shift 2 ;;
            --timeout)        timeout="$2";        shift 2 ;;
            --dry-run)        dry_run="true";      shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    _deploy.argocd._validate_app_name "$app_name" || return $?

    if [[ -z "$repo" ]]; then
        log.error "repo is required (--repo)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -z "$branch" ]]; then
        log.error "branch is required (--branch)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -z "$target_path" ]]; then
        log.error "path is required (--path)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -z "$source_dir" ]]; then
        log.error "source is required (--source)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local -a common_args=()
    [[ "$dry_run" == "true" ]] && common_args+=(--dry-run)

    # Step 1: Push manifests to config repo
    local tag="${BRIK_DEPLOY_IMAGE_TAG:-${BRIK_TAG:-${BRIK_COMMIT_SHA:-unknown}}}"
    local -a push_args=(
        --repo "$repo"
        --branch "$branch"
        --path "$target_path"
        --source "$source_dir"
        --message "deploy: update ${app_name} to ${tag}"
    )
    [[ -n "$git_token_var" ]] && push_args+=(--git-token-var "$git_token_var")

    brik.use deploy.gitops
    deploy.gitops.push_manifests "${push_args[@]}" "${common_args[@]}" || return $?

    # Step 2: Sync ArgoCD application
    local -a sync_args=(--app "$app_name")
    [[ -n "$server" ]] && sync_args+=(--server "$server")
    [[ -n "$auth_token_var" ]] && sync_args+=(--auth-token-var "$auth_token_var")

    deploy.argocd.sync "${sync_args[@]}" "${common_args[@]}" || return $?

    # Step 3: Wait for healthy
    local -a wait_args=(--app "$app_name" --timeout "$timeout")
    [[ -n "$server" ]] && wait_args+=(--server "$server")
    [[ -n "$auth_token_var" ]] && wait_args+=(--auth-token-var "$auth_token_var")

    deploy.argocd.wait_healthy "${wait_args[@]}" "${common_args[@]}" || return $?

    log.info "argocd deployment completed: ${app_name}"
    return 0
}

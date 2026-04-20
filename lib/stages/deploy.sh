#!/usr/bin/env bash
# @module stages/deploy
# @description Deploy stage - deploy to target environments.

# Deploy stage: iterate over configured environments and deploy.
# Usage: stages.deploy <context_file>
stages.deploy() {
    local context_file="$1"

    config.export_deploy_vars

    brik.use deploy
    brik.use conditions
    brik.use transverse.env

    log.info "deploy stage"

    if [[ -z "${BRIK_DEPLOY_ENVIRONMENTS:-}" ]]; then
        log.info "no deploy environments configured"
        context.set "$context_file" "BRIK_DEPLOY_STATUS" "skipped"
        return 0
    fi

    local env_name upper_env
    local deploy_failed=0

    while IFS= read -r env_name; do
        [[ -z "$env_name" ]] && continue
        upper_env="$(printf '%s' "$env_name" | tr '[:lower:]-' '[:upper:]_')"

        local target_var="BRIK_DEPLOY_${upper_env}_TARGET"
        local namespace_var="BRIK_DEPLOY_${upper_env}_NAMESPACE"
        local manifest_var="BRIK_DEPLOY_${upper_env}_MANIFEST"
        local when_var="BRIK_DEPLOY_${upper_env}_WHEN"
        local repo_var="BRIK_DEPLOY_${upper_env}_REPO"
        local path_var="BRIK_DEPLOY_${upper_env}_PATH"
        local controller_var="BRIK_DEPLOY_${upper_env}_CONTROLLER"
        local app_name_var="BRIK_DEPLOY_${upper_env}_APP_NAME"
        local chart_var="BRIK_DEPLOY_${upper_env}_CHART"
        local release_name_var="BRIK_DEPLOY_${upper_env}_RELEASE_NAME"
        local values_var="BRIK_DEPLOY_${upper_env}_VALUES"
        local host_var="BRIK_DEPLOY_${upper_env}_HOST"
        local compose_file_var="BRIK_DEPLOY_${upper_env}_COMPOSE_FILE"
        local remote_path_var="BRIK_DEPLOY_${upper_env}_REMOTE_PATH"
        local source_var="BRIK_DEPLOY_${upper_env}_SOURCE"
        local restart_cmd_var="BRIK_DEPLOY_${upper_env}_RESTART_CMD"

        # Load per-env env_file (brik.yml .deploy.environments.<env>.env_file) if set.
        # Existing env vars take precedence over file entries (CI precedence).
        transverse.env.load_deploy_env "$env_name" || {
            log.error "failed to load env_file for '$env_name'"
            ((deploy_failed++))
            continue
        }

        local target when_cond
        target="$(transverse.env.resolve_indirect "$target_var")"
        when_cond="$(transverse.env.resolve_indirect "$when_var")"

        if [[ -z "$target" ]]; then
            log.error "environment '$env_name' has no target configured in brik.yml"
            ((deploy_failed++))
            continue
        fi

        # Evaluate deploy condition if set
        if [[ -n "$when_cond" ]]; then
            if ! conditions.eval "$when_cond"; then
                log.info "skipping $env_name (condition not met: $when_cond)"
                continue
            fi
        fi

        log.info "deploying to $env_name (target=$target)"

        local deploy_args=(--target "$target" --env "$env_name")
        local _v
        _v="$(transverse.env.resolve_indirect "$namespace_var")";    [[ -n "$_v" ]] && deploy_args+=(--namespace "$_v")
        _v="$(transverse.env.resolve_indirect "$manifest_var")";     [[ -n "$_v" ]] && deploy_args+=(--manifest "$_v")
        _v="$(transverse.env.resolve_indirect "$repo_var")";         [[ -n "$_v" ]] && deploy_args+=(--repo "$_v")
        _v="$(transverse.env.resolve_indirect "$path_var")";         [[ -n "$_v" ]] && deploy_args+=(--path "$_v")
        _v="$(transverse.env.resolve_indirect "$controller_var")";   [[ -n "$_v" ]] && deploy_args+=(--controller "$_v")
        _v="$(transverse.env.resolve_indirect "$app_name_var")";     [[ -n "$_v" ]] && deploy_args+=(--app-name "$_v")
        _v="$(transverse.env.resolve_indirect "$chart_var")";        [[ -n "$_v" ]] && deploy_args+=(--chart "$_v")
        _v="$(transverse.env.resolve_indirect "$release_name_var")"; [[ -n "$_v" ]] && deploy_args+=(--release "$_v")
        _v="$(transverse.env.resolve_indirect "$values_var")";       [[ -n "$_v" ]] && deploy_args+=(--values "$_v")
        _v="$(transverse.env.resolve_indirect "$host_var")";         [[ -n "$_v" ]] && deploy_args+=(--host "$_v")
        _v="$(transverse.env.resolve_indirect "$compose_file_var")"; [[ -n "$_v" ]] && deploy_args+=(--file "$_v")
        _v="$(transverse.env.resolve_indirect "$remote_path_var")";  [[ -n "$_v" ]] && deploy_args+=(--path "$_v")
        _v="$(transverse.env.resolve_indirect "$source_var")";       [[ -n "$_v" ]] && deploy_args+=(--source "$_v")
        _v="$(transverse.env.resolve_indirect "$restart_cmd_var")";  [[ -n "$_v" ]] && deploy_args+=(--restart-cmd "$_v")

        deploy.run "${deploy_args[@]}" || ((deploy_failed++))
    done <<< "$BRIK_DEPLOY_ENVIRONMENTS"

    if [[ $deploy_failed -gt 0 ]]; then
        context.set "$context_file" "BRIK_DEPLOY_STATUS" "failed"
        return "$BRIK_EXIT_FAILURE"
    fi

    context.set "$context_file" "BRIK_DEPLOY_STATUS" "success"
    return 0
}

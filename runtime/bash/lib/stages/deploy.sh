#!/usr/bin/env bash
# @module stages/deploy
# @description Deploy stage - deploy to target environments.

# Deploy stage: iterate over configured environments and deploy.
# Usage: stages.deploy <context_file>
stages.deploy() {
    local context_file="$1"

    config.export_deploy_vars

    brik.use deploy
    brik.use condition

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
        local restart_cmd_var="BRIK_DEPLOY_${upper_env}_RESTART_CMD"

        local target="${!target_var:-}"
        local when_cond="${!when_var:-}"

        if [[ -z "$target" ]]; then
            log.error "environment '$env_name' has no target configured in brik.yml"
            ((deploy_failed++))
            continue
        fi

        # Evaluate deploy condition if set
        if [[ -n "$when_cond" ]]; then
            if ! condition.eval "$when_cond"; then
                log.info "skipping $env_name (condition not met: $when_cond)"
                continue
            fi
        fi

        log.info "deploying to $env_name (target=$target)"

        local deploy_args=(--target "$target" --env "$env_name")
        [[ -n "${!namespace_var:-}" ]] && deploy_args+=(--namespace "${!namespace_var}")
        [[ -n "${!manifest_var:-}" ]] && deploy_args+=(--manifest "${!manifest_var}")
        [[ -n "${!repo_var:-}" ]] && deploy_args+=(--repo "${!repo_var}")
        [[ -n "${!path_var:-}" ]] && deploy_args+=(--path "${!path_var}")
        [[ -n "${!controller_var:-}" ]] && deploy_args+=(--controller "${!controller_var}")
        [[ -n "${!app_name_var:-}" ]] && deploy_args+=(--app-name "${!app_name_var}")
        [[ -n "${!chart_var:-}" ]] && deploy_args+=(--chart "${!chart_var}")
        [[ -n "${!release_name_var:-}" ]] && deploy_args+=(--release-name "${!release_name_var}")
        [[ -n "${!values_var:-}" ]] && deploy_args+=(--values "${!values_var}")
        [[ -n "${!host_var:-}" ]] && deploy_args+=(--host "${!host_var}")
        [[ -n "${!compose_file_var:-}" ]] && deploy_args+=(--compose-file "${!compose_file_var}")
        [[ -n "${!remote_path_var:-}" ]] && deploy_args+=(--remote-path "${!remote_path_var}")
        [[ -n "${!restart_cmd_var:-}" ]] && deploy_args+=(--restart-cmd "${!restart_cmd_var}")

        deploy.run "${deploy_args[@]}" || ((deploy_failed++))
    done <<< "$BRIK_DEPLOY_ENVIRONMENTS"

    if [[ $deploy_failed -gt 0 ]]; then
        context.set "$context_file" "BRIK_DEPLOY_STATUS" "failed"
        return "$BRIK_EXIT_FAILURE"
    fi

    context.set "$context_file" "BRIK_DEPLOY_STATUS" "success"
    return 0
}

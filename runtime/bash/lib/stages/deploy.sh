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
        upper_env="$(printf '%s' "$env_name" | tr '[:lower:]' '[:upper:]')"

        local target_var="BRIK_DEPLOY_${upper_env}_TARGET"
        local namespace_var="BRIK_DEPLOY_${upper_env}_NAMESPACE"
        local manifest_var="BRIK_DEPLOY_${upper_env}_MANIFEST"
        local when_var="BRIK_DEPLOY_${upper_env}_WHEN"

        local target="${!target_var:-}"
        local when_cond="${!when_var:-}"

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

        deploy.run "${deploy_args[@]}" || ((deploy_failed++))
    done <<< "$BRIK_DEPLOY_ENVIRONMENTS"

    if [[ $deploy_failed -gt 0 ]]; then
        context.set "$context_file" "BRIK_DEPLOY_STATUS" "failed"
        return "$BRIK_EXIT_FAILURE"
    fi

    context.set "$context_file" "BRIK_DEPLOY_STATUS" "success"
    return 0
}

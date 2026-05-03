#!/usr/bin/env bash
# @module stages/deploy
# @description Deploy stage - deploy to target environments.

# Deploy stage: iterate over configured environments and deploy.
# Usage: stages.deploy <context_file>
stages.deploy() {
    # context_file positionally passed by stage.run; unused here after §4.2
    # migration (pipeline.run records tech.status from rc; config-skip path
    # uses report.record directly).
    # shellcheck disable=SC2034
    local context_file="$1"

    # Wrapper for rollout.strategy.run; closes over _deploy_fn and deploy_args
    # via dynamic scoping so rollout.strategy.run receives a no-arg function name.
    _brik.deploy._strategy_wrapper() {
        "$_deploy_fn" "${deploy_args[@]}" "$@"
    }

    config.export_deploy_vars

    brik.use conditions
    brik.use transverse.env

    log.info "deploy stage"

    if [[ -z "${BRIK_DEPLOY_ENVIRONMENTS:-}" ]]; then
        # Silent skip: deploy is gated by the .deploy block presence; when
        # absent, no fragment is emitted so the aggregate keeps no
        # stages[name=deploy] entry.
        log.info "no deploy environments configured - skipping deploy silently"
        return 0
    fi

    # Pipeline-report enrichment (chantier 20260502 L2.C.4). Per-env details
    # (target/strategy/namespace/url, image.deployed/digest, replicas, rollback,
    # gitops.*) are deferred -- they require post-deploy state queries
    # (kubectl, argocd, etc.) that are out of scope for this slice.
    if command -v jq >/dev/null 2>&1; then
        local _envs_arr
        _envs_arr="$(printf '%s' "${BRIK_DEPLOY_ENVIRONMENTS}" \
            | jq -Rsc 'split("\n") | map(select(length > 0))')"
        report.record_object "deploy" "tech" "environments" "$_envs_arr" 2>/dev/null || true
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
        local git_token_var_var="BRIK_DEPLOY_${upper_env}_GIT_TOKEN_VAR"
        local auth_token_var_var="BRIK_DEPLOY_${upper_env}_AUTH_TOKEN_VAR"

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
        _v="$(transverse.env.resolve_indirect "$source_var")";        [[ -n "$_v" ]] && deploy_args+=(--source "$_v")
        _v="$(transverse.env.resolve_indirect "$git_token_var_var")"; [[ -n "$_v" ]] && deploy_args+=(--git-token-var "$_v")
        _v="$(transverse.env.resolve_indirect "$auth_token_var_var")"; [[ -n "$_v" ]] && deploy_args+=(--auth-token-var "$_v")
        _v="$(transverse.env.resolve_indirect "$restart_cmd_var")";  [[ -n "$_v" ]] && deploy_args+=(--restart-cmd "$_v")

        # Inline deploy dispatch: load deployments.<target> + call deploy.<target>.run.
        if ! brik.use "deployments.${target}"; then
            log.error "unsupported deploy target: $target"
            ((deploy_failed++))
            continue
        fi
        local _deploy_fn="deploy.${target}.run"
        if ! declare -f "$_deploy_fn" >/dev/null 2>&1; then
            log.error "deploy function not found: $_deploy_fn"
            ((deploy_failed++))
            continue
        fi
        local strategy_var="BRIK_DEPLOY_${upper_env}_STRATEGY"
        local strategy
        strategy="$(transverse.env.resolve_indirect "$strategy_var")"

        if [[ -n "$strategy" ]]; then
            case "$target" in
                k8s|helm)
                    brik.use rollout.strategy
                    log.info "deploying $env_name with strategy: $strategy"
                    rollout.strategy.run --type "$strategy" \
                        --deploy-fn "_brik.deploy._strategy_wrapper" \
                        || ((deploy_failed++))
                    continue
                    ;;
                ssh|compose)
                    log.debug "strategy '$strategy' ignored for target '$target' (no native primitive)"
                    ;;
            esac
        fi

        log.info "deploying with target: $target"
        "$_deploy_fn" "${deploy_args[@]}" || ((deploy_failed++))
    done <<< "$BRIK_DEPLOY_ENVIRONMENTS"

    if [[ $deploy_failed -gt 0 ]]; then
        return "$BRIK_EXIT_FAILURE"
    fi

    # pipeline.run records tech.status=success from rc (see commit cf719f5).
    return 0
}

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

    # Apply the on_health_failure policy when a deploy attempt fails. 'hold'
    # (the default) leaves the environment on its previous version; 'rollback'
    # reverts the deployment where the target supports it, otherwise holds and
    # says so. This only logs intent and (for rollback) acts -- the caller still
    # records the failure, so a failed deploy is never reported as success.
    _brik.deploy._on_failure() {
        local _env="$1" _target="$2" _uenv="$3" _policy
        _policy="$(transverse.env.resolve_indirect "BRIK_DEPLOY_${_uenv}_ON_HEALTH_FAILURE")"
        [[ -z "$_policy" ]] && _policy="hold"

        if [[ "$_policy" != "rollback" ]]; then
            log.error "deploy of '$_env' failed; holding on the previous version (on_health_failure=hold)"
            return 0
        fi

        case "$_target" in
            gitops)
                # GitOps rolls back by reverting the last config-repo commit so
                # the controller reconciles back to the previous desired state.
                local _repo _path _token
                _repo="$(transverse.env.resolve_indirect "BRIK_DEPLOY_${_uenv}_REPO")"
                _path="$(transverse.env.resolve_indirect "BRIK_DEPLOY_${_uenv}_PATH")"
                _token="$(transverse.env.resolve_indirect "BRIK_DEPLOY_${_uenv}_GIT_TOKEN_VAR")"
                if [[ -z "$_repo" ]]; then
                    log.error "rollback requested for '$_env' but no repo is configured; holding on the previous version"
                    return 0
                fi
                log.warn "deploy of '$_env' failed; rolling back the last config-repo commit"
                brik.use deployments.gitops
                local -a _rb=(--repo "$_repo" --branch main)
                [[ -n "$_path" ]]  && _rb+=(--path "$_path")
                [[ -n "$_token" ]] && _rb+=(--git-token-var "$_token")
                deploy.gitops.rollback "${_rb[@]}" \
                    || log.error "rollback of '$_env' failed; manual intervention required"
                ;;
            *)
                # Push targets have no generic rollback path here, so a rollback
                # request degrades to a hold rather than a silent success.
                log.error "rollback requested for '$_env' but target '$_target' has no rollback path; holding on the previous version"
                ;;
        esac
        return 0
    }

    # Post-deploy read-back: record the resolved digest and, where the target
    # exposes a live query, the actually-deployed digest + match flag.
    # Best-effort, never fails the deploy.
    _brik.deploy._readback() {
        local _env="$1" _target="$2" _uenv="$3" _ctrl
        brik.use deployments.readback 2>/dev/null || return 0
        _ctrl="$(transverse.env.resolve_indirect "BRIK_DEPLOY_${_uenv}_CONTROLLER")"
        deploy.readback.record --env "$_env" --target "$_target" \
            --controller "$_ctrl" 2>/dev/null || true
    }

    config.export_deploy_vars

    # SC20: honour deploy.trigger.{on-tag, on-main, on-feature, manual}.
    # Legacy compat preserved: unconfigured trigger -> always run.
    # Defensive: a test harness stubbing brik.use as a no-op leaves
    # gating.should_run_stage undefined; treat that as "run".
    brik.use transverse.gating 2>/dev/null || true
    if declare -f gating.should_run_stage >/dev/null 2>&1; then
        if ! gating.should_run_stage DEPLOY; then
            log.info "deploy stage skipped: trigger conditions not met"
            report.record "deploy" "tech" "status" "skipped"         2>/dev/null || true
            report.record "deploy" "tech" "kind"   "not-applicable"  2>/dev/null || true
            return 0
        fi
    fi

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

    if command -v jq >/dev/null 2>&1; then
        local _envs_arr
        _envs_arr="$(printf '%s' "${BRIK_DEPLOY_ENVIRONMENTS}" \
            | jq -Rsc 'split("\n") | map(select(length > 0))')"
        report.record_object "deploy" "tech" "environments" "$_envs_arr" 2>/dev/null || true
    fi

    local env_name upper_env
    local deploy_failed=0
    # business.environments[] accumulator: one object per env that actually
    # ran (skipped envs and envs with no target are excluded so consumers
    # see only the work that took place).
    local _business_envs_json="[]"

    while IFS= read -r env_name; do
        [[ -z "$env_name" ]] && continue
        # Explicit CD deploy (brik deploy --environment <e>) targets a single
        # environment; skip all others. The chosen env also bypasses its `when`
        # condition below, because the operator selected it explicitly.
        if [[ -n "${BRIK_DEPLOY_ONLY_ENV:-}" && "$env_name" != "${BRIK_DEPLOY_ONLY_ENV}" ]]; then
            continue
        fi
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

        # Evaluate deploy condition if set. An explicit CD deploy
        # (BRIK_DEPLOY_ONLY_ENV) skips the `when` gate: the operator chose this
        # environment directly, so the event-driven condition does not apply.
        if [[ -z "${BRIK_DEPLOY_ONLY_ENV:-}" && -n "$when_cond" ]]; then
            if ! conditions.eval "$when_cond"; then
                log.info "skipping $env_name (condition not met: $when_cond)"
                continue
            fi
        fi

        log.info "deploying to $env_name (target=$target)"

        # Build the business.environments entry for this env now that we
        # know it will execute. Captured fields are env-var-derived only;
        # post-deploy state (image digest, replicas, URLs, rollback ref)
        # would require kubectl/argocd queries and is left to a future
        # post-deploy hook on each deployments.<target> module.
        if command -v jq >/dev/null 2>&1; then
            local _ns_val _strat_val _env_obj
            _ns_val="$(transverse.env.resolve_indirect "$namespace_var")"
            _strat_val="$(transverse.env.resolve_indirect "BRIK_DEPLOY_${upper_env}_STRATEGY")"
            # The two definition-layer refs resolved by the CD verb: Layer V
            # (the version's tag) and, for an env governed by config_ref, the
            # Layer E commit its config was read at. Recorded for audit and
            # consumed by the P3 DeploymentJournal.
            _env_obj="$(jq -nc \
                --arg name      "$env_name" \
                --arg target    "$target" \
                --arg namespace "$_ns_val" \
                --arg strategy  "$_strat_val" \
                --arg version_ref    "${BRIK_DEPLOY_VERSION_REF:-}" \
                --arg env_config_ref "${BRIK_DEPLOY_ENV_CONFIG_REF:-}" \
                '{name: $name, target: $target, namespace: ( if $namespace != "" then $namespace else null end )}
                 + ( if $strategy != "" then { strategy: $strategy } else {} end )
                 + ( if $version_ref != "" then { version_ref: $version_ref } else {} end )
                 + ( if $env_config_ref != "" then { env_config_ref: $env_config_ref } else {} end )')"
            _business_envs_json="$(jq -nc \
                --argjson arr "$_business_envs_json" \
                --argjson obj "$_env_obj" \
                '$arr + [$obj]')"
        fi

        local deploy_args=(--target "$target" --env "$env_name")
        local _v

        # Referential absorption (T5b/PD3): the deploy environment's binding
        # wires the git/argocd credentials and the argocd controller. Deploy is
        # environment-scoped, so credentials resolve per env (infra.credential_for
        # over the single GitHost/ArgoCD endpoint). The brik.yml git_token_var /
        # auth_token_var / controller fields remain the legacy path without a
        # referential; when present, the referential takes precedence.
        local _ref_git_token_var="" _ref_auth_token_var="" _ref_controller=""
        brik.use transverse.infra 2>/dev/null || true
        if declare -f infra.root >/dev/null 2>&1 && infra.root >/dev/null 2>&1; then
            local _ep _name _cred _tok
            if _ep="$(infra.endpoint_of_kind GitHost 2>/dev/null)"; then
                _name="$(printf '%s' "$_ep" | jq -r '.name')"
                if _cred="$(infra.credential_for "$env_name" "$_name" 2>/dev/null)"; then
                    _tok="$(printf '%s' "$_cred" | jq -r '.token // ""')"
                    [[ -n "$_tok" ]] && _ref_git_token_var="$(infra.env_var_of_ref "$_tok" 2>/dev/null)" || _ref_git_token_var=""
                fi
            fi
            if _ep="$(infra.endpoint_of_kind ArgoCD 2>/dev/null)"; then
                _ref_controller="$(printf '%s' "$_ep" | jq -r '.url // ""')"
                _name="$(printf '%s' "$_ep" | jq -r '.name')"
                if _cred="$(infra.credential_for "$env_name" "$_name" 2>/dev/null)"; then
                    _tok="$(printf '%s' "$_cred" | jq -r '.token // ""')"
                    [[ -n "$_tok" ]] && _ref_auth_token_var="$(infra.env_var_of_ref "$_tok" 2>/dev/null)" || _ref_auth_token_var=""
                fi
            fi
        fi
        # --namespace is only consumed by the k8s/helm/compose targets.
        # gitops and ssh reject unknown options, and a workflow profile injects
        # a k8s-centric `namespace` default into every env -- forwarding it to a
        # gitops/ssh target (selected via a `target:` override) would abort the
        # deploy with "unknown option: --namespace". Filter it to the targets
        # that accept it.
        case "$target" in
            k8s|helm|compose)
                _v="$(transverse.env.resolve_indirect "$namespace_var")"
                [[ -n "$_v" ]] && deploy_args+=(--namespace "$_v")
                ;;
        esac
        _v="$(transverse.env.resolve_indirect "$manifest_var")";     [[ -n "$_v" ]] && deploy_args+=(--manifest "$_v")
        _v="$(transverse.env.resolve_indirect "$repo_var")";         [[ -n "$_v" ]] && deploy_args+=(--repo "$_v")
        _v="$(transverse.env.resolve_indirect "$path_var")";         [[ -n "$_v" ]] && deploy_args+=(--path "$_v")
        _v="$(transverse.env.resolve_indirect "$controller_var")";   [[ -n "$_ref_controller" ]] && _v="$_ref_controller"; [[ -n "$_v" ]] && deploy_args+=(--controller "$_v")
        _v="$(transverse.env.resolve_indirect "$app_name_var")";     [[ -n "$_v" ]] && deploy_args+=(--app-name "$_v")
        _v="$(transverse.env.resolve_indirect "$chart_var")";        [[ -n "$_v" ]] && deploy_args+=(--chart "$_v")
        _v="$(transverse.env.resolve_indirect "$release_name_var")"; [[ -n "$_v" ]] && deploy_args+=(--release "$_v")
        _v="$(transverse.env.resolve_indirect "$values_var")";       [[ -n "$_v" ]] && deploy_args+=(--values "$_v")
        _v="$(transverse.env.resolve_indirect "$host_var")";         [[ -n "$_v" ]] && deploy_args+=(--host "$_v")
        _v="$(transverse.env.resolve_indirect "$compose_file_var")"; [[ -n "$_v" ]] && deploy_args+=(--file "$_v")
        _v="$(transverse.env.resolve_indirect "$remote_path_var")";  [[ -n "$_v" ]] && deploy_args+=(--path "$_v")
        _v="$(transverse.env.resolve_indirect "$source_var")";        [[ -n "$_v" ]] && deploy_args+=(--source "$_v")
        _v="$(transverse.env.resolve_indirect "$git_token_var_var")"; [[ -n "$_ref_git_token_var" ]] && _v="$_ref_git_token_var"; [[ -n "$_v" ]] && deploy_args+=(--git-token-var "$_v")
        _v="$(transverse.env.resolve_indirect "$auth_token_var_var")"; [[ -n "$_ref_auth_token_var" ]] && _v="$_ref_auth_token_var"; [[ -n "$_v" ]] && deploy_args+=(--auth-token-var "$_v")
        _v="$(transverse.env.resolve_indirect "$restart_cmd_var")";  [[ -n "$_v" ]] && deploy_args+=(--restart-cmd "$_v")
        # CD flow: inject the digest-pinned image ref resolved by `brik deploy`
        # so the target deploys exactly that digest (require_digest).
        [[ -n "${BRIK_DEPLOY_IMAGE_REF:-}" ]] && deploy_args+=(--image-ref "${BRIK_DEPLOY_IMAGE_REF}")

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
                    if rollout.strategy.run --type "$strategy" \
                        --deploy-fn "_brik.deploy._strategy_wrapper"; then
                        _brik.deploy._readback "$env_name" "$target" "$upper_env"
                    else
                        _brik.deploy._on_failure "$env_name" "$target" "$upper_env"
                        ((deploy_failed++))
                    fi
                    continue
                    ;;
                gitops)
                    # Pull-based: the GitOps controller reconciles the desired
                    # state, so brik applies no rollout strategy itself. Log it
                    # explicitly instead of silently ignoring the strategy.
                    log.info "strategy '$strategy' n/a for target 'gitops': reconciled by controller"
                    ;;
                ssh|compose)
                    log.debug "strategy '$strategy' ignored for target '$target' (no native primitive)"
                    ;;
            esac
        fi

        log.info "deploying with target: $target"
        if "$_deploy_fn" "${deploy_args[@]}"; then
            _brik.deploy._readback "$env_name" "$target" "$upper_env"
        else
            _brik.deploy._on_failure "$env_name" "$target" "$upper_env"
            ((deploy_failed++))
        fi
    done <<< "$BRIK_DEPLOY_ENVIRONMENTS"

    if command -v jq >/dev/null 2>&1 && [[ "$_business_envs_json" != "[]" ]]; then
        report.record_object "deploy" "business" "environments" "$_business_envs_json" 2>/dev/null || true
    fi

    if [[ $deploy_failed -gt 0 ]]; then
        return "$BRIK_EXIT_FAILURE"
    fi

    return 0
}

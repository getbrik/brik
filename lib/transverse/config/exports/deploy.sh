#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.config.exports.deploy
# @description Exports BRIK_DEPLOY_* variables from brik.yml.

# Guard against double-sourcing
[[ -n "${_BRIK_CONFIG_EXPORTS_DEPLOY_LOADED:-}" ]] && return 0
_BRIK_CONFIG_EXPORTS_DEPLOY_LOADED=1

# _config._export_trigger_vars lives in transverse.config.exports.release;
# deploy shares the helper. brik.use is idempotent (guard-checked).
brik.use transverse.config.exports.release

# Export deploy-related variables from brik.yml.
# Sets: BRIK_DEPLOY_WORKFLOW, BRIK_DEPLOY_ENVIRONMENTS, BRIK_DEPLOY_<ENV>_*
#
# When deploy.workflow is set, the profile defaults are merged with user
# brik.yml overrides before reading environments.
config.export_deploy_vars() {
    # SC20 trigger gating (independent of workflow).
    _config._export_trigger_vars deploy DEPLOY

    # Export workflow if set
    local workflow
    workflow="$(config.get '.deploy.workflow' '' 2>/dev/null)" || workflow=""
    if [[ -n "$workflow" && "$workflow" != "null" ]]; then
        export BRIK_DEPLOY_WORKFLOW="$workflow"

        # Load deploy.profile module and merge profile defaults with user config
        local profile_module="${BRIK_HOME}/lib/rollout/profile.sh"
        if [[ -f "$profile_module" ]]; then
            # shellcheck source=/dev/null
            . "$profile_module"
            local merged_config
            merged_config="$(rollout.profile.merge "$workflow" "${BRIK_CONFIG_FILE:-brik.yml}" 2>/dev/null)" || merged_config=""
            if [[ -n "$merged_config" && -f "$merged_config" ]]; then
                # Temporarily use merged config to read environments
                local orig_config="$BRIK_CONFIG_FILE"
                export BRIK_CONFIG_FILE="$merged_config"
                local exit_code=0
                _config._export_deploy_env_vars || exit_code=$?
                export BRIK_CONFIG_FILE="$orig_config"
                rm -f "$merged_config"
                return $exit_code
            fi
        fi
    fi

    # No workflow mode: read directly from brik.yml (existing behavior)
    _config._export_deploy_env_vars
    return 0
}

# Internal: export BRIK_DEPLOY_ENVIRONMENTS and per-environment variables
# from the current BRIK_CONFIG_FILE.
_config._export_deploy_env_vars() {
    local env_keys
    # optional: deploy section may not exist in brik.yml
    env_keys="$(config.get '.deploy.environments | keys | .[]' '' 2>/dev/null)" || true
    if [[ -z "$env_keys" ]]; then
        export BRIK_DEPLOY_ENVIRONMENTS=""
        return 0
    fi

    export BRIK_DEPLOY_ENVIRONMENTS="$env_keys"

    local env_name upper_env
    while IFS= read -r env_name; do
        [[ -z "$env_name" ]] && continue
        if ! [[ "$env_name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
            log.warn "skipping invalid environment name: $env_name"
            continue
        fi
        upper_env="$(printf '%s' "$env_name" | tr '[:lower:]-' '[:upper:]_')"

        local val
        val="$(config.get ".deploy.environments.${env_name}.target" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_TARGET=$val"

        val="$(config.get ".deploy.environments.${env_name}.namespace" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_NAMESPACE=$val"

        val="$(config.get ".deploy.environments.${env_name}.manifest" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_MANIFEST=$val"

        val="$(config.get ".deploy.environments.${env_name}.when" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_WHEN=$val"

        val="$(config.get ".deploy.environments.${env_name}.repo" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_REPO=$val"

        val="$(config.get ".deploy.environments.${env_name}.path" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_PATH=$val"

        val="$(config.get ".deploy.environments.${env_name}.controller" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_CONTROLLER=$val"

        val="$(config.get ".deploy.environments.${env_name}.app_name" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_APP_NAME=$val"

        # New target-specific fields
        val="$(config.get ".deploy.environments.${env_name}.chart" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_CHART=$val"

        val="$(config.get ".deploy.environments.${env_name}.release_name" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_RELEASE_NAME=$val"

        val="$(config.get ".deploy.environments.${env_name}.values" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_VALUES=$val"

        val="$(config.get ".deploy.environments.${env_name}.host" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_HOST=$val"

        val="$(config.get ".deploy.environments.${env_name}.compose_file" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_COMPOSE_FILE=$val"

        val="$(config.get ".deploy.environments.${env_name}.service" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_SERVICE=$val"

        val="$(config.get ".deploy.environments.${env_name}.remote_path" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_REMOTE_PATH=$val"

        val="$(config.get ".deploy.environments.${env_name}.restart_cmd" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_RESTART_CMD=$val"

        val="$(config.get ".deploy.environments.${env_name}.source" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_SOURCE=$val"

        val="$(config.get ".deploy.environments.${env_name}.git_token_var" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_GIT_TOKEN_VAR=$val"

        val="$(config.get ".deploy.environments.${env_name}.auth_token_var" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_AUTH_TOKEN_VAR=$val"

        val="$(config.get ".deploy.environments.${env_name}.strategy" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_STRATEGY=$val"

        val="$(config.get ".deploy.environments.${env_name}.on_health_failure" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_ON_HEALTH_FAILURE=$val"

        # CD flow (P0): the channel an environment accepts and whether a
        # digest-pinned image ref is mandatory before deploying.
        val="$(config.get ".deploy.environments.${env_name}.accepts_channel" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_CHANNEL=$val"

        val="$(config.get ".deploy.environments.${env_name}.gates.require_digest" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_REQUIRE_DIGEST=$val"

        # Attestation gate: verify the signed attestations on the resolved
        # digest and the provenance expectations (builder identity, source
        # repo) before deploying. The identity/issuer pin the expected signer
        # for keyless verification (the key and kms backends verify with the
        # referential's key instead).
        val="$(config.get ".deploy.environments.${env_name}.gates.require_attestation" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_REQUIRE_ATTESTATION=$val"

        val="$(config.get ".deploy.environments.${env_name}.gates.expected_builder" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_EXPECTED_BUILDER=$val"

        val="$(config.get ".deploy.environments.${env_name}.gates.expected_source" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_EXPECTED_SOURCE=$val"

        # Eligibility gate: the PromotionJournal event types that must all
        # exist for the resolved digest and this environment (all_of).
        val="$(config.get ".deploy.environments.${env_name}.gates.requires_eligibility | join(\",\")" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_REQUIRES_ELIGIBILITY=$val"

        val="$(config.get ".deploy.environments.${env_name}.gates.verify_identity" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_VERIFY_IDENTITY=$val"

        val="$(config.get ".deploy.environments.${env_name}.gates.verify_issuer" '')"
        [[ -n "$val" ]] && export "BRIK_DEPLOY_${upper_env}_VERIFY_ISSUER=$val"
    done <<< "$env_keys"

    return 0
}

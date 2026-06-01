#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.config.exports.hooks
# @description Exports BRIK_HOOK_PRE_* / BRIK_HOOK_POST_* variables from brik.yml.

# Guard against double-sourcing
[[ -n "${_BRIK_CONFIG_EXPORTS_HOOKS_LOADED:-}" ]] && return 0
_BRIK_CONFIG_EXPORTS_HOOKS_LOADED=1

# Stage list driving hook variable export. Prefers the registry
# (registry.stage.list, the single source of truth); falls back to the
# documented fixed flow so hook export still works during early config
# loading, before the registry module has been sourced.
config._hook_stage_list() {
    if declare -f registry.stage.list >/dev/null 2>&1; then
        local _ids
        if _ids="$(registry.stage.list 2>/dev/null)" && [[ -n "$_ids" ]]; then
            printf '%s' "$_ids"
            return 0
        fi
    fi
    printf '%s\n' init release build lint sast scan test package container-scan deploy notify
}

# Export hooks-related variables from brik.yml.
# Sets: BRIK_HOOK_PRE_<STAGE>, BRIK_HOOK_POST_<STAGE>
# Stage ids are normalised to underscore form (container-scan -> container_scan)
# to match brik.yml hook keys and BRIK_HOOK_* variable names.
config.export_hooks_vars() {
    local stages stage stage_key upper_stage val
    mapfile -t stages < <(config._hook_stage_list)
    for stage in "${stages[@]}"; do
        stage_key="${stage//-/_}"
        upper_stage="$(printf '%s' "$stage_key" | tr '[:lower:]' '[:upper:]')"

        val="$(config.get ".hooks.pre_${stage_key}" '')"
        [[ -n "$val" ]] && export "BRIK_HOOK_PRE_${upper_stage}=$val"

        val="$(config.get ".hooks.post_${stage_key}" '')"
        [[ -n "$val" ]] && export "BRIK_HOOK_POST_${upper_stage}=$val"
    done

    return 0
}

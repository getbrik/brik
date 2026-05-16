#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.config.exports.hooks
# @description Exports BRIK_HOOK_PRE_* / BRIK_HOOK_POST_* variables from brik.yml.

# Guard against double-sourcing
[[ -n "${_BRIK_CONFIG_EXPORTS_HOOKS_LOADED:-}" ]] && return 0
_BRIK_CONFIG_EXPORTS_HOOKS_LOADED=1

# Export hooks-related variables from brik.yml.
# Sets: BRIK_HOOK_PRE_<STAGE>, BRIK_HOOK_POST_<STAGE>
config.export_hooks_vars() {
    local stage upper_stage val
    for stage in init release build lint sast scan test package container_scan deploy notify; do
        upper_stage="$(printf '%s' "$stage" | tr '[:lower:]' '[:upper:]')"

        val="$(config.get ".hooks.pre_${stage}" '')"
        [[ -n "$val" ]] && export "BRIK_HOOK_PRE_${upper_stage}=$val"

        val="$(config.get ".hooks.post_${stage}" '')"
        [[ -n "$val" ]] && export "BRIK_HOOK_POST_${upper_stage}=$val"
    done

    return 0
}

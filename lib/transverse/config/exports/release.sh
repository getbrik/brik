#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.config.exports.release
# @description Exports BRIK_RELEASE_* variables from brik.yml.
#
# Hosts _config._export_trigger_vars (private helper) because the release
# stage is the first declarer; package and deploy reuse the same helper
# by depending on this module via brik.use.

# Guard against double-sourcing
[[ -n "${_BRIK_CONFIG_EXPORTS_RELEASE_LOADED:-}" ]] && return 0
_BRIK_CONFIG_EXPORTS_RELEASE_LOADED=1

# Export release-related variables from brik.yml.
# Sets: BRIK_RELEASE_STRATEGY, BRIK_RELEASE_TAG_PREFIX
config.export_release_vars() {
    local strategy
    strategy="$(config.get '.release.strategy' 'semver')"
    export BRIK_RELEASE_STRATEGY="$strategy"

    local tag_prefix
    tag_prefix="$(config.get '.release.tag_prefix' 'v')"
    export BRIK_RELEASE_TAG_PREFIX="$tag_prefix"

    local val
    val="$(config.get '.release.changelog.enabled' 'true')"
    export BRIK_RELEASE_CHANGELOG_ENABLED="$val"

    val="$(config.get '.release.changelog.format' 'conventional')"
    export BRIK_RELEASE_CHANGELOG_FORMAT="$val"

    val="$(config.get '.release.changelog.file' 'CHANGELOG.md')"
    export BRIK_RELEASE_CHANGELOG_FILE="$val"

    # SC20 trigger gating. Only exports when the user has actually
    # written a .release.trigger block: presence drives the CONFIGURED
    # sentinel, which gating.should_run_stage uses to switch from
    # legacy always-run to the new flag-driven behaviour.
    _config._export_trigger_vars release RELEASE

    return 0
}

# Internal: read .<yaml_key>.trigger.{on-tag,on-main,on-feature,manual}
# and export the BRIK_<PREFIX>_TRIGGER_* dotenv. Adds the CONFIGURED
# sentinel only when the block is present in brik.yml.
_config._export_trigger_vars() {
    local yaml_key="$1"   # release|package|deploy
    local prefix="$2"     # RELEASE|PACKAGE|DEPLOY

    local raw_block
    raw_block="$(config.get ".${yaml_key}.trigger" '' 2>/dev/null)" || raw_block=""
    if [[ -z "$raw_block" || "$raw_block" == "null" ]]; then
        return 0
    fi

    local on_tag on_main on_feature manual
    on_tag="$(config.get     ".${yaml_key}.trigger[\"on-tag\"]"     'true')"
    on_main="$(config.get    ".${yaml_key}.trigger[\"on-main\"]"    'false')"
    on_feature="$(config.get ".${yaml_key}.trigger[\"on-feature\"]" 'false')"
    manual="$(config.get     ".${yaml_key}.trigger.manual"          'false')"

    export "BRIK_${prefix}_TRIGGER_CONFIGURED=true"
    export "BRIK_${prefix}_TRIGGER_ON_TAG=${on_tag}"
    export "BRIK_${prefix}_TRIGGER_ON_MAIN=${on_main}"
    export "BRIK_${prefix}_TRIGGER_ON_FEATURE=${on_feature}"
    export "BRIK_${prefix}_TRIGGER_MANUAL=${manual}"
}

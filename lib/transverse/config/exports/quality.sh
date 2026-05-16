#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.config.exports.quality
# @description Exports BRIK_QUALITY_* variables from brik.yml.

# Guard against double-sourcing
[[ -n "${_BRIK_CONFIG_EXPORTS_QUALITY_LOADED:-}" ]] && return 0
_BRIK_CONFIG_EXPORTS_QUALITY_LOADED=1

# Export quality-related variables from brik.yml.
# Sets: BRIK_QUALITY_LINT_TOOL, BRIK_QUALITY_FORMAT_TOOL.
# The legacy BRIK_LINT_ENABLED gate is no longer exported: the stage runs
# unconditionally, business decisions live in the business layer
# (lib/pipeline/business.sh) and the org policy file.
config.export_quality_vars() {
    local stack
    stack="$(config.get '.project.stack' 'auto')"

    local default_lint=""
    local default_format=""
    if [[ "$stack" != "auto" ]]; then
        # optional: stack may not define default quality tools
        default_lint="$(config.stack_default "$stack" "lint_tool" 2>/dev/null || true)"
        default_format="$(config.stack_default "$stack" "format_tool" 2>/dev/null || true)"
    fi

    local lint_tool
    lint_tool="$(config.get '.quality.lint.tool' "$default_lint")"
    export BRIK_QUALITY_LINT_TOOL="$lint_tool"

    local format_tool
    format_tool="$(config.get '.quality.format.tool' "$default_format")"
    export BRIK_QUALITY_FORMAT_TOOL="$format_tool"

    local format_check
    format_check="$(config.get '.quality.format.check' 'false')"
    export BRIK_QUALITY_FORMAT_CHECK="$format_check"

    local lint_config
    lint_config="$(config.get '.quality.lint.config' '')"
    [[ -n "$lint_config" ]] && export BRIK_QUALITY_LINT_CONFIG="$lint_config"

    local lint_fix
    lint_fix="$(config.get '.quality.lint.fix' '')"
    [[ -n "$lint_fix" ]] && export BRIK_QUALITY_LINT_FIX="$lint_fix"

    # Quality command overrides (Tier 1 of 3-tier resolution)
    local lint_cmd
    lint_cmd="$(config.get '.quality.lint.command' '')"
    [[ -n "$lint_cmd" ]] && export BRIK_QUALITY_LINT_COMMAND="$lint_cmd"

    local format_cmd
    format_cmd="$(config.get '.quality.format.command' '')"
    [[ -n "$format_cmd" ]] && export BRIK_QUALITY_FORMAT_COMMAND="$format_cmd"

    # Type check tool and command (Tier 2 / Tier 1)
    local type_check_tool
    type_check_tool="$(config.get '.quality.type_check.tool' '')"
    [[ -n "$type_check_tool" ]] && export BRIK_QUALITY_TYPE_CHECK_TOOL="$type_check_tool"

    local type_check_cmd
    type_check_cmd="$(config.get '.quality.type_check.command' '')"
    [[ -n "$type_check_cmd" ]] && export BRIK_QUALITY_TYPE_CHECK_COMMAND="$type_check_cmd"

    # Findings management policy (chantier 20260508 P1). Schema enum
    # constrains values to pragmatic|strict|permissive; the runtime falls
    # back to pragmatic when the field is absent. BRIK_FINDINGS_EXPIRING_SOON_DAYS
    # is a runtime constant (no brik.yml knob) used by findings.expiring_soon
    # to surface allowlist entries nearing their expiration.
    local findings_policy
    findings_policy="$(config.get '.quality.findings.policy' 'pragmatic')"
    export BRIK_QUALITY_FINDINGS_POLICY="$findings_policy"
    export BRIK_FINDINGS_EXPIRING_SOON_DAYS="${BRIK_FINDINGS_EXPIRING_SOON_DAYS:-30}"

    return 0
}

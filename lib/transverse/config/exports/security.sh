#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.config.exports.security
# @description Exports BRIK_SECURITY_* variables from brik.yml.

# Guard against double-sourcing
[[ -n "${_BRIK_CONFIG_EXPORTS_SECURITY_LOADED:-}" ]] && return 0
_BRIK_CONFIG_EXPORTS_SECURITY_LOADED=1

# Export security-related variables from brik.yml.
# Sets: BRIK_SECURITY_SAST_*, BRIK_SECURITY_DEPS_*, BRIK_SECURITY_SECRETS_*,
#       BRIK_SECURITY_LICENSE_*, BRIK_SECURITY_CONTAINER_*, BRIK_SECURITY_IAC_*,
#       BRIK_SECURITY_SEVERITY_THRESHOLD
config.export_security_vars() {
    # SAST
    local sast_tool; sast_tool="$(config.get '.security.sast.tool' '')"
    [[ -n "$sast_tool" ]] && export BRIK_SECURITY_SAST_TOOL="$sast_tool"
    local sast_ruleset; sast_ruleset="$(config.get '.security.sast.ruleset' '')"
    [[ -n "$sast_ruleset" ]] && export BRIK_SECURITY_SAST_RULESET="$sast_ruleset"
    local sast_cmd; sast_cmd="$(config.get '.security.sast.command' '')"
    [[ -n "$sast_cmd" ]] && export BRIK_SECURITY_SAST_COMMAND="$sast_cmd"
    local sast_output_format; sast_output_format="$(config.get '.security.sast.output_format' '')"
    [[ -n "$sast_output_format" ]] && export BRIK_SECURITY_SAST_OUTPUT_FORMAT="$sast_output_format"
    local sast_output_path; sast_output_path="$(config.get '.security.sast.output_path' '')"
    [[ -n "$sast_output_path" ]] && export BRIK_SECURITY_SAST_OUTPUT_PATH="$sast_output_path"

    # Deps
    local deps_tool; deps_tool="$(config.get '.security.deps.tool' '')"
    [[ -n "$deps_tool" ]] && export BRIK_SECURITY_DEPS_TOOL="$deps_tool"
    local deps_severity; deps_severity="$(config.get '.security.deps.severity' '')"
    [[ -n "$deps_severity" ]] && export BRIK_SECURITY_DEPS_SEVERITY="$deps_severity"
    local deps_cmd; deps_cmd="$(config.get '.security.deps.command' '')"
    [[ -n "$deps_cmd" ]] && export BRIK_SECURITY_DEPS_COMMAND="$deps_cmd"
    local deps_output_path; deps_output_path="$(config.get '.security.deps.output_path' '')"
    [[ -n "$deps_output_path" ]] && export BRIK_SECURITY_DEPS_OUTPUT_PATH="$deps_output_path"
    local sbom_enabled; sbom_enabled="$(config.get '.security.deps.sbom.enabled' '')"
    [[ -n "$sbom_enabled" ]] && export BRIK_SECURITY_DEPS_SBOM_ENABLED="$sbom_enabled"
    local sbom_format; sbom_format="$(config.get '.security.deps.sbom.format' '')"
    [[ -n "$sbom_format" ]] && export BRIK_SECURITY_DEPS_SBOM_FORMAT="$sbom_format"
    local sbom_output_path; sbom_output_path="$(config.get '.security.deps.sbom.output_path' '')"
    [[ -n "$sbom_output_path" ]] && export BRIK_SECURITY_DEPS_SBOM_OUTPUT_PATH="$sbom_output_path"

    # Secrets
    local secrets_tool; secrets_tool="$(config.get '.security.secrets.tool' '')"
    [[ -n "$secrets_tool" ]] && export BRIK_SECURITY_SECRETS_TOOL="$secrets_tool"
    local secrets_cmd; secrets_cmd="$(config.get '.security.secrets.command' '')"
    [[ -n "$secrets_cmd" ]] && export BRIK_SECURITY_SECRETS_COMMAND="$secrets_cmd"
    local secrets_output_path; secrets_output_path="$(config.get '.security.secrets.output_path' '')"
    [[ -n "$secrets_output_path" ]] && export BRIK_SECURITY_SECRETS_OUTPUT_PATH="$secrets_output_path"

    # License
    local license_allowed; license_allowed="$(config.get '.security.license.allowed' '')"
    [[ -n "$license_allowed" ]] && export BRIK_SECURITY_LICENSE_ALLOWED="$license_allowed"
    local license_denied; license_denied="$(config.get '.security.license.denied' '')"
    [[ -n "$license_denied" ]] && export BRIK_SECURITY_LICENSE_DENIED="$license_denied"

    # Container
    local container_image; container_image="$(config.get '.security.container.image' '')"
    [[ -n "$container_image" ]] && export BRIK_SECURITY_CONTAINER_IMAGE="$container_image"
    local container_severity; container_severity="$(config.get '.security.container.severity' '')"
    [[ -n "$container_severity" ]] && export BRIK_SECURITY_CONTAINER_SEVERITY="$container_severity"

    # IaC
    local iac_tool; iac_tool="$(config.get '.security.iac.tool' '')"
    [[ -n "$iac_tool" ]] && export BRIK_SECURITY_IAC_TOOL="$iac_tool"
    local iac_cmd; iac_cmd="$(config.get '.security.iac.command' '')"
    [[ -n "$iac_cmd" ]] && export BRIK_SECURITY_IAC_COMMAND="$iac_cmd"

    # Global threshold
    local threshold; threshold="$(config.get '.security.severity_threshold' 'high')"
    export BRIK_SECURITY_SEVERITY_THRESHOLD="$threshold"

    return 0
}

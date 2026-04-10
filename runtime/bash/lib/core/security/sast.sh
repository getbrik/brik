#!/usr/bin/env bash
# @module security.sast
# @uses quality._tools security._scan
# @description Security-focused Static Application Security Testing.
# 3-tier resolution: BRIK_SECURITY_SAST_COMMAND > BRIK_SECURITY_SAST_TOOL > auto-detect

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_SECURITY_SAST_LOADED:-}" ]] && return 0
_BRIK_CORE_SECURITY_SAST_LOADED=1

# Load tool registry and common scan helper
brik.use "quality._tools"
brik.use "security._scan"

# Register security SAST scanners
# Default template; overridden below when BRIK_SECURITY_SAST_RULESET is set
quality.tool.register sec_sast semgrep semgrep "semgrep scan --config auto ." 10

# Run SAST scan on a workspace.
# Usage: security.sast.run <workspace>
security.sast.run() {
    local workspace="$1"
    runtime.require_dir "$workspace" || return 6

    # If a custom ruleset is configured, re-register semgrep with it
    if [[ -n "${BRIK_SECURITY_SAST_RULESET:-}" ]]; then
        quality.tool.register sec_sast semgrep semgrep \
            "semgrep scan --config ${BRIK_SECURITY_SAST_RULESET} ." 10
    fi

    _security._run_scan sec_sast BRIK_SECURITY_SAST_COMMAND BRIK_SECURITY_SAST_TOOL \
        "$workspace" "SAST"
}

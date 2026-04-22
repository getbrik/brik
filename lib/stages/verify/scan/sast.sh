#!/usr/bin/env bash
# @module verify.scan.sast
# @uses transverse.tools verify._scan
# @description Security-focused Static Application Security Testing.
# 3-tier resolution: BRIK_SECURITY_SAST_COMMAND > BRIK_SECURITY_SAST_TOOL > auto-detect

# Guard against double-sourcing
[[ -n "${_BRIK_VERIFY_SCAN_SAST_LOADED:-}" ]] && return 0
_BRIK_VERIFY_SCAN_SAST_LOADED=1

# Load tool registry and common scan helper
brik.use transverse.tools
brik.use verify.scan._scan

# Register security SAST scanners
# Default template; overridden below when BRIK_SECURITY_SAST_RULESET is set
transverse.tools.register sec_sast semgrep semgrep "semgrep scan --config auto ." 10

# Run SAST scan on a workspace.
# Usage: verify.scan.sast.run <workspace>
verify.scan.sast.run() {
    local workspace="$1"
    pipeline.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    # If a custom ruleset is configured, re-register semgrep with it
    if [[ -n "${BRIK_SECURITY_SAST_RULESET:-}" ]]; then
        transverse.tools.register sec_sast semgrep semgrep \
            "semgrep scan --config ${BRIK_SECURITY_SAST_RULESET} ." 10
    fi

    _verify._scan._run sec_sast BRIK_SECURITY_SAST_COMMAND BRIK_SECURITY_SAST_TOOL \
        "$workspace" "SAST"
}

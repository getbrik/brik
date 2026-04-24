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

# Build the semgrep command line based on the configured ruleset and severity.
# semgrep scan exits 0 by default even when findings exist; --error makes it
# exit non-zero so the stage can surface security issues. --severity bounds
# which findings count as blocking. Setting BRIK_SECURITY_SAST_SEVERITY=ALL
# disables the severity filter so any finding (INFO/WARNING/ERROR) blocks.
_verify.scan.sast._build_command() {
    local ruleset="${BRIK_SECURITY_SAST_RULESET:-auto}"
    local severity="${BRIK_SECURITY_SAST_SEVERITY:-ERROR}"
    if [[ "$severity" == "ALL" ]]; then
        printf 'semgrep scan --error --config %s .' "$ruleset"
    else
        printf 'semgrep scan --error --severity %s --config %s .' "$severity" "$ruleset"
    fi
}

# Run SAST scan on a workspace.
# Usage: verify.scan.sast.run <workspace>
# The semgrep command is registered just-in-time so per-run env overrides
# of ruleset/severity take effect (a load-time register would freeze the
# defaults that were in scope at source time).
verify.scan.sast.run() {
    local workspace="$1"
    pipeline.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    transverse.tools.register sec_sast semgrep semgrep \
        "$(_verify.scan.sast._build_command)" 10

    _verify._scan._run sec_sast BRIK_SECURITY_SAST_COMMAND BRIK_SECURITY_SAST_TOOL \
        "$workspace" "SAST"
}

#!/usr/bin/env bash
# @module security.secret_scan
# @uses quality._tools security._scan
# @description Security-focused secret scanning.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_SECURITY_SECRET_SCAN_LOADED:-}" ]] && return 0
_BRIK_CORE_SECURITY_SECRET_SCAN_LOADED=1

# Load tool registry and common scan helper
brik.use "quality._tools"
brik.use "security._scan"

# Register security secret scanners
quality.tool.register sec_secret gitleaks  gitleaks  "gitleaks detect --source ."  10
quality.tool.register sec_secret trufflehog trufflehog "trufflehog filesystem ."   20

# Run security secret scan on a workspace.
# Usage: security.secret_scan.run <workspace>
security.secret_scan.run() {
    local workspace="$1"
    runtime.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"
    _security._run_scan sec_secret BRIK_SECURITY_SECRETS_COMMAND BRIK_SECURITY_SECRETS_TOOL \
        "$workspace" "security secret scan"
}

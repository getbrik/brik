#!/usr/bin/env bash
# @module verify.scan.secret
# @uses verify._tools verify._scan
# @description Security-focused secret scanning.

# Guard against double-sourcing
[[ -n "${_BRIK_VERIFY_SCAN_SECRET_LOADED:-}" ]] && return 0
_BRIK_VERIFY_SCAN_SECRET_LOADED=1

# Load tool registry and common scan helper
brik.use verify._tools
brik.use verify.scan._scan

# Register security secret scanners
verify.tool.register sec_secret gitleaks  gitleaks  "gitleaks detect --source ."  10
verify.tool.register sec_secret trufflehog trufflehog "trufflehog filesystem ."   20

# Run security secret scan on a workspace.
# Usage: verify.scan.secret.run <workspace>
verify.scan.secret.run() {
    local workspace="$1"
    pipeline.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"
    _verify._scan._run sec_secret BRIK_SECURITY_SECRETS_COMMAND BRIK_SECURITY_SECRETS_TOOL \
        "$workspace" "security secret scan"
}

#!/usr/bin/env bash
# @module security._scan
# @description Common 3-tier scan execution helper for security modules.
# Factorizes the command-override / tool-resolve / auto-detect pattern.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_SECURITY_SCAN_LOADED:-}" ]] && return 0
_BRIK_CORE_SECURITY_SCAN_LOADED=1

# Execute a security scan using the 3-tier resolution pattern.
# Tier 1: command override (env var) -> eval directly
# Tier 2: explicit tool selection -> resolve via registry
# Tier 3: auto-detect best available tool -> resolve via registry
#
# Usage: _security._run_scan <category> <command_var> <tool_var> <workspace> <label>
#   category    - tool registry category (e.g. sec_secret, sec_sast, sec_deps)
#   command_var - name of the BRIK_SECURITY_*_COMMAND env var
#   tool_var    - name of the BRIK_SECURITY_*_TOOL env var
#   workspace   - project workspace directory
#   label       - human-readable scan label for log messages
#
# Returns: 0 on pass, 3 if tool missing, 7 if unknown tool, 10 on findings
_security._run_scan() {
    local category="$1"
    local command_var="$2"
    local tool_var="$3"
    local workspace="$4"
    local label="$5"

    # Tier 1: command override
    local command_override="${!command_var:-}"
    if [[ -n "$command_override" ]]; then
        log.info "$label (command override): $command_override"
        (cd "$workspace" && eval "$command_override") || {
            log.error "$label findings detected"
            return "$BRIK_EXIT_CHECK_FAILED"
        }
        log.info "$label passed"
        return 0
    fi

    # Tier 2+3: resolve via tool registry
    local tool="${!tool_var:-}"
    local resolve_args=("$category")
    [[ -n "$tool" ]] && resolve_args+=(--tool "$tool")

    local resolved rc=0
    resolved="$(quality.tool.resolve "${resolve_args[@]}")" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        if [[ $rc -eq 3 ]]; then
            log.error "${tool} not found"
            return "$BRIK_EXIT_MISSING_DEP"
        elif [[ $rc -eq 7 ]]; then
            log.error "unknown $label tool: ${tool}"
            return "$BRIK_EXIT_CONFIG_ERROR"
        fi
        log.warn "no $label tool available - skipping"
        return 0
    fi

    log.info "$label with $resolved"
    (cd "$workspace" && quality.tool.exec "$category" "$resolved") || {
        log.error "$label findings detected"
        return "$BRIK_EXIT_CHECK_FAILED"
    }

    log.info "$label passed"
    return 0
}

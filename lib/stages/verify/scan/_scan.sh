#!/usr/bin/env bash
# @module verify.scan._scan
# @description Common 3-tier scan execution helper for security modules.
# Factorizes the command-override / tool-resolve / auto-detect pattern.

# Guard against double-sourcing
[[ -n "${_BRIK_VERIFY_SCAN_SCAN_LOADED:-}" ]] && return 0
_BRIK_VERIFY_SCAN_SCAN_LOADED=1

# Execute a security scan using the 3-tier resolution pattern.
# Tier 1: command override (env var) -> eval directly
# Tier 2: explicit tool selection -> resolve via registry
# Tier 3: auto-detect best available tool -> resolve via registry
#
# Usage: _verify._scan._run <category> <command_var> <tool_var> <workspace> <label>
#   category    - tool registry category (e.g. sec_secret, sec_sast, sec_deps)
#   command_var - name of the BRIK_SECURITY_*_COMMAND env var
#   tool_var    - name of the BRIK_SECURITY_*_TOOL env var
#   workspace   - project workspace directory
#   label       - human-readable scan label for log messages
#
# Returns: 0 on pass, 3 if tool missing, 7 if unknown tool, 10 on findings
_verify._scan._run() {
    local category="$1"
    local command_var="$2"
    local tool_var="$3"
    local workspace="$4"
    local label="$5"

    # Tier 1: command override
    brik.use transverse.env
    local command_override
    command_override="$(transverse.env.resolve_indirect "$command_var")"
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
    local tool
    tool="$(transverse.env.resolve_indirect "$tool_var")"
    local resolve_args=("$category")
    [[ -n "$tool" ]] && resolve_args+=(--tool "$tool")

    local resolved rc=0
    resolved="$(transverse.tools.resolve "${resolve_args[@]}")" || rc=$?
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
    (cd "$workspace" && transverse.tools.exec "$category" "$resolved") || {
        log.error "$label findings detected"
        return "$BRIK_EXIT_CHECK_FAILED"
    }

    log.info "$label passed"
    return 0
}

# Stamp tech.tool_error=true on report stage $1 when a SARIF-emitting scanner
# failed ($3 != 0) without producing a valid SARIF at $2 -- i.e. it crashed
# before reporting, rather than finding real issues. This lets the report
# renderers surface a "scanner error" instead of a misleading threshold breach
# or a deceptive "0 findings". No-op when a valid SARIF exists (real findings
# were reported) or when the tool exited cleanly. Best-effort: report.record
# failures are swallowed so this never alters the caller's verdict.
#
# Usage: _verify.scan._flag_tool_error <report_stage> <sarif_path> <tool_rc>
_verify.scan._flag_tool_error() {
    local report_stage="$1" sarif="$2" tool_rc="$3"
    [[ "$tool_rc" -ne 0 ]] || return 0
    if [[ -f "$sarif" ]] && command -v jq >/dev/null 2>&1 \
       && jq -e 'has("runs")' "$sarif" >/dev/null 2>&1; then
        return 0
    fi
    report.record "$report_stage" "tech" "tool_error" "true" 2>/dev/null || true
}

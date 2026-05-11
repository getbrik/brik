#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.severity
# @description Normalize tool-native severity scales onto the canonical
#   Brik 5-bucket scale {critical, high, medium, low, info} and answer
#   whether the tool itself treats the finding as blocking.
#
# Tool ownership lives in this module so that the rest of the pipeline
# (business.evaluate, exporters, aggregate-report) can compare findings
# uniformly. Per-tool mappings:
#
#   eslint        : 2/error -> high blocking, 1/warn -> low non-blocking,
#                   else info non-blocking
#   ruff          : E*/F*/error -> high blocking, W*/warning -> low
#                   non-blocking, else info non-blocking
#   checkstyle    : error -> high blocking, warning -> low non-blocking,
#                   info/ignore -> info non-blocking
#   dotnet-format : error -> high blocking, warning -> low non-blocking,
#                   info/silent/hidden/suggestion -> info non-blocking
#   semgrep       : ERROR -> high blocking, WARNING -> medium non-blocking,
#                   INFO -> info non-blocking
#   grype         : Critical/High -> blocking, Medium/Low -> non-blocking,
#                   Negligible/Unknown -> info
#   osv-scanner   : CRITICAL/HIGH -> blocking, MODERATE/LOW -> non-blocking
#   gitleaks      : every finding is a leaked secret -> high blocking
#
# Any other tool falls back to the SARIF level vocabulary
# (error/warning/note/none) augmented with the canonical bucket names.

# Guard against double-sourcing
[[ -n "${_BRIK_SEVERITY_LOADED:-}" ]] && return 0
_BRIK_SEVERITY_LOADED=1

# Lowercase a string without spawning tr (faster, no IO dep).
_severity._lower() {
    local s="$1"
    printf '%s' "${s,,}"
}

# Generic fallback that handles SARIF level vocabulary plus the canonical
# Brik bucket names. Used when the tool dispatch did not produce a match.
_severity._generic() {
    local sev_lc="$1"
    case "$sev_lc" in
        critical) printf 'critical' ;;
        error|high) printf 'high' ;;
        warning|medium) printf 'medium' ;;
        note|low) printf 'low' ;;
        none|info|"") printf 'info' ;;
        *) printf 'info' ;;
    esac
}

# severity.normalize <tool> <tool_severity>
# Print the canonical 5-bucket Brik severity to stdout (rc=0).
severity.normalize() {
    local tool="${1:-}"
    local sev="${2:-}"
    local sev_lc; sev_lc="$(_severity._lower "$sev")"

    case "$tool" in
        eslint)
            case "$sev_lc" in
                error|2) printf 'high' ;;
                warn|warning|1) printf 'low' ;;
                *) printf 'info' ;;
            esac
            ;;
        ruff)
            case "$sev_lc" in
                error) printf 'high' ;;
                warning) printf 'low' ;;
                note|info) printf 'info' ;;
                "") printf 'info' ;;
                e[0-9]*|f[0-9]*) printf 'high' ;;
                w[0-9]*|i[0-9]*) printf 'low' ;;
                *) printf 'info' ;;
            esac
            ;;
        checkstyle)
            case "$sev_lc" in
                error) printf 'high' ;;
                warning) printf 'low' ;;
                info|ignore|"") printf 'info' ;;
                *) printf 'info' ;;
            esac
            ;;
        dotnet-format)
            case "$sev_lc" in
                error) printf 'high' ;;
                warning) printf 'low' ;;
                info|silent|hidden|suggestion|default|"") printf 'info' ;;
                *) printf 'info' ;;
            esac
            ;;
        semgrep)
            case "$sev_lc" in
                error) printf 'high' ;;
                warning) printf 'medium' ;;
                info|"") printf 'info' ;;
                *) printf 'info' ;;
            esac
            ;;
        grype)
            case "$sev_lc" in
                critical) printf 'critical' ;;
                high) printf 'high' ;;
                medium) printf 'medium' ;;
                low) printf 'low' ;;
                negligible|unknown|"") printf 'info' ;;
                *) printf 'info' ;;
            esac
            ;;
        osv-scanner|osv)
            case "$sev_lc" in
                critical) printf 'critical' ;;
                high) printf 'high' ;;
                moderate|medium) printf 'medium' ;;
                low) printf 'low' ;;
                *) printf 'info' ;;
            esac
            ;;
        gitleaks)
            # Every gitleaks finding is a leaked secret; severity is fixed.
            printf 'high'
            ;;
        *)
            _severity._generic "$sev_lc"
            ;;
    esac
}

# severity.is_tool_blocking <tool> <tool_severity>
# Print "true" if the tool itself treats this severity as blocking by
# default (eslint error, grype critical/high, every gitleaks finding, ...),
# else "false". rc=0 in both cases.
severity.is_tool_blocking() {
    local tool="${1:-}"
    local sev="${2:-}"
    local sev_lc; sev_lc="$(_severity._lower "$sev")"

    case "$tool" in
        eslint)
            case "$sev_lc" in
                error|2) printf 'true' ;;
                *) printf 'false' ;;
            esac
            ;;
        ruff)
            case "$sev_lc" in
                error) printf 'true' ;;
                e[0-9]*|f[0-9]*) printf 'true' ;;
                *) printf 'false' ;;
            esac
            ;;
        checkstyle|dotnet-format)
            case "$sev_lc" in
                error) printf 'true' ;;
                *) printf 'false' ;;
            esac
            ;;
        semgrep)
            case "$sev_lc" in
                error) printf 'true' ;;
                *) printf 'false' ;;
            esac
            ;;
        grype|osv-scanner|osv)
            case "$sev_lc" in
                critical|high) printf 'true' ;;
                *) printf 'false' ;;
            esac
            ;;
        gitleaks)
            printf 'true'
            ;;
        *)
            case "$sev_lc" in
                error|critical|high) printf 'true' ;;
                *) printf 'false' ;;
            esac
            ;;
    esac
}

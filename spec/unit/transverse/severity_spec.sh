#shellcheck shell=bash
# Contract for lib/transverse/severity.sh
#
# The severity module exposes two pure functions:
#
#   severity.normalize <tool> <tool_severity>
#     -> one of {critical, high, medium, low, info}, written to stdout
#
#   severity.is_tool_blocking <tool> <tool_severity>
#     -> "true" or "false" on stdout, with rc=0
#
# Tool-native severity scales differ per tool. The module owns those
# mappings so that the rest of the pipeline can reason in the canonical
# 5-bucket Brik scale (critical/high/medium/low/info) plus a boolean
# "is the tool considering this finding blocking by default".
#
# Tool conventions (per master pipeline-behavior-model sub-chantier 14):
#
#   eslint        : 2/error -> high blocking ; 1/warn -> low non-blocking ;
#                   0/off/anything else -> info non-blocking
#   ruff          : E.../F.../error -> high blocking ;
#                   W.../warning -> low non-blocking ; else info non-blocking
#   checkstyle    : error -> high blocking ; warning -> low non-blocking ;
#                   info/ignore -> info non-blocking
#   dotnet-format : error -> high blocking ; warning -> low non-blocking ;
#                   info/silent/hidden/suggestion -> info non-blocking
#   semgrep       : ERROR -> high blocking ; WARNING -> medium non-blocking ;
#                   INFO -> info non-blocking
#   grype         : Critical -> critical blocking ; High -> high blocking ;
#                   Medium -> medium non-blocking ; Low -> low non-blocking ;
#                   Negligible/Unknown -> info non-blocking
#   osv-scanner   : CRITICAL -> critical blocking ; HIGH -> high blocking ;
#                   MODERATE -> medium non-blocking ; LOW -> low non-blocking
#   gitleaks      : any input -> high blocking (every secret leak is blocking)
#
# Generic fallback for unrecognized tools: maps SARIF level vocabulary
# (error/warning/note/none) and the canonical bucket names back to themselves.
# Unknown severity -> info, non-blocking.

Describe "lib/transverse/severity.sh"
  Include "$BRIK_HOME/lib/transverse/severity.sh"

  Describe "severity.normalize - eslint"
    Parameters
      "error"   "high"
      "2"       "high"
      "warn"    "low"
      "warning" "low"
      "1"       "low"
      "off"     "info"
      "0"       "info"
      ""        "info"
      "unknown" "info"
    End

    It "maps eslint severity '$1' to '$2'"
      When call severity.normalize "eslint" "$1"
      The output should equal "$2"
    End
  End

  Describe "severity.is_tool_blocking - eslint"
    Parameters
      "error" "true"
      "2"     "true"
      "warn"  "false"
      "1"     "false"
      "off"   "false"
      ""      "false"
    End

    It "eslint '$1' blocking -> '$2'"
      When call severity.is_tool_blocking "eslint" "$1"
      The output should equal "$2"
    End
  End

  Describe "severity.normalize - ruff"
    Parameters
      "error"   "high"
      "E501"    "high"
      "F401"    "high"
      "W605"    "low"
      "warning" "low"
      "I001"    "low"
      "note"    "info"
      ""        "info"
    End

    It "maps ruff severity '$1' to '$2'"
      When call severity.normalize "ruff" "$1"
      The output should equal "$2"
    End
  End

  Describe "severity.is_tool_blocking - ruff"
    Parameters
      "E501"    "true"
      "F401"    "true"
      "error"   "true"
      "W605"    "false"
      "warning" "false"
      ""        "false"
    End

    It "ruff '$1' blocking -> '$2'"
      When call severity.is_tool_blocking "ruff" "$1"
      The output should equal "$2"
    End
  End

  Describe "severity.normalize - checkstyle"
    Parameters
      "error"   "high"
      "warning" "low"
      "info"    "info"
      "ignore"  "info"
    End

    It "maps checkstyle severity '$1' to '$2'"
      When call severity.normalize "checkstyle" "$1"
      The output should equal "$2"
    End
  End

  Describe "severity.is_tool_blocking - checkstyle"
    Parameters
      "error"   "true"
      "warning" "false"
      "info"    "false"
      "ignore"  "false"
    End

    It "checkstyle '$1' blocking -> '$2'"
      When call severity.is_tool_blocking "checkstyle" "$1"
      The output should equal "$2"
    End
  End

  Describe "severity.normalize - dotnet-format"
    Parameters
      "error"      "high"
      "warning"    "low"
      "info"       "info"
      "silent"     "info"
      "hidden"     "info"
      "suggestion" "info"
    End

    It "maps dotnet-format severity '$1' to '$2'"
      When call severity.normalize "dotnet-format" "$1"
      The output should equal "$2"
    End
  End

  Describe "severity.is_tool_blocking - dotnet-format"
    Parameters
      "error"   "true"
      "warning" "false"
      "info"    "false"
      "hidden"  "false"
    End

    It "dotnet-format '$1' blocking -> '$2'"
      When call severity.is_tool_blocking "dotnet-format" "$1"
      The output should equal "$2"
    End
  End

  Describe "severity.normalize - semgrep"
    Parameters
      "ERROR"   "high"
      "WARNING" "medium"
      "INFO"    "info"
    End

    It "maps semgrep severity '$1' to '$2'"
      When call severity.normalize "semgrep" "$1"
      The output should equal "$2"
    End
  End

  Describe "severity.is_tool_blocking - semgrep"
    Parameters
      "ERROR"   "true"
      "WARNING" "false"
      "INFO"    "false"
    End

    It "semgrep '$1' blocking -> '$2'"
      When call severity.is_tool_blocking "semgrep" "$1"
      The output should equal "$2"
    End
  End

  Describe "severity.normalize - grype"
    Parameters
      "Critical"   "critical"
      "High"       "high"
      "Medium"     "medium"
      "Low"        "low"
      "Negligible" "info"
      "Unknown"    "info"
    End

    It "maps grype severity '$1' to '$2'"
      When call severity.normalize "grype" "$1"
      The output should equal "$2"
    End
  End

  Describe "severity.is_tool_blocking - grype"
    Parameters
      "Critical"   "true"
      "High"       "true"
      "Medium"     "false"
      "Low"        "false"
      "Negligible" "false"
      "Unknown"    "false"
    End

    It "grype '$1' blocking -> '$2'"
      When call severity.is_tool_blocking "grype" "$1"
      The output should equal "$2"
    End
  End

  Describe "severity.normalize - osv-scanner"
    Parameters
      "CRITICAL" "critical"
      "HIGH"     "high"
      "MODERATE" "medium"
      "LOW"      "low"
    End

    It "maps osv-scanner severity '$1' to '$2'"
      When call severity.normalize "osv-scanner" "$1"
      The output should equal "$2"
    End

    It "accepts the 'osv' alias for severity '$1' -> '$2'"
      When call severity.normalize "osv" "$1"
      The output should equal "$2"
    End
  End

  Describe "severity.is_tool_blocking - osv-scanner"
    Parameters
      "CRITICAL" "true"
      "HIGH"     "true"
      "MODERATE" "false"
      "LOW"      "false"
    End

    It "osv-scanner '$1' blocking -> '$2'"
      When call severity.is_tool_blocking "osv-scanner" "$1"
      The output should equal "$2"
    End
  End

  Describe "severity.normalize - gitleaks"
    Parameters
      "high"     "high"
      "critical" "high"
      ""         "high"
      "unknown"  "high"
    End

    It "maps gitleaks severity '$1' to 'high' (always)"
      When call severity.normalize "gitleaks" "$1"
      The output should equal "$2"
    End
  End

  Describe "severity.is_tool_blocking - gitleaks"
    It "treats every gitleaks finding as blocking"
      When call severity.is_tool_blocking "gitleaks" "anything"
      The output should equal "true"
    End

    It "blocks even when no severity is provided"
      When call severity.is_tool_blocking "gitleaks" ""
      The output should equal "true"
    End
  End

  Describe "severity.normalize - generic fallback"
    Parameters
      "error"    "high"
      "warning"  "medium"
      "note"     "low"
      "none"     "info"
      "critical" "critical"
      "high"     "high"
      "medium"   "medium"
      "low"      "low"
      "info"     "info"
      ""         "info"
      "garbage"  "info"
    End

    It "maps unknown tool with '$1' to '$2'"
      When call severity.normalize "no-such-tool" "$1"
      The output should equal "$2"
    End
  End

  Describe "severity.is_tool_blocking - generic fallback"
    Parameters
      "error"    "true"
      "critical" "true"
      "high"     "true"
      "warning"  "false"
      "medium"   "false"
      "low"      "false"
      "info"     "false"
      "note"     "false"
      ""         "false"
    End

    It "unknown tool with '$1' blocking -> '$2'"
      When call severity.is_tool_blocking "no-such-tool" "$1"
      The output should equal "$2"
    End
  End

  Describe "guard rails"
    It "is idempotent: feeding a canonical bucket back into the generic fallback yields itself"
      When call severity.normalize "" "high"
      The output should equal "high"
    End

    It "returns rc=0 on every well-formed call"
      do_run() {
        severity.normalize "eslint" "error" >/dev/null
      }
      When call do_run
      The status should equal 0
    End
  End
End

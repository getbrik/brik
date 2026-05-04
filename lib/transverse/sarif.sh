#!/usr/bin/env bash
# @module sarif
# @requires jq
# @description Parse SARIF 2.1.0 reports into Brik canonical metrics. SARIF
#   level vocabulary (error/warning/note/none) and per-rule
#   defaultConfiguration.level are mapped to Brik's {critical, high, medium,
#   low, info}. CVSS numeric in properties.security-severity overrides level
#   when present.

# Guard against double-sourcing.
[[ -n "${_BRIK_TRANSVERSE_SARIF_LOADED:-}" ]] && return 0
_BRIK_TRANSVERSE_SARIF_LOADED=1

# Shared jq pipeline that resolves a result's effective severity bucket.
# Reads from the result object plus the rules table; emits one of
# {critical, high, medium, low, info}.
#
# Resolution order:
#   1. result.properties["security-severity"] numeric CVSS, when present.
#   2. result.level when set.
#   3. tool.driver.rules[ruleIndex].defaultConfiguration.level when result has
#      a valid ruleIndex.
#   4. tool.driver.rules[? id == ruleId].defaultConfiguration.level via id
#      lookup (osv-scanner sets ruleIndex=-1 in some cases).
#   5. info as the fallback.
#
# KCOV_EXCL_START
_SARIF_SEVERITY_PIPE=$(cat <<'JQ'
def cvss_bucket(s):
  (s | tonumber) as $v
  | if $v >= 9.0 then "critical"
    elif $v >= 7.0 then "high"
    elif $v >= 4.0 then "medium"
    elif $v > 0    then "low"
    else "info"
    end;

def level_bucket(lvl):
  if   lvl == "error"   then "high"
  elif lvl == "warning" then "medium"
  elif lvl == "note"    then "low"
  else "info"
  end;

. as $sarif
| ($sarif.runs[0].tool.driver.rules // []) as $rules
| ($sarif.runs[0].results // [])
| map(
    . as $r
    | (.properties["security-severity"] // null) as $cvss
    | if $cvss != null then cvss_bucket($cvss)
      elif (.level // null) != null then level_bucket(.level)
      else
        (
          ([
            ((.ruleIndex // -1) as $idx
             | if $idx >= 0 and $idx < ($rules | length)
                 then $rules[$idx].defaultConfiguration.level // null
                 else null end),
            (($rules[]?
              | select(.id == $r.ruleId)
              | .defaultConfiguration.level // null)
             // null)
          ]
          | map(select(. != null))
          | first) // null
        ) as $lvl
        | if $lvl != null then level_bucket($lvl) else "info" end
      end
  )
JQ
)
# KCOV_EXCL_STOP

# sarif.tool_name <file>
# Print the SARIF run's tool driver name to stdout.
sarif.tool_name() {
    if [[ $# -lt 1 ]]; then
        printf 'sarif.tool_name: missing file argument\n' >&2
        return 2
    fi
    local _file="$1"
    if [[ ! -f "$_file" ]]; then
        printf 'sarif.tool_name: file does not exist: %s\n' "$_file" >&2
        return 1
    fi
    jq -r '.runs[0].tool.driver.name // ""' "$_file"
}

# sarif.count_total <file>
# Print the total number of results across run 0.
sarif.count_total() {
    if [[ $# -lt 1 ]]; then
        printf 'sarif.count_total: missing file argument\n' >&2
        return 2
    fi
    local _file="$1"
    if [[ ! -f "$_file" ]]; then
        printf 'sarif.count_total: file does not exist: %s\n' "$_file" >&2
        return 1
    fi
    jq -r '(.runs[0].results // []) | length' "$_file"
}

# sarif.count_by_severity <file>
# Print a JSON object {critical, high, medium, low, info} with bucket counts.
# Severity placement varies by tool: see _SARIF_SEVERITY_PIPE above.
sarif.count_by_severity() {
    if [[ $# -lt 1 ]]; then
        printf 'sarif.count_by_severity: missing file argument\n' >&2
        return 2
    fi
    local _file="$1"
    if [[ ! -f "$_file" ]]; then
        printf 'sarif.count_by_severity: file does not exist: %s\n' "$_file" >&2
        return 1
    fi
    jq -c "
        ${_SARIF_SEVERITY_PIPE}
        | reduce .[] as \$b (
            {critical:0, high:0, medium:0, low:0, info:0};
            .[\$b] += 1
          )
    " "$_file"
}

# sarif.extract_cwe <file>
# Print a JSON array of unique CWE identifiers (e.g. ["CWE-79","CWE-89"]),
# parsed from rules[].properties.tags strings shaped "CWE-NN: ...".
sarif.extract_cwe() {
    if [[ $# -lt 1 ]]; then
        printf 'sarif.extract_cwe: missing file argument\n' >&2
        return 2
    fi
    local _file="$1"
    if [[ ! -f "$_file" ]]; then
        printf 'sarif.extract_cwe: file does not exist: %s\n' "$_file" >&2
        return 1
    fi
    jq -c '
      [
        (.runs[0].tool.driver.rules // [])[]
        | (.properties.tags // [])[]
        | select(type == "string" and (test("^CWE-[0-9]+")))
        | capture("^(?<cwe>CWE-[0-9]+)").cwe
      ]
      | unique
    ' "$_file"
}

# sarif.is_valid <file>
# Return rc=0 when the file is a valid SARIF 2.1.0 document, rc=1 otherwise.
# Uses jv against the bundled OASIS schema when available; falls back to a
# structural jq check (version + runs[].tool.driver.name).
sarif.is_valid() {
    if [[ $# -lt 1 ]]; then
        return 1
    fi
    local _file="$1"
    [[ -f "$_file" ]] || return 1

    local _schema="${BRIK_HOME:-}/schemas/external/sarif-2.1.0.json"
    if [[ -f "$_schema" ]] && command -v jv >/dev/null 2>&1; then
        jv "$_schema" "$_file" >/dev/null 2>&1 && return 0
        return 1
    fi

    jq -e '
        (.version == "2.1.0")
        and (.runs | type == "array")
        and ((.runs[0].tool.driver.name // null) | type == "string")
    ' "$_file" >/dev/null 2>&1
}

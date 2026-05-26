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
    | (
        ([
          (.properties["security-severity"] // null),
          ((.ruleIndex // -1) as $idx
           | if $idx >= 0 and $idx < ($rules | length)
               then $rules[$idx].properties["security-severity"] // null
               else null end),
          (($rules[]?
            | select(.id == $r.ruleId)
            | .properties["security-severity"] // null)
           // null)
        ]
        | map(select(. != null))
        | first) // null
      ) as $cvss
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
    # KCOV_EXCL_START -- inline jq script body, not bash code
    jq -c "
        ${_SARIF_SEVERITY_PIPE}
        | reduce .[] as \$b (
            {critical:0, high:0, medium:0, low:0, info:0};
            .[\$b] += 1
          )
    " "$_file"
    # KCOV_EXCL_STOP
}

# sarif.extract_cwe <file>
# Print a JSON array of unique CWE identifiers (e.g. ["CWE-79","CWE-89"])
# for the rules that actually produced a result. Earlier revisions
# listed every rule the scanner ships with -- so a clean run still
# emitted ~60 CWE entries, which gave readers the impression that those
# weaknesses were detected. We now join results[].ruleId against
# tool.driver.rules[].id and pick CWE tags only from that subset.
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
    # KCOV_EXCL_START -- inline jq script body, not bash code
    jq -c '
      . as $sarif
      | ([(.runs[0].results // [])[].ruleId] | unique) as $hit_rule_ids
      | [
          ($sarif.runs[0].tool.driver.rules // [])[]
          | select(.id as $rid | $hit_rule_ids | index($rid))
          | (.properties.tags // [])[]
          | select(type == "string" and (test("^CWE-[0-9]+")))
          | capture("^(?<cwe>CWE-[0-9]+)").cwe
        ]
      | unique
    ' "$_file"
    # KCOV_EXCL_STOP
}

# sarif.extract_items <file>
# Print a JSON array of canonical Brik finding items extracted from a SARIF
# 2.1.0 document. Each item carries the operator-actionable subset that
# aggregate-report.{json,md,html} surfaces:
#   { id, severity, score, level, message, tool: {name, version},
#     location: {uri, start_line, end_line, snippet, logical},
#     package: {name, version, ecosystem} | null,
#     fix:     {versions: [...], available: bool} | null,
#     help_uri: string | null,
#     cwe:      [string, ...] }
# Severity bucket follows the same precedence as _SARIF_SEVERITY_PIPE but is
# computed per item so the array stays one-to-one with results.
sarif.extract_items() {
    if [[ $# -lt 1 ]]; then
        printf 'sarif.extract_items: missing file argument\n' >&2
        return 2
    fi
    local _file="$1"
    if [[ ! -f "$_file" ]]; then
        printf 'sarif.extract_items: file does not exist: %s\n' "$_file" >&2
        return 1
    fi
    # KCOV_EXCL_START -- inline jq script body, not bash code
    jq -c '
        def cvss_bucket(s):
          (s | tonumber) as $v
          | if   $v >= 9.0 then "critical"
            elif $v >= 7.0 then "high"
            elif $v >= 4.0 then "medium"
            elif $v >  0   then "low"
            else "info"
            end;
        def level_bucket(lvl):
          if   lvl == "error"   then "high"
          elif lvl == "warning" then "medium"
          elif lvl == "note"    then "low"
          else "info"
          end;
        def parse_purl(p):
          if (p // "") == "" or ((p // "") | test("^pkg:") | not) then null
          else
            (p | capture("^pkg:(?<eco>[^/]+)/(?:(?<ns>[^/@]+)/)?(?<name>[^@/?]+)@(?<ver>[^?]+)")) as $m
            | { name: $m.name, version: $m.ver, ecosystem: $m.eco }
          end;
        def parse_fix(help_text):
          if (help_text // "") == "" or ((help_text // "") | test("Fix Version:") | not) then null
          else
            (help_text | capture("Fix Version:[ \\t]*(?<v>[^\\n]*)").v) as $line
            | ($line | split(",") | map(gsub("^[ \\t]+|[ \\t]+$"; "")) | map(select(length > 0))) as $vs
            | { versions: $vs, available: ($vs | length > 0) }
          end;
        def parse_cwe(tags):
          ((tags // [])
            | map(select(type == "string" and test("^CWE-[0-9]+")))
            | map(capture("^(?<c>CWE-[0-9]+)").c)
            | unique);
        def first_present(xs):
          (xs | map(select(. != null)) | first) // null;
        def to_number(s):
          if s == null then null
          else (s | tostring | tonumber? // null)
          end;

        . as $sarif
        | ($sarif.runs[0] // {}) as $run
        | ($run.tool.driver // {}) as $drv
        | ($drv.rules // []) as $rules
        | { name: ($drv.name // ""), version: ($drv.version // null) } as $tool
        | (
            $run.results // []
            | map(
                . as $r
                | ($r.ruleIndex // -1) as $idx
                | (
                    if $idx >= 0 and $idx < ($rules | length) then $rules[$idx]
                    else (first($rules[]? | select(.id == $r.ruleId)) // null)
                    end
                  ) as $rule
                | first_present([
                    $r.properties["security-severity"]    // null,
                    $rule.properties["security-severity"] // null
                  ]) as $cvss_raw
                | (to_number($cvss_raw)) as $score
                | (
                    if $score != null then cvss_bucket($score)
                    elif ($r.level // null) != null then level_bucket($r.level)
                    else
                      first_present([
                        $rule.defaultConfiguration.level // null
                      ]) as $rl
                      | if $rl != null then level_bucket($rl) else "info" end
                    end
                  ) as $sev
                | (parse_purl($rule.properties.purls[0]? // "")) as $pkg
                | (parse_fix($rule.help.text? // "")) as $fix
                | (parse_cwe($rule.properties.tags? // [])) as $cwe
                | ($r.locations[0].physicalLocation? // {}) as $phy
                | ($r.locations[0].logicalLocations[0]? // {}) as $log
                | {
                    id:       ($r.ruleId // ""),
                    severity: $sev,
                    score:    $score,
                    level:    ($r.level // null),
                    message:  ($r.message.text // ""),
                    tool:     $tool,
                    location: {
                      uri:        ($phy.artifactLocation.uri // null),
                      start_line: ($phy.region.startLine // null),
                      end_line:   ($phy.region.endLine // null),
                      snippet:    ($phy.region.snippet.text // null),
                      logical:    ($log.fullyQualifiedName // null)
                    },
                    package:  $pkg,
                    fix:      $fix,
                    help_uri: ($rule.helpUri // null),
                    cwe:      $cwe
                  }
              )
          )
    ' "$_file"
    # KCOV_EXCL_STOP
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

    # KCOV_EXCL_START -- inline jq script body, not bash code
    jq -e '
        (.version == "2.1.0")
        and (.runs | type == "array")
        and ((.runs[0].tool.driver.name // null) | type == "string")
    ' "$_file" >/dev/null 2>&1
    # KCOV_EXCL_STOP
}

# sarif.from_prettier <input_text> <output_sarif>
# Convert raw `prettier --check` stdout into a minimal valid SARIF 2.1.0
# document. Each `[warn] <path>` line where <path> is a single token (no
# whitespace) becomes one result with ruleId="formatting" and level="warning".
# Lines whose payload contains whitespace (e.g. the trailing summary line)
# are ignored.
sarif.from_prettier() {
    if [[ $# -lt 2 ]]; then
        printf 'sarif.from_prettier: missing input/output arguments\n' >&2
        return 2
    fi
    local _in="$1" _out="$2"
    if [[ ! -f "$_in" ]]; then
        printf 'sarif.from_prettier: input does not exist: %s\n' "$_in" >&2
        return 1
    fi

    # KCOV_EXCL_START -- inline jq script body, not bash code
    grep -E '^\[warn\] [^[:space:]]+$' "$_in" 2>/dev/null \
        | sed -E 's/^\[warn\] //' \
        | jq -R -s --arg tool "prettier" '
            split("\n")
            | map(select(length > 0))
            | {
                "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
                "version": "2.1.0",
                "runs": [
                  {
                    "tool": {
                      "driver": {
                        "name": $tool,
                        "rules": [
                          {
                            "id": "formatting",
                            "shortDescription": { "text": "Code style issue detected by prettier" },
                            "defaultConfiguration": { "level": "warning" }
                          }
                        ]
                      }
                    },
                    "results": (
                      . | map({
                        "ruleId": "formatting",
                        "ruleIndex": 0,
                        "level": "warning",
                        "message": { "text": "File does not conform to prettier formatting rules." },
                        "locations": [
                          { "physicalLocation": { "artifactLocation": { "uri": . } } }
                        ]
                      })
                    )
                  }
                ]
              }
        ' > "$_out"
    # KCOV_EXCL_STOP
}

# sarif.from_tsc <input_text> <output_sarif>
# Convert raw `tsc --noEmit` stderr/stdout into a minimal valid SARIF 2.1.0
# document. Each line shaped `<file>(<line>,<col>): <severity> TSnnnn: <msg>`
# becomes one result with ruleId="TSnnnn", level mapped from the diagnostic
# severity (error->error, warning->warning, message->note).
sarif.from_tsc() {
    if [[ $# -lt 2 ]]; then
        printf 'sarif.from_tsc: missing input/output arguments\n' >&2
        return 2
    fi
    local _in="$1" _out="$2"
    if [[ ! -f "$_in" ]]; then
        printf 'sarif.from_tsc: input does not exist: %s\n' "$_in" >&2
        return 1
    fi

    # Stream of tab-separated tuples: file<TAB>line<TAB>col<TAB>sev<TAB>code<TAB>message.
    # Uses bash regex (BASH_REMATCH) for portability across BSD awk on macOS
    # which lacks the match($0, re, arr) gawk extension.
    local _re='^([^(]+)\(([0-9]+),([0-9]+)\): (error|warning|message) (TS[0-9]+): (.*)$'
    _sarif._parse_tsc_lines() {
        local _line _msg
        while IFS= read -r _line || [[ -n "$_line" ]]; do
            if [[ "$_line" =~ $_re ]]; then
                _msg="${BASH_REMATCH[6]//$'\t'/ }"
                printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
                    "${BASH_REMATCH[1]}" \
                    "${BASH_REMATCH[2]}" \
                    "${BASH_REMATCH[3]}" \
                    "${BASH_REMATCH[4]}" \
                    "${BASH_REMATCH[5]}" \
                    "$_msg"
            fi
        done
    }
    # KCOV_EXCL_START -- inline jq script body, not bash code
    _sarif._parse_tsc_lines < "$_in" \
      | jq -R -s --arg tool "tsc" '
          def to_level(s):
            if s == "error" then "error"
            elif s == "warning" then "warning"
            else "note"
            end;

          (split("\n") | map(select(length > 0))) as $lines
          | ($lines | map(split("\t") | {
              file: .[0], line: (.[1]|tonumber), col: (.[2]|tonumber),
              sev: .[3], code: .[4], msg: .[5]
            })) as $diags
          | {
              "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
              "version": "2.1.0",
              "runs": [
                {
                  "tool": {
                    "driver": {
                      "name": $tool,
                      "rules": (
                        $diags
                        | map(.code)
                        | unique
                        | map({ "id": ., "shortDescription": { "text": ("TypeScript diagnostic " + .) } })
                      )
                    }
                  },
                  "results": (
                    $diags | map({
                      "ruleId": .code,
                      "level": to_level(.sev),
                      "message": { "text": .msg },
                      "locations": [
                        {
                          "physicalLocation": {
                            "artifactLocation": { "uri": .file },
                            "region": { "startLine": .line, "startColumn": .col }
                          }
                        }
                      ]
                    })
                  )
                }
              ]
            }
        ' > "$_out"
    # KCOV_EXCL_STOP
}

# sarif.from_dotnet_format <input_json> <output_sarif>
# Convert a `dotnet format --report` JSON document into a minimal valid
# SARIF 2.1.0 document. The input is an array of file objects whose
# FileChanges[] entries each yield one SARIF result with ruleId set to
# DiagnosticId and level=warning (style issues, not compiler errors).
sarif.from_dotnet_format() {
    if [[ $# -lt 2 ]]; then
        printf 'sarif.from_dotnet_format: missing input/output arguments\n' >&2
        return 2
    fi
    local _in="$1" _out="$2"
    if [[ ! -f "$_in" ]]; then
        printf 'sarif.from_dotnet_format: input does not exist: %s\n' "$_in" >&2
        return 1
    fi

    # KCOV_EXCL_START -- inline jq script body, not bash code
    jq --arg tool "dotnet-format" '
      [ .[]
        | . as $file
        | (.FileChanges // [])[] | . as $ch
        | {
            "ruleId": ($ch.DiagnosticId // "format"),
            "level": "warning",
            "message": { "text": ($ch.FormatDescription // "Formatting issue") },
            "locations": [
              {
                "physicalLocation": {
                  "artifactLocation": { "uri": ($file.FilePath // $file.FileName // "") },
                  "region": {
                    "startLine": ($ch.LineNumber // 1),
                    "startColumn": ($ch.CharNumber // 1)
                  }
                }
              }
            ]
          }
      ] as $results
      | {
          "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
          "version": "2.1.0",
          "runs": [
            {
              "tool": {
                "driver": {
                  "name": $tool,
                  "rules": (
                    $results
                    | map(.ruleId)
                    | unique
                    | map({ "id": ., "shortDescription": { "text": ("dotnet-format diagnostic " + .) } })
                  )
                }
              },
              "results": $results
            }
          ]
        }
    ' "$_in" > "$_out"
    # KCOV_EXCL_STOP
}

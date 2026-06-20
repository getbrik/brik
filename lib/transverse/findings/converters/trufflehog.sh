#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.findings.converters.trufflehog
# @requires jq
# @description trufflehog NDJSON -> SARIF 2.1.0 converter.
#   trufflehog v3 emits one JSON object per line (NDJSON), e.g.:
#     {"SourceMetadata":{"Data":{"Filesystem":{"file":"src/secrets.py","line":12}}},
#      "DetectorName":"AWS","Verified":true,"Raw":"AKIA...","Redacted":"AKIA[REDACTED]"}
#
#   Level mapping (trufflehog -> SARIF level + Brik bucket):
#     Verified=true  -> error    (high)
#     Verified=false -> warning  (medium)
#
#   Secrets are inherently HIGH priority; verified ones are CRITICAL in
#   practice because the secret is known-good.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_TRANSVERSE_FINDINGS_CONVERTERS_TRUFFLEHOG_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_FINDINGS_CONVERTERS_TRUFFLEHOG_LOADED=1

findings.converters.trufflehog.to_sarif() {
    if [[ $# -lt 2 ]]; then
        printf 'findings.converters.trufflehog.to_sarif: missing arguments (input output)\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    local input="$1" output="$2"

    if ! command -v jq >/dev/null 2>&1; then
        printf 'findings.converters.trufflehog.to_sarif: jq is required\n' >&2
        return "$BRIK_EXIT_MISSING_DEP"
    fi

    local tmp
    tmp="$(mktemp "${output}.XXXXXX")" || return "$BRIK_EXIT_IO_FAILURE"

    # KCOV_EXCL_START -- jq script body is not bash code.
    # `jq -s` slurps the NDJSON stream into an array. Empty input -> [].
    if ! jq -s '
        # Resolve a usable filesystem location across the SourceMetadata
        # variants trufflehog emits (Filesystem, Git, Github, Gitlab, ...).
        # Falls back to "" so the SARIF stays well-formed when the source
        # type is unknown to us.
        def loc($r):
          ($r.SourceMetadata.Data // {}) as $d
          | ($d.Filesystem // $d.Git // $d.Github // $d.Gitlab // {}) as $fs
          | { file: ($fs.file // ""), line: ($fs.line // 1) };

        def level_for($r):
          if ($r.Verified // false) then "error" else "warning" end;

        def cvss_for($r):
          if ($r.Verified // false) then "9.0" else "7.0" end;

        def result($r):
          loc($r) as $l
          | {
              ruleId:  ($r.DetectorName // "trufflehog"),
              level:   level_for($r),
              message: {
                text: (
                  "Secret detected: " + ($r.DetectorName // "unknown")
                  + (if ($r.Verified // false) then " (verified)" else " (unverified)" end)
                  + (if ($r.Redacted // "") != "" then "\nValue: " + $r.Redacted else "" end)
                )
              },
              locations: [{
                physicalLocation: {
                  artifactLocation: { uri: $l.file },
                  region: { startLine: $l.line }
                }
              }],
              properties: {
                "security-severity": cvss_for($r),
                verified: ($r.Verified // false)
              }
            };

        (map(result(.))) as $results
        | (
            (group_by(.DetectorName // "trufflehog"))
            | map(
                # Pick the worst-case verified status across the group so
                # rule.defaultConfiguration.level is deterministic when a
                # detector ships both verified and unverified findings.
                # any(.Verified) -> error/9.0, otherwise -> warning/7.0.
                (any(.[]; .Verified // false)) as $worst
                | .[0] as $first
                | {
                    id:    ($first.DetectorName // "trufflehog"),
                    name:  ($first.DetectorName // "trufflehog"),
                    shortDescription: { text: ("trufflehog detector: " + ($first.DetectorName // "trufflehog")) },
                    defaultConfiguration: { level: (if $worst then "error" else "warning" end) },
                    properties: { "security-severity": (if $worst then "9.0" else "7.0" end) }
                  }
              )
          ) as $rules
        | {
            "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
            version: "2.1.0",
            runs: [{
              tool: {
                driver: {
                  name: "trufflehog",
                  informationUri: "https://github.com/trufflesecurity/trufflehog",
                  rules: $rules
                }
              },
              results: $results
            }]
          }
    ' "$input" > "$tmp"; then
        rm -f "$tmp"
        printf 'findings.converters.trufflehog.to_sarif: jq filter failed\n' >&2
        return "$BRIK_EXIT_IO_FAILURE"
    fi
    # KCOV_EXCL_STOP

    mv "$tmp" "$output" || {
        rm -f "$tmp"
        printf 'findings.converters.trufflehog.to_sarif: cannot write %s\n' "$output" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    }
    return 0
}

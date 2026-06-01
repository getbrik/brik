#!/usr/bin/env bash
# @module transverse.findings.policy
# @requires jq, transverse.sarif
# @description Policy stage of the findings pipeline: apply the active
#   built-in preset + org allowlist to a SARIF (apply_policy) and surface
#   allowlist entries expiring soon (expiring_soon). Split out of
#   lib/transverse/findings.sh; loaded by the findings.sh facade.
#
# Depends on facade-provided globals (resolved at runtime):
#   _BRIK_JQ_SEVERITY_DEFS    (transverse/sarif.sh: cvss_bucket/level_bucket)
#   _FINDINGS_JQ_RESULT_DEFS  (findings.sh facade: rule_for/severity_of_result)

[[ -n "${_BRIK_MODULE_TRANSVERSE_FINDINGS_POLICY_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_FINDINGS_POLICY_LOADED=1

# shellcheck source=../sarif.sh
[[ -z "${_BRIK_TRANSVERSE_SARIF_LOADED:-}" ]] && [[ -f "${BASH_SOURCE[0]%/*}/../sarif.sh" ]] && . "${BASH_SOURCE[0]%/*}/../sarif.sh"

# Apply the active built-in policy preset to a SARIF document. The preset
# is read from BRIK_QUALITY_FINDINGS_POLICY (default pragmatic); the
# severity floor is read from BRIK_SECURITY_SEVERITY_THRESHOLD (default
# high). P3 will layer the organization allowlist from BRIK_POLICY_URL on
# top of the preset output.
#
# Preset matrix (chantier 20260508 A2):
#   pragmatic  : ignore severity<floor (below-severity), then fixState=
#                not-fixed (no-upstream-fix), then fixState=wont-fix
#                (vendor-wont-fix); fail the rest.
#   strict     : ignore severity<floor; fail everything else (no-fix included).
#   permissive : effective floor is critical; ignore severity<critical
#                (below-severity), then not-fixed/wont-fix; fail only
#                critical with an upstream fix.
#
# In every preset, results that already carry a non-empty suppressions[]
# (tool-native allowlist, inline annotation, ...) pass through untouched
# so the SARIF natif owner keeps full control of pre-existing decisions.
#
# Annotations appended on policy-ignored results:
#   result.suppressions[+] = {
#     kind: "external",
#     justification: "Brik policy: <reason>",
#     properties: { brikSource: "policy.built-in.<reason>" }
#   }
# Reason is one of: below-severity, no-upstream-fix, vendor-wont-fix.
#
# Severity resolution mirrors transverse.sarif: prefers
# properties.security-severity (CVSS string) when present, else falls
# back to result.level. fixState defaults to "fixed" when absent so tools
# without grype-style fix metadata (semgrep, eslint, ...) never qualify
# for the no-fix tags.
#
# Args:
#   $1 sarif_in  -- input SARIF (typically the tool's native output).
#   $2 sarif_out -- output path (typically brik-artifacts/<stage>/findings.sarif).
findings.apply_policy() {
    if [[ $# -lt 2 ]]; then
        printf 'findings.apply_policy: missing arguments (expected: sarif_in sarif_out)\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    local sarif_in="$1" sarif_out="$2"
    if [[ ! -f "$sarif_in" ]]; then
        printf 'findings.apply_policy: input not found: %s\n' "$sarif_in" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    # Project preset (default pragmatic). The org policy cache may override
    # this further down with .preset_override.
    local preset="${BRIK_QUALITY_FINDINGS_POLICY:-pragmatic}"
    case "$preset" in
        pragmatic|strict|permissive) ;;
        *)
            printf 'findings.apply_policy: unknown preset %s (expected pragmatic|strict|permissive)\n' "$preset" >&2
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac

    # Resolve the org policy cache (chantier 20260508 P3 D5). Mirrors
    # org_policy.cache_path so callers do not need to source the loader
    # module just to read the cache. When BRIK_POLICY_CACHE_PATH is unset,
    # falls back to the canonical brik-artifacts location.
    local cache_path="${BRIK_POLICY_CACHE_PATH:-${BRIK_WORKSPACE:-/tmp/brik}/.brik-logs/policy.cache.json}"
    local cve_allowlist='[]'
    local path_globs='[]'
    if [[ -f "$cache_path" ]]; then
        cve_allowlist="$(jq -c '.cve_allowlist // []' "$cache_path" 2>/dev/null || printf '[]')"
        path_globs="$(jq -c '.path_globs // []' "$cache_path" 2>/dev/null || printf '[]')"
        local override
        override="$(jq -r '.preset_override // empty' "$cache_path" 2>/dev/null)"
        if [[ -n "$override" ]]; then
            case "$override" in
                pragmatic|strict|permissive)
                    preset="$override"
                    ;;
                *)
                    printf 'findings.apply_policy: unknown preset %s in org cache (expected pragmatic|strict|permissive)\n' "$override" >&2
                    return "$BRIK_EXIT_CONFIG_ERROR"
                    ;;
            esac
        fi
    fi

    local floor_raw="${BRIK_SECURITY_SEVERITY_THRESHOLD:-high}"
    local floor="${floor_raw,,}"
    local floor_rank
    case "$floor" in
        info)     floor_rank=0 ;;
        low)      floor_rank=1 ;;
        medium)   floor_rank=2 ;;
        high)     floor_rank=3 ;;
        critical) floor_rank=4 ;;
        *)
            printf 'findings.apply_policy: unknown severity threshold %s (expected info|low|medium|high|critical)\n' "$floor_raw" >&2
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac

    local out_dir
    out_dir="$(dirname "$sarif_out")"
    mkdir -p "$out_dir" || {
        printf 'findings.apply_policy: cannot create output directory: %s\n' "$out_dir" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    }

    if ! command -v jq >/dev/null 2>&1; then
        printf 'findings.apply_policy: jq not on PATH\n' >&2
        return "$BRIK_EXIT_MISSING_DEP"
    fi

    local tmp
    tmp="$(mktemp "${sarif_out}.XXXXXX")" || return "$BRIK_EXIT_IO_FAILURE"

    # KCOV_EXCL_START -- jq script body is not bash code
    jq --arg     preset        "$preset" \
       --argjson floor_rank    "$floor_rank" \
       --argjson cve_allowlist "$cve_allowlist" \
       --argjson path_globs    "$path_globs" "${_BRIK_JQ_SEVERITY_DEFS}${_FINDINGS_JQ_RESULT_DEFS}"'
        def severity_rank(s):
          if   s == "critical" then 4
          elif s == "high"     then 3
          elif s == "medium"   then 2
          elif s == "low"      then 1
          else 0 end;

        # cvss_bucket / level_bucket come from ${_BRIK_JQ_SEVERITY_DEFS}
        # (transverse/sarif.sh), prepended to this program above.

        # rule_for / severity_of_result come from
        # ${_FINDINGS_JQ_RESULT_DEFS} (top of findings.sh), prepended to this
        # program above. rule_for looks up severity/fix metadata: Grype
        # encodes CVSS at rule.properties.security-severity and fix
        # availability in rule.help.text ("Fix Version: <value>", empty = no
        # upstream fix).

        # Resolve fix availability. Order: explicit result property, SARIF
        # standard result.fixes[], grype-style "Fix Version:" in rule
        # help.text, conservative default "fixed" so tools without fix
        # metadata never qualify for the no-fix tags.
        def fix_state_of_result($r; $sarif):
          rule_for($r; $sarif) as $rule
          | ($r.properties.fixState // null) as $explicit
          | if $explicit != null then $explicit
            elif (($r.fixes // []) | length) > 0 then "fixed"
            else
              (($rule.help.text // "")
               | capture("Fix Version: (?<fv>[^\\n]*)")? // null) as $cap
              | if $cap == null then "fixed"
                elif ($cap.fv // "" | gsub("^\\s+|\\s+$"; "")) == "" then "not-fixed"
                else "fixed" end
            end;

        # Org policy CVE allowlist match. Returns the full brikSource tag
        # ("policy.org.cve-allowlist") on match, null otherwise.
        def org_match_cve($r):
          ($r.ruleId // null) as $rid
          | if $rid != null and ($cve_allowlist | index($rid)) != null
            then "policy.org.cve-allowlist"
            else null end;

        # Org policy path glob match: returns "policy.org.path-allowlist"
        # when any location URI matches any compiled regex pattern. The
        # try/catch around test() keeps a malformed pattern (e.g. unbalanced
        # bracket from an unusual glob) from crashing the entire jq filter
        # and silently dropping the SARIF document. A bad pattern simply
        # fails to match and the next pattern is evaluated.
        def org_match_path($r):
          ($r.locations // [])
          | map(.physicalLocation.artifactLocation.uri // "")
          | reduce .[] as $uri (null;
              if . != null then .
              else
                reduce $path_globs[] as $pg (null;
                  if . != null then .
                  elif (try ($uri | test($pg.regex)) catch false)
                       then "policy.org.path-allowlist"
                  else null end)
              end);

        # Built-in classification (chantier 20260508 P2 matrix). Returns the
        # full brikSource tag, e.g. "policy.built-in.below-severity".
        def builtin_classify($r; $sarif):
          severity_of_result($r; $sarif) as $sev
          | severity_rank($sev) as $rank
          | fix_state_of_result($r; $sarif) as $fix
          | (if $preset == "strict" then
              if $rank < $floor_rank then "below-severity" else null end
            elif $preset == "permissive" then
              if   $rank < 4               then "below-severity"
              elif $fix == "not-fixed"     then "no-upstream-fix"
              elif $fix == "wont-fix"      then "vendor-wont-fix"
              else null end
            else
              if   $rank < $floor_rank then "below-severity"
              elif $fix == "not-fixed"     then "no-upstream-fix"
              elif $fix == "wont-fix"      then "vendor-wont-fix"
              else null end
            end) as $r2
          | if $r2 != null then ("policy.built-in." + $r2) else null end;

        # Classify a result. Hierarchy (chantier Hierarchie d application):
        #   1. Native suppressions[] -> respect, never touch.
        #   2. Org policy (CVE allowlist, then path allowlist) -> tag.
        #   3. Built-in preset -> tag.
        # Returns a brikSource tag string, or null when the finding stays
        # failing.
        def classify($r; $sarif):
          (($r.suppressions // []) | length) as $sup_len
          | if $sup_len > 0 then null
            else
              org_match_cve($r) // org_match_path($r) // builtin_classify($r; $sarif)
            end;

        def annotate($r; $sarif):
          classify($r; $sarif) as $source
          | if $source == null then $r
            else
              ($source | split(".") | last) as $reason
              | $r + {
                suppressions: (
                  ($r.suppressions // []) + [{
                    kind: "external",
                    justification: ("Brik policy: " + $reason),
                    properties: { brikSource: $source }
                  }]
                )
              } end;

        . as $sarif
        | .runs[0].results = ((.runs[0].results // []) | map(annotate(.; $sarif)))
    ' "$sarif_in" > "$tmp" || {
        rm -f "$tmp"
        printf 'findings.apply_policy: jq processing failed for %s\n' "$sarif_in" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    }
    # KCOV_EXCL_STOP

    mv "$tmp" "$sarif_out" || {
        rm -f "$tmp"
        printf 'findings.apply_policy: cannot write %s\n' "$sarif_out" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    }
    return 0
}

# Surface allowlist entries whose expires field falls within
# BRIK_FINDINGS_EXPIRING_SOON_DAYS (default 30). Delegates to
# org_policy.expiring_soon, auto-loading the loader module from the
# canonical findings/ subdirectory when the host has not loaded it yet.
# Always returns 0 -- this is a query, not a gate. Callers (init stage)
# inspect the JSON array on stdout to decide what to surface.
#
# Output: JSON array on stdout. Each entry is shaped
#   { type: "cve",  id:   <CVE-ID>, expires: <YYYY-MM-DD>, reason: <str> }
#   { type: "path", glob: <glob>,   expires: <YYYY-MM-DD>, reason: <str> }
# Empty array "[]" when no org policy is active or no entry expires within
# the window -- mirrors the legacy stub behaviour for back-compat.
findings.expiring_soon() {
    if ! declare -f org_policy.expiring_soon >/dev/null 2>&1; then
        local _loader="${BASH_SOURCE[0]%/*}/org_policy.sh"
        if [[ -f "$_loader" ]]; then
            # shellcheck source=org_policy.sh
            . "$_loader" 2>/dev/null || true
        fi
    fi
    if declare -f org_policy.expiring_soon >/dev/null 2>&1; then
        org_policy.expiring_soon
        return 0
    fi
    printf '[]'
    return 0
}

#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module transverse.findings.org_policy
# @requires curl, yq, jv, jq
# @description Organizational policy loader for the Brik findings framework.
#   Fetches the org-owned brik-policy.yml from the URL the referential's
#   Policy document declares, validates it against
#   schemas/policy/v1/brik-policy.schema.json, filters entries by
#   BRIK_PROJECT_NAME and expires date, then writes a compiled cache to
#   ${BRIK_WORKSPACE}/.brik-logs/policy.cache.json (override path via
#   BRIK_POLICY_CACHE_PATH).
#
#   The compiled cache is consumed by findings.apply_policy to layer
#   policy.org.cve-allowlist / policy.org.path-allowlist annotations on top
#   of the built-in preset.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_TRANSVERSE_FINDINGS_ORG_POLICY_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_FINDINGS_ORG_POLICY_LOADED=1

# Resolve the compiled cache path. Honors BRIK_POLICY_CACHE_PATH override
# so tests and CI artifacts can target a deterministic location; falls
# back to the canonical brik-artifacts layout per chantier D5.
org_policy.cache_path() {
    if [[ -n "${BRIK_POLICY_CACHE_PATH:-}" ]]; then
        printf '%s' "$BRIK_POLICY_CACHE_PATH"
        return 0
    fi
    printf '%s/.brik-logs/policy.cache.json' "${BRIK_WORKSPACE:-/tmp/brik}"
}

# Returns 0 when an org policy cache exists for this run, 1 otherwise.
# Pipeline call sites use this to decide whether to feed the cache to
# findings.apply_policy or fall back to built-in-only behaviour.
org_policy.is_active() {
    local cache
    cache="$(org_policy.cache_path)"
    [[ -f "$cache" ]]
}

# Translate a glob pattern into an anchored regex. Recognises the standard
# globbing operators expected by DSI users (* matches a single path segment,
# ** matches across segments, ? a single character) plus the regex
# metacharacters that need escaping. The result is anchored with ^...$ so
# downstream jq test() matches the full URI rather than a prefix.
_org_policy._glob_to_regex() {
    local glob="$1"
    local regex=""
    local i=0 ch
    local n=${#glob}
    while ((i < n)); do
        ch="${glob:$i:1}"
        case "$ch" in
            '*')
                if [[ "${glob:$((i+1)):1}" == "*" ]]; then
                    regex+=".*"
                    i=$((i + 2))
                    continue
                fi
                regex+="[^/]*"
                ;;
            '?')        regex+="[^/]" ;;
            '.'|'+'|'('|')'|'['|']'|'{'|'}'|'^'|'$'|'|'|'\\')
                        regex+="\\${ch}" ;;
            *)          regex+="$ch" ;;
        esac
        i=$((i + 1))
    done
    printf '^%s$' "$regex"
}

# Convert an epoch timestamp to an ISO date (UTC). GNU date uses -d "@..."
# and BSD/macOS uses -r; we try both and fall back to today on failure.
_org_policy._epoch_to_date() {
    local epoch="$1"
    date -u -d "@$epoch" +%Y-%m-%d 2>/dev/null \
        || date -u -r "$epoch" +%Y-%m-%d 2>/dev/null \
        || date -u +%Y-%m-%d
}

# Load the policy file at <url>, validate it, filter entries by
# BRIK_PROJECT_NAME and expires, translate glob patterns to anchored regex,
# and write the compiled cache. No-op when no URL is given (the project then
# operates with built-in policy only); the caller decides whether a policy
# applies (stages.init reads the referential's Policy document).
# Usage: org_policy.load <url>
#
# Returns:
#   0                          on success or no-op (no URL given).
#   BRIK_EXIT_MISSING_DEP(3)   when curl/yq/jq is unavailable.
#   BRIK_EXIT_CONFIG_ERROR(7)  when the URL is unreachable, the YAML is
#                              malformed, or the policy violates the schema.
#   BRIK_EXIT_IO_FAILURE(6)    when the cache cannot be written.
org_policy.load() {
    local url="${1:-}"
    if [[ -z "$url" ]]; then
        return 0
    fi

    local cache
    cache="$(org_policy.cache_path)"
    mkdir -p "$(dirname "$cache")" || {
        printf 'org_policy.load: cannot create cache directory for %s\n' "$cache" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    }

    if ! command -v curl >/dev/null 2>&1; then
        printf 'org_policy.load: curl not on PATH\n' >&2
        return "$BRIK_EXIT_MISSING_DEP"
    fi
    if ! command -v yq >/dev/null 2>&1; then
        printf 'org_policy.load: yq not on PATH\n' >&2
        return "$BRIK_EXIT_MISSING_DEP"
    fi
    if ! command -v jq >/dev/null 2>&1; then
        printf 'org_policy.load: jq not on PATH\n' >&2
        return "$BRIK_EXIT_MISSING_DEP"
    fi

    local raw rc
    raw="$(curl -sf "$url" 2>/dev/null)"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        printf 'org_policy.load: cannot fetch the policy at %s (curl rc=%d)\n' \
            "$url" "$rc" >&2
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    local json
    if ! json="$(printf '%s\n' "$raw" | yq -o json '.' 2>/dev/null)"; then
        printf 'org_policy.load: malformed YAML at %s\n' "$url" >&2
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    local schema="${BRIK_HOME:-/opt/brik}/schemas/policy/v1/brik-policy.schema.json"
    if [[ -f "$schema" ]] && command -v jv >/dev/null 2>&1; then
        # Validate by piping the JSON via stdin instead of materialising a
        # tmp file: avoids the symlink race that "$(mktemp).json" introduced
        # (the .json suffix concatenation breaks mktemp's safe-by-default
        # contract) and the cleanup-on-signal gap.
        if ! printf '%s\n' "$json" | jv "$schema" - >/dev/null 2>&1; then
            printf 'org_policy.load: schema validation failed for the policy at %s\n' \
                "$url" >&2
            return "$BRIK_EXIT_CONFIG_ERROR"
        fi
    fi

    local project="${BRIK_PROJECT_NAME:-}"
    local today
    today="$(date -u +%Y-%m-%d)"
    local loaded_at
    loaded_at="$(date +"%Y-%m-%dT%H:%M:%S%z")"

    # Phase A: filter cve/paths by projects[] and expires (lexicographic
    # comparison on YYYY-MM-DD is correct).
    # KCOV_EXCL_START -- jq script body is not bash code
    local partial
    partial="$(printf '%s\n' "$json" | jq -c \
        --arg project "$project" \
        --arg today   "$today" '
        def is_for_project($entry):
            ($entry.projects // null) as $p
            | $p == null or ($p | index($project) != null);

        def is_active($entry):
            ($entry.expires // "0000-00-00") >= $today;

        def filtered($items):
            ($items // []) | map(select(is_for_project(.) and is_active(.)));

        {
            preset_override: (.preset // null),
            cve_entries:  filtered(.allow.cve),
            path_entries: filtered(.allow.paths)
        }
    ' 2>/dev/null)" || {
        printf 'org_policy.load: jq filter failed\n' >&2
        return "$BRIK_EXIT_IO_FAILURE"
    }
    # KCOV_EXCL_STOP

    # Phase B: enrich path_entries with translated regex. Done in bash
    # because jq has no native glob -> regex; iterating in shell keeps the
    # translation logic readable and unit-testable.
    local path_count
    path_count="$(printf '%s' "$partial" | jq '.path_entries | length')"
    local path_globs_json='[]'
    local entries=()
    local idx glob expires regex
    if (( path_count > 0 )); then
        for ((idx=0; idx<path_count; idx++)); do
            glob="$(printf '%s' "$partial"   | jq -r ".path_entries[$idx].glob")"
            expires="$(printf '%s' "$partial" | jq -r ".path_entries[$idx].expires")"
            regex="$(_org_policy._glob_to_regex "$glob")"
            entries+=("$(jq -nc \
                --arg glob "$glob" \
                --arg regex "$regex" \
                --arg expires "$expires" \
                '{glob: $glob, regex: $regex, expires: $expires}')")
        done
        path_globs_json="$(printf '%s\n' "${entries[@]}" | jq -sc '.')"
    fi

    # Phase C: assemble the compiled cache. Use the standard write-tmp-then-mv
    # pattern (mirrors lib/pipeline/report.sh:_report._append_json) so a
    # parallel reader (apply_policy or report.aggregate_fragments) never
    # observes a half-written file when org_policy.load runs concurrently.
    local cache_tmp
    cache_tmp="$(mktemp "${cache}.XXXXXX")" || {
        printf 'org_policy.load: cannot create cache tmp file in %s\n' "$(dirname "$cache")" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    }
    # KCOV_EXCL_START -- jq script body is not bash code
    if ! jq -n \
        --argjson partial    "$partial" \
        --argjson path_globs "$path_globs_json" \
        --arg     url        "$url" \
        --arg     loaded_at  "$loaded_at" '
        {
            preset_override: $partial.preset_override,
            cve_allowlist:   ($partial.cve_entries | map(.id) | unique),
            cve_entries:     $partial.cve_entries,
            path_globs:      $path_globs,
            path_entries:    $partial.path_entries,
            url:             $url,
            loaded_at:       $loaded_at
        }
    ' > "$cache_tmp"; then
        rm -f "$cache_tmp"
        printf 'org_policy.load: cannot build compiled cache for %s\n' "$cache" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    fi
    # KCOV_EXCL_STOP
    if ! mv "$cache_tmp" "$cache"; then
        rm -f "$cache_tmp"
        printf 'org_policy.load: cannot install compiled cache to %s\n' "$cache" >&2
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    return 0
}

# Read the state-repo branch-protection posture from the policy at <url>.
# Echoes required|warn|off; an absent field means warn. Fail-closed: an
# unreachable or malformed policy, or a value outside the enum, is
# CONFIG_ERROR -- a governed project must never silently regress to a softer
# posture. The enum is enforced in bash so the guarantee holds even on a
# host without a JSON Schema validator.
# Usage: org_policy.state_repo_protection <url>
org_policy.state_repo_protection() {
    local url="${1:-}"
    if [[ -z "$url" ]]; then
        printf 'org_policy.state_repo_protection: <url> is required\n' >&2
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local dep
    for dep in curl yq jq; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            printf 'org_policy.state_repo_protection: %s not on PATH\n' "$dep" >&2
            return "$BRIK_EXIT_MISSING_DEP"
        fi
    done

    local raw rc
    raw="$(curl -sf "$url" 2>/dev/null)"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        printf 'org_policy.state_repo_protection: cannot fetch the policy at %s (curl rc=%d)\n' \
            "$url" "$rc" >&2
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    local json
    if ! json="$(printf '%s\n' "$raw" | yq -o json '.' 2>/dev/null)"; then
        printf 'org_policy.state_repo_protection: malformed YAML at %s\n' "$url" >&2
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    local value
    value="$(printf '%s\n' "$json" | jq -r '.state_repo_protection // "warn"')"
    case "$value" in
        required|warn|off) ;;
        *)
            printf 'org_policy.state_repo_protection: the policy at %s violates the policy schema (state_repo_protection=%s)\n' \
                "$url" "$value" >&2
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac
    printf '%s' "$value"
}

# Surface allowlist entries whose expires falls within
# BRIK_FINDINGS_EXPIRING_SOON_DAYS (default 30). Returns "[]" when no cache
# exists so call sites can integrate the expiring-soon banner unconditionally.
org_policy.expiring_soon() {
    if ! org_policy.is_active; then
        printf '[]'
        return 0
    fi
    local cache
    cache="$(org_policy.cache_path)"
    local days="${BRIK_FINDINGS_EXPIRING_SOON_DAYS:-30}"
    local now_epoch
    now_epoch="$(date -u +%s)"
    local soon_epoch=$((now_epoch + days * 86400))
    local soon_date
    soon_date="$(_org_policy._epoch_to_date "$soon_epoch")"

    # KCOV_EXCL_START -- jq script body is not bash code
    jq -c --arg soon "$soon_date" '
        [
          (.cve_entries // [])[]
          | select(.expires <= $soon)
          | { type: "cve", id: .id, expires: .expires, reason: (.reason // "") }
        ]
        +
        [
          (.path_entries // [])[]
          | select(.expires <= $soon)
          | { type: "path", glob: .glob, expires: .expires, reason: (.reason // "") }
        ]
    ' "$cache"
    # KCOV_EXCL_STOP
}

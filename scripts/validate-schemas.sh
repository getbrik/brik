#!/usr/bin/env bash
# @script validate-schemas
# @description Validate every JSON Schema file under schemas/ against the
#   JSON Schema 2020-12 meta-schema, plus a few brik-specific invariants
#   (every schema declares $schema and $id; every $ref resolves locally).
#
# Run via:
#   scripts/validate-schemas.sh
#
# Exits 0 when every schema is valid, 1 on the first failure.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HERE%/scripts}"
SCHEMAS_DIR="${ROOT}/schemas"

command -v jq >/dev/null 2>&1 || { printf '[validate-schemas] jq required\n' >&2; exit 69; }

if [[ ! -d "$SCHEMAS_DIR" ]]; then
    printf '[validate-schemas] schemas dir not found: %s\n' "$SCHEMAS_DIR" >&2
    exit 66
fi

# Pick a validator. jv is preferred (same tool brik uses at runtime);
# check-jsonschema is the documented fallback (per doctor.sh).
validator=""
if command -v jv >/dev/null 2>&1; then
    validator="jv"
elif command -v check-jsonschema >/dev/null 2>&1; then
    validator="check-jsonschema"
else
    printf '[validate-schemas] no JSON Schema validator on PATH (install jv or check-jsonschema)\n' >&2
    exit 69
fi

META="https://json-schema.org/draft/2020-12/schema"

pass=0
fail=0
fail_files=()

while IFS= read -r schema; do
    rel="${schema#"$ROOT/"}"

    if ! jq '.' "$schema" >/dev/null 2>&1; then
        printf '[validate-schemas] FAIL %s: not valid JSON\n' "$rel" >&2
        fail=$((fail + 1))
        fail_files+=("$rel")
        continue
    fi

    declared="$(jq -r '."$schema" // ""' "$schema")"
    # schemas/external/ vendors third-party schemas verbatim (e.g.
    # CycloneDX is draft-07). We don't rewrite them, so the
    # 2020-12-must-match invariant only applies to brik-authored
    # schemas under schemas/{config,plan,registry,report,policy}/.
    is_external=false
    [[ "$rel" == schemas/external/* ]] && is_external=true
    if [[ "$is_external" == "false" && "$declared" != "$META" ]]; then
        printf '[validate-schemas] FAIL %s: $schema is %s, expected %s\n' \
            "$rel" "${declared:-<missing>}" "$META" >&2
        fail=$((fail + 1))
        fail_files+=("$rel")
        continue
    fi
    if [[ "$is_external" == "true" ]]; then
        printf '[validate-schemas] OK   %s (external, $schema=%s)\n' "$rel" "${declared:-<missing>}"
        pass=$((pass + 1))
        continue
    fi

    if [[ "$(jq -r '."$id" // ""' "$schema")" == "" ]]; then
        printf '[validate-schemas] FAIL %s: $id is missing\n' "$rel" >&2
        fail=$((fail + 1))
        fail_files+=("$rel")
        continue
    fi

    # Every local $ref ("#/$defs/<name>") must resolve to an existing
    # def. External refs (https://...) are passed through; only local
    # refs are checked because that's what brik authors control.
    bad_ref="$(jq -r '
        [ paths as $p | getpath($p) | strings | select(startswith("#/$defs/")) ] as $refs
        | ($refs | map(ltrimstr("#/$defs/"))) as $names
        | ($names - (try ((.["$defs"] // {}) | keys) catch [])) | .[]
    ' "$schema" 2>/dev/null | head -1)"
    if [[ -n "$bad_ref" ]]; then
        printf '[validate-schemas] FAIL %s: unresolved $ref #/$defs/%s\n' "$rel" "$bad_ref" >&2
        fail=$((fail + 1))
        fail_files+=("$rel")
        continue
    fi

    # Validator-level meta-schema check. check-jsonschema supports it
    # natively; for jv we fall back to a structural attempt by validating
    # the empty document {}, which forces jv to parse the schema. A
    # structural error in the schema surfaces as a "schema:" prefix; any
    # other error means the schema parsed fine and the instance just
    # didn't match.
    if [[ "$validator" == "check-jsonschema" ]]; then
        if ! check-jsonschema --check-metaschema "$schema" >/dev/null 2>&1; then
            err="$(check-jsonschema --check-metaschema "$schema" 2>&1 || true)"
            printf '[validate-schemas] FAIL %s: %s\n' "$rel" "$err" >&2
            fail=$((fail + 1))
            fail_files+=("$rel")
            continue
        fi
    else
        empty_doc="$(mktemp)"
        printf '{}' > "$empty_doc"
        err="$(jv "$schema" "$empty_doc" 2>&1 || true)"
        rm -f "$empty_doc"
        # An external $ref that jv can't fetch ("returned status code 404"
        # / "failing loading") means we can't fully cross-validate, not
        # that the schema is broken. Surface as a warning, not a hard
        # fail -- the schema's own structure has already been checked by
        # the earlier jq/$schema/$id/$ref steps.
        if grep -qiE 'returned status code|failing loading' <<<"$err"; then
            printf '[validate-schemas] WARN %s: external ref not fetchable (%s)\n' \
                "$rel" "$(grep -oE 'https?://[^[:space:]"]+' <<<"$err" | head -1)" >&2
        elif grep -qiE '^schema [^:]+:.*(error|fail)|invalid schema' <<<"$err"; then
            printf '[validate-schemas] FAIL %s: %s\n' "$rel" "$err" >&2
            fail=$((fail + 1))
            fail_files+=("$rel")
            continue
        fi
    fi

    printf '[validate-schemas] OK   %s\n' "$rel"
    pass=$((pass + 1))
done < <(find "$SCHEMAS_DIR" -type f -name '*.schema.json' | LC_ALL=C sort)

# Vendored third-party schemas under schemas/external/ are pinned by content in
# SCHEMAS.sha256 so a copy cannot drift unnoticed (these files are not rewritten
# and carry no $schema/$id we author). Enforce that manifest: every recorded
# digest matches, and no external schema file is left unpinned.
external_dir="${SCHEMAS_DIR}/external"
checksum_file="${external_dir}/SCHEMAS.sha256"
if [[ ! -f "$checksum_file" ]]; then
    printf '[validate-schemas] FAIL schemas/external/SCHEMAS.sha256: missing checksum manifest\n' >&2
    fail=$((fail + 1))
    fail_files+=("schemas/external/SCHEMAS.sha256")
else
    sha_cmd=()
    if command -v sha256sum >/dev/null 2>&1; then
        sha_cmd=(sha256sum)
    elif command -v shasum >/dev/null 2>&1; then
        sha_cmd=(shasum -a 256)
    fi

    if [[ "${#sha_cmd[@]}" -eq 0 ]]; then
        printf '[validate-schemas] FAIL schemas/external/SCHEMAS.sha256: no sha256 tool (sha256sum or shasum) on PATH\n' >&2
        fail=$((fail + 1))
        fail_files+=("schemas/external/SCHEMAS.sha256")
    elif ( cd "$external_dir" && "${sha_cmd[@]}" -c SCHEMAS.sha256 ) >/dev/null 2>&1; then
        printf '[validate-schemas] OK   schemas/external/SCHEMAS.sha256 (vendored digests match)\n'
        pass=$((pass + 1))
    else
        printf '[validate-schemas] FAIL schemas/external/SCHEMAS.sha256: vendored external schema digests do not match\n' >&2
        ( cd "$external_dir" && "${sha_cmd[@]}" -c SCHEMAS.sha256 ) 2>&1 \
            | grep -vi ': OK$' | sed 's/^/[validate-schemas]   /' >&2 || true
        fail=$((fail + 1))
        fail_files+=("schemas/external/SCHEMAS.sha256")
    fi

    # No external schema may ship unpinned: every *.json under external/ must
    # have a line in the manifest.
    while IFS= read -r ext_file; do
        ext_base="$(basename "$ext_file")"
        if ! grep -qE "  ${ext_base}\$" "$checksum_file"; then
            printf '[validate-schemas] FAIL schemas/external/%s: not pinned in SCHEMAS.sha256\n' "$ext_base" >&2
            fail=$((fail + 1))
            fail_files+=("schemas/external/${ext_base}")
        fi
    done < <(find "$external_dir" -maxdepth 1 -type f -name '*.json' | LC_ALL=C sort)
fi

printf '\n[validate-schemas] %d passed, %d failed (validator=%s)\n' "$pass" "$fail" "$validator"
if [[ "$fail" -gt 0 ]]; then
    printf '[validate-schemas] failed files:\n' >&2
    for f in "${fail_files[@]}"; do
        printf '  - %s\n' "$f" >&2
    done
    exit 1
fi
exit 0

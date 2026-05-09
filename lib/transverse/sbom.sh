#!/usr/bin/env bash
# @module sbom
# @requires jq
# @description CycloneDX 1.5 SBOM helpers: validate, count components and
#   vulnerabilities, and merge multiple SBOMs into one. Prefers the
#   cyclonedx-cli Go binary when available; falls back to a pure-jq merge
#   that deduplicates components by bom-ref.

# Guard against double-sourcing.
[[ -n "${_BRIK_TRANSVERSE_SBOM_LOADED:-}" ]] && return 0
_BRIK_TRANSVERSE_SBOM_LOADED=1

# sbom.component_count <file>
# Print the number of components (.components | length).
sbom.component_count() {
    if [[ $# -lt 1 ]]; then
        printf 'sbom.component_count: missing file argument\n' >&2
        return 2
    fi
    local _file="$1"
    if [[ ! -f "$_file" ]]; then
        printf 'sbom.component_count: file does not exist: %s\n' "$_file" >&2
        return 1
    fi
    jq -r '(.components // []) | length' "$_file"
}

# sbom.vuln_count <file>
# Print the number of vulnerabilities (.vulnerabilities | length).
sbom.vuln_count() {
    if [[ $# -lt 1 ]]; then
        printf 'sbom.vuln_count: missing file argument\n' >&2
        return 2
    fi
    local _file="$1"
    if [[ ! -f "$_file" ]]; then
        printf 'sbom.vuln_count: file does not exist: %s\n' "$_file" >&2
        return 1
    fi
    jq -r '(.vulnerabilities // []) | length' "$_file"
}

# sbom.is_valid <file>
# Return rc=0 when the file is a valid CycloneDX 1.5 document, rc=1 otherwise.
# Uses jv against the bundled official schema when available; falls back to a
# structural jq check (bomFormat + specVersion).
sbom.is_valid() {
    if [[ $# -lt 1 ]]; then
        return 1
    fi
    local _file="$1"
    [[ -f "$_file" ]] || return 1

    local _schema="${BRIK_HOME:-}/schemas/external/cyclonedx-1.5.schema.json"
    if [[ -f "$_schema" ]] && command -v jv >/dev/null 2>&1; then
        jv "$_schema" "$_file" >/dev/null 2>&1 && return 0
        return 1
    fi

    # KCOV_EXCL_START -- inline jq script body, not bash code
    jq -e '
        (.bomFormat == "CycloneDX")
        and (.specVersion == "1.5")
    ' "$_file" >/dev/null 2>&1
    # KCOV_EXCL_STOP
}

# sbom.merge <output_path> <input_path>...
# Merge multiple CycloneDX 1.5 SBOMs into a single output file.
# Prefers cyclonedx-cli when on PATH; otherwise uses the pure-jq fallback.
sbom.merge() {
    if [[ $# -lt 1 ]]; then
        printf 'sbom.merge: missing output path\n' >&2
        return 2
    fi
    local _out="$1"
    shift
    if [[ $# -lt 1 ]]; then
        printf 'sbom.merge: at least one input is required\n' >&2
        return 2
    fi

    local _f
    for _f in "$@"; do
        if [[ ! -f "$_f" ]]; then
            printf 'sbom.merge: input does not exist: %s\n' "$_f" >&2
            return 1
        fi
    done

    # KCOV_EXCL_START -- cyclonedx-cli is optional and not installed in CI
    if command -v cyclonedx-cli >/dev/null 2>&1; then
        local _args=()
        for _f in "$@"; do
            _args+=( "--input-files" "$_f" )
        done
        cyclonedx-cli merge --output-format json --output-file "$_out" "${_args[@]}" >/dev/null 2>&1 && return 0
        printf 'sbom.merge: cyclonedx-cli failed; falling back to jq merge\n' >&2
    fi
    # KCOV_EXCL_STOP

    _sbom._jq_merge "$_out" "$@"
}

# Internal: pure-jq fallback merge. Takes the first input as the base
# (preserving its metadata), unions components by bom-ref (or by name@version
# when bom-ref is absent), and concatenates vulnerabilities.
_sbom._jq_merge() {
    local _out="$1"
    shift
    # KCOV_EXCL_START -- inline jq script body, not bash code
    jq -s '
      def comp_key(c):
        c["bom-ref"] // ((c.name // "") + "@" + (c.version // ""));

      .[0] as $base
      | (reduce .[] as $doc ([]; . + ($doc.components // []))
         | unique_by(comp_key(.))) as $components
      | (reduce .[] as $doc ([]; . + ($doc.vulnerabilities // []))) as $vulns
      | $base
      | .components = $components
      | .vulnerabilities = $vulns
    ' "$@" > "$_out"
    # KCOV_EXCL_STOP
}

#!/usr/bin/env bash
# @description Generate the Quick reference markdown table for a brik.yml
#              section from the JSON Schema.
#
# v1 prints to stdout only. Future revisions will splice the output into
# docs/config/reference/<section>.md between sentinel comments and add a
# --check mode that diffs regenerated content against committed pages.
#
# Usage:
#   ./scripts/gen-config-reference.sh project        # top-level inline
#   ./scripts/gen-config-reference.sh release        # $defs/release
#   ./scripts/gen-config-reference.sh quality        # walks sub-sections
#   ./scripts/gen-config-reference.sh --list         # list known sections

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCHEMA="${REPO_ROOT}/schemas/config/v1/brik.schema.json"

if [[ ! -f "${SCHEMA}" ]]; then
    echo "[gen-config-reference] error: schema not found at ${SCHEMA}" >&2
    exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "[gen-config-reference] error: jq is required" >&2
    exit 2
fi

# Resolve a section name to its JSON-pointer path inside the schema.
# project and version are inline at .properties.*; everything else is in $defs.
_resolve_path() {
    local section="$1"
    case "$section" in
        project) echo '.properties.project' ;;
        version) echo '.properties.version' ;;
        *)       echo ".\"\$defs\".${section}" ;;
    esac
}

# Render markdown rows for a JSON object of properties (read from stdin).
# Format type, default, description for each property.
_render_rows() {
    local prefix="$1"
    jq -r --arg prefix "$prefix" '
        def fmt_type:
            if .["$ref"] then "ref"
            elif .enum then "enum"
            elif .type == "array" then
                if .items.type == "string" then "array of strings"
                else "array"
                end
            elif .type == "object" then "object"
            else (.type // "any")
            end;
        def fmt_default:
            if has("default") then "`\(.default | tostring)`"
            else "--"
            end;
        def fmt_desc:
            (.description // "") | gsub("\\n"; " ");
        to_entries[]
        | "| `\($prefix).\(.key)` | \(.value | fmt_type) | \(.value | fmt_default) | \(.value | fmt_desc) |"
    '
}

# Header for the markdown table.
_table_header() {
    cat <<'EOF'
| Field | Type | Default | Description |
|-------|------|---------|-------------|
EOF
}

# Render a single section. If the section has nested object children
# (sub-blocks like quality.lint, quality.format), emit a sub-heading +
# table per child. Leaf properties render as one combined table.
gen_section() {
    local section="$1"
    local jq_path
    jq_path="$(_resolve_path "$section")"

    # Confirm the section exists in the schema.
    local exists
    exists="$(jq -r "${jq_path} // empty | type" "${SCHEMA}")"
    if [[ -z "${exists}" ]]; then
        echo "[gen-config-reference] error: unknown section '${section}'" >&2
        return 2
    fi

    # Special-case: top-level singletons (version, no sub-properties).
    local sec_type
    sec_type="$(jq -r "${jq_path}.type // \"\"" "${SCHEMA}")"
    if [[ "${sec_type}" != "object" ]]; then
        # Single property like top-level `version`.
        _table_header
        jq -r --arg name "$section" '
            "| `\($name)` | \(.type // "any") | \(if has("default") then "`\(.default | tostring)`" else "--" end) | \((.description // "") | gsub("\\n"; " ")) |"
        ' <<< "$(jq "${jq_path}" "${SCHEMA}")"
        echo
        return 0
    fi

    # Object section: split leaf properties from nested object children.
    local props_json
    props_json="$(jq "${jq_path}.properties // {}" "${SCHEMA}")"

    local leaf_props nested_keys
    leaf_props="$(jq '
        with_entries(select(.value.type != "object" or (.value.properties | not)))
    ' <<< "${props_json}")"
    nested_keys="$(jq -r '
        to_entries[]
        | select(.value.type == "object" and (.value.properties | type == "object"))
        | .key
    ' <<< "${props_json}")"

    if [[ "$(jq 'length' <<< "${leaf_props}")" -gt 0 ]]; then
        _table_header
        printf '%s\n' "${leaf_props}" | _render_rows "${section}"
        echo
    fi

    if [[ -n "${nested_keys}" ]]; then
        local key
        while IFS= read -r key; do
            [[ -z "${key}" ]] && continue
            printf '### `%s.%s`\n\n' "${section}" "${key}"
            _table_header
            jq "${jq_path}.properties.${key}.properties" "${SCHEMA}" \
                | _render_rows "${section}.${key}"
            echo
        done <<< "${nested_keys}"
    fi
}

# List known sections that the generator can render.
_list_sections() {
    {
        echo "project"
        echo "version"
        jq -r '."$defs" | keys[]' "${SCHEMA}"
    } | sort -u
}

# CLI dispatch
if [[ $# -eq 0 ]]; then
    echo "usage: $0 <section> | --list" >&2
    exit 2
fi

case "$1" in
    --list) _list_sections ;;
    -h|--help)
        echo "usage: $0 <section> | --list"
        echo
        echo "Sections:"
        _list_sections | sed 's/^/  /'
        ;;
    *) gen_section "$1" ;;
esac

#!/usr/bin/env bash
# @description Generate the Quick reference markdown table for a brik.yml
#              section from the JSON Schema and splice it into the matching
#              page under docs/config/reference/.
#
# Pages must mark the auto-managed region with HTML sentinel comments:
#
#   <!-- BEGIN AUTO-GENERATED: quick-reference -->
#   ...generator content...
#   <!-- END AUTO-GENERATED -->
#
# Usage:
#   ./scripts/gen-config-reference.sh <section>           # print to stdout
#   ./scripts/gen-config-reference.sh --apply <section>   # splice into page
#   ./scripts/gen-config-reference.sh --apply --all       # splice all pages
#   ./scripts/gen-config-reference.sh --check             # diff drift (CI)
#   ./scripts/gen-config-reference.sh --list              # list sections

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
# Format type, default, description for each property. The full schema is
# loaded via --slurpfile (a one-element array, hence $schema[0]) so $refs
# can be resolved. --argfile was removed in jq 1.8.
_render_rows() {
    local prefix="$1"
    jq -r --arg prefix "$prefix" --slurpfile schema "${SCHEMA}" '
        # Resolve a $ref like "#/$defs/notifyEventList" to its target schema.
        def deref:
            if .["$ref"] then
                .["$ref"] as $r
                | $r | sub("^#/\\$defs/"; "") as $name
                | $schema[0]["$defs"][$name]
            else .
            end;
        def fmt_type:
            deref as $r
            | if $r.enum then
                "enum (\($r.enum | map("`\(.)`") | join(", ")))"
              elif $r.type == "array" then
                if $r.items.enum then
                    "array of enum (\($r.items.enum | map("`\(.)`") | join(", ")))"
                elif $r.items.type == "string" then "array of strings"
                else "array"
                end
              elif $r.type == "object" then "object"
              else ($r.type // "any")
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
            def fmt_type:
                if .const then "const (`\(.const)`)"
                elif .enum then "enum (\(.enum | map("`\(.)`") | join(", ")))"
                else (.type // "any")
                end;
            def fmt_default:
                if has("default") then "`\(.default | tostring)`"
                elif .const then "`\(.const)`"
                else "--"
                end;
            "| `\($name)` | \(fmt_type) | \(fmt_default) | \((.description // "") | gsub("\\n"; " ")) |"
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

# Sections that have a page under docs/config/reference/. Internal $defs
# (deployEnvironment, hookCommand, notifyEventList) are not user-facing.
_user_facing_sections() {
    cat <<'EOF'
project
release
git
notify
hooks
build
quality
test
package
publish
security
deploy
EOF
}

# List every section the generator could render (debugging aid).
_list_sections() {
    {
        echo "project"
        echo "version"
        jq -r '."$defs" | keys[]' "${SCHEMA}"
    } | sort -u
}

# Splice generated content into a markdown page between sentinels.
# Returns 0 on success, 3 if sentinels are missing.
SENTINEL_BEGIN='<!-- BEGIN AUTO-GENERATED: quick-reference -->'
SENTINEL_END='<!-- END AUTO-GENERATED -->'

_splice_page() {
    local page="$1"
    local section="$2"

    if [[ ! -f "${page}" ]]; then
        echo "[gen-config-reference] error: ${page} not found" >&2
        return 2
    fi
    if ! grep -qF "${SENTINEL_BEGIN}" "${page}" \
        || ! grep -qF "${SENTINEL_END}" "${page}"; then
        echo "[gen-config-reference] error: sentinels missing in ${page}" >&2
        echo "[gen-config-reference]   add the following pair around the Quick reference table:" >&2
        echo "    ${SENTINEL_BEGIN}" >&2
        echo "    ${SENTINEL_END}" >&2
        return 3
    fi

    local body_file tmp
    body_file="$(mktemp)"
    tmp="$(mktemp)"
    gen_section "${section}" > "${body_file}"

    awk -v begin="${SENTINEL_BEGIN}" -v end="${SENTINEL_END}" \
        -v body_file="${body_file}" '
        BEGIN { in_block = 0 }
        index($0, begin) {
            print
            while ((getline line < body_file) > 0) print line
            close(body_file)
            in_block = 1
            next
        }
        index($0, end) { print; in_block = 0; next }
        !in_block { print }
    ' "${page}" > "${tmp}"

    mv "${tmp}" "${page}"
    rm -f "${body_file}"
}

_page_for_section() {
    local section="$1"
    echo "${REPO_ROOT}/docs/config/reference/${section}.md"
}

# Apply mode: rewrite one page or all pages.
cmd_apply() {
    local target="${1:-}"
    if [[ "${target}" == "--all" || -z "${target}" ]]; then
        local s
        while IFS= read -r s; do
            [[ -z "${s}" ]] && continue
            local page
            page="$(_page_for_section "${s}")"
            _splice_page "${page}" "${s}" || return $?
        done < <(_user_facing_sections)
    else
        local page
        page="$(_page_for_section "${target}")"
        _splice_page "${page}" "${target}"
    fi
}

# Check mode: diff regenerated content against committed pages.
# Exits 0 when in sync, 1 on drift.
cmd_check() {
    local drift=0
    local s page tmp
    while IFS= read -r s; do
        [[ -z "${s}" ]] && continue
        page="$(_page_for_section "${s}")"
        tmp="$(mktemp)"
        cp "${page}" "${tmp}"
        if ! _splice_page "${tmp}" "${s}" >/dev/null 2>&1; then
            echo "[gen-config-reference] DRIFT (sentinels missing): ${page}"
            drift=1
            continue
        fi
        if ! diff -u "${page}" "${tmp}" >/dev/null 2>&1; then
            echo "[gen-config-reference] DRIFT: ${page}"
            diff -u "${page}" "${tmp}" | sed 's/^/  /'
            drift=1
        fi
    done < <(_user_facing_sections)

    if [[ ${drift} -eq 0 ]]; then
        echo "[gen-config-reference] OK -- all reference pages match the schema"
        return 0
    fi
    return 1
}

# CLI dispatch
if [[ $# -eq 0 ]]; then
    cat >&2 <<'EOF'
usage:
  gen-config-reference.sh <section>            # print to stdout
  gen-config-reference.sh --apply <section>    # splice one page
  gen-config-reference.sh --apply --all        # splice all pages
  gen-config-reference.sh --check              # CI drift detection
  gen-config-reference.sh --list               # list known sections
EOF
    exit 2
fi

case "$1" in
    --list)  _list_sections ;;
    --check) cmd_check ;;
    --apply) shift; cmd_apply "${1:---all}" ;;
    -h|--help)
        sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *) gen_section "$1" ;;
esac

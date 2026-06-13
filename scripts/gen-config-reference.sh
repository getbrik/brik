#!/usr/bin/env bash
# @description Generate the Quick reference markdown table for a brik.yml
#              section from the JSON Schema and splice it into the matching
#              page under docs/reference/configuration/.
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

# Render a 3-column table (Field | Type | Default) for a JSON object of
# properties (read from stdin), then one description line per field BELOW the
# table. Field/Type/Default stay scannable in the table; the description gets
# full width underneath. The schema is loaded via --slurpfile (a one-element
# array, hence $schema[0]) so $refs resolve. --argfile was removed in jq 1.8.
_render_fields() {
    local prefix="$1"
    local props
    props="$(cat)"
    printf '| Field | Type | Default |\n|-------|------|---------|\n'
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
                elif $r.items.type == "string" then "`array of strings`"
                else "`array`"
                end
              elif $r.type == "object" then "`object`"
              else "`\($r.type // "any")`"
              end;
        def fmt_default:
            if has("default") then "`\(.default | tostring)`" else "--" end;
        to_entries[]
        | "| `\($prefix).\(.key)` | \(.value | fmt_type) | \(.value | fmt_default) |"
    ' <<< "$props"
    printf '\n'
    jq -r --arg prefix "$prefix" '
        def fmt_desc:
            (.description // "(no description)") | gsub("\\n"; " ");
        to_entries[]
        | "- **`\($prefix).\(.key)`**\n\n  \(.value | fmt_desc)\n"
    ' <<< "$props"
}

# Emit a fenced YAML example for one object level: the dotted <prefix> becomes
# the nesting (release.candidate.docker -> release:/candidate:/docker:), then
# each "<key>: <value>" line is indented under it. Shows where a field lives in
# the tree, copy-pasteable and syntax-highlighted.
# Usage: _emit_example_yaml <prefix> <newline-separated "key: value" lines>
_emit_example_yaml() {
    local prefix="$1" lines="$2"
    local -a segs
    IFS='.' read -ra segs <<< "$prefix"
    local indent="" seg line
    printf '```yaml\n'
    for seg in "${segs[@]}"; do
        printf '%s%s:\n' "$indent" "$seg"
        indent+="  "
    done
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        printf '%s%s\n' "$indent" "$line"
    done <<< "$lines"
    printf '```\n'
}

# Recursively render a level of properties (read from stdin): the leaf fields
# of this level as a table + descriptions, then a sub-heading and a recursive
# render for every nested object child. This is what describes deep objects
# such as release.candidate.docker in full instead of as an opaque `object`.
# Usage: printf '%s' "<properties-json>" | _render_level <prefix> <heading-hashes>
_render_level() {
    local prefix="$1" hashes="$2"
    local props
    props="$(cat)"

    local leaf_props nested_keys
    leaf_props="$(jq '
        with_entries(select(.value.type != "object" or (.value.properties | not)))
    ' <<< "${props}")"
    nested_keys="$(jq -r '
        to_entries[]
        | select(.value.type == "object" and (.value.properties | type == "object"))
        | .key
    ' <<< "${props}")"

    if [[ "$(jq 'length' <<< "${leaf_props}")" -gt 0 ]]; then
        printf '%s\n' "${leaf_props}" | _render_fields "${prefix}"
        echo

        # One composed, tree-structured YAML example for this level's leaves
        # (only fields that declare a schema example), instead of a context-less
        # inline example per field.
        local ex_lines
        ex_lines="$(jq -r '
            to_entries[]
            | select((.value.examples // []) | length > 0)
            | (.value.examples[0] | type) as $t
            | select($t != "object" and $t != "array")
            | "\(.key): \(.value.examples[0] | tostring)"
        ' <<< "${leaf_props}")"
        if [[ -n "${ex_lines}" ]]; then
            printf '*Example*\n\n'
            _emit_example_yaml "${prefix}" "${ex_lines}"
            echo
        fi
    fi

    if [[ -n "${nested_keys}" ]]; then
        local key ndesc
        while IFS= read -r key; do
            [[ -z "${key}" ]] && continue
            printf '%s `%s.%s`\n\n' "${hashes}" "${prefix}" "${key}"
            ndesc="$(jq -r --arg k "${key}" '.[$k].description // empty | gsub("\n"; " ")' <<< "${props}")"
            [[ -n "${ndesc}" ]] && printf '%s\n\n' "${ndesc}"
            jq --arg k "${key}" '.[$k].properties' <<< "${props}" \
                | _render_level "${prefix}.${key}" "${hashes}#"
        done <<< "${nested_keys}"
    fi
}

# Render a single section. Leaf properties render as a table + descriptions;
# nested object children (release.trigger, release.candidate.docker, ...) get a
# sub-heading and are described recursively to any depth.
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
        local single
        single="$(jq "${jq_path}" "${SCHEMA}")"
        printf '| Field | Type | Default |\n|-------|------|---------|\n'
        jq -r --arg name "$section" '
            def fmt_type:
                if .const then "const (`\(.const)`)"
                elif .enum then "enum (\(.enum | map("`\(.)`") | join(", ")))"
                else "`\(.type // "any")`"
                end;
            def fmt_default:
                if has("default") then "`\(.default | tostring)`"
                elif .const then "`\(.const)`"
                else "--"
                end;
            "| `\($name)` | \(fmt_type) | \(fmt_default) |"
        ' <<< "$single"
        printf '\n'
        jq -r --arg name "$section" '
            "- **`\($name)`**\n\n  \((.description // "(no description)") | gsub("\\n"; " "))"
        ' <<< "$single"
        echo
        return 0
    fi

    # Object section: render this level's leaves, then recurse into nested
    # object children so sub-objects are described in full, not left opaque.
    jq "${jq_path}.properties // {}" "${SCHEMA}" | _render_level "${section}" "###"
}

# Sections that have a page under docs/reference/configuration/. Internal $defs
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
    echo "${REPO_ROOT}/docs/reference/configuration/${section}.md"
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

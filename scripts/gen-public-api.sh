#!/usr/bin/env bash
# @description Generate the "Public API surface" function tables under
#              docs/contributing/test-matrix/<notion>-public-api.md from the
#              actual function definitions in the source tree.
#
# Each page carries an auto-managed region marked with HTML sentinels:
#
#   <!-- BEGIN AUTO-GENERATED: public-api -->
#   ...table + total...
#   <!-- END AUTO-GENERATED -->
#
# Everything outside the sentinels (title, Source line, curated prose tails)
# is hand-owned and preserved. On first run the sentinels are inserted around
# the existing table+total block.
#
# Usage:
#   ./scripts/gen-public-api.sh <notion>          # print the region to stdout
#   ./scripts/gen-public-api.sh --apply <notion>  # splice into the page
#   ./scripts/gen-public-api.sh --apply --all     # splice every page
#   ./scripts/gen-public-api.sh --check           # fail if any page is stale
#   ./scripts/gen-public-api.sh --list            # list notions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCS_DIR="${REPO_ROOT}/docs/contributing/test-matrix"
BEGIN_MARK='<!-- BEGIN AUTO-GENERATED: public-api -->'
END_MARK='<!-- END AUTO-GENERATED -->'

# A function definition is a line that starts (no indentation) with a dotted
# name immediately followed by `()`. Indented (nested) helpers are not part of
# the public surface and are excluded.
DEF_RE='^[A-Za-z_][A-Za-z0-9._]*\(\)'

NOTIONS=(cli deployments execution execution-environment findings \
         package-managers planning registry rollout stacks stages transverse)

# Echo the *.sh files (repo-relative) that make up a notion's source.
_notion_files() {
    cd "${REPO_ROOT}"
    case "$1" in
        cli)                   find lib/cli -name '*.sh' ;;
        deployments)           find lib/deployments -name '*.sh' ;;
        execution)             find lib/pipeline -name '*.sh' ;;
        execution-environment) find shared-libs/common shared-libs/gitlab \
                                    shared-libs/jenkins shared-libs/local -name '*.sh' ;;
        findings)              find lib/transverse/findings.sh lib/transverse/findings \
                                    -name '*.sh' 2>/dev/null ;;
        package-managers)      find lib/package-managers -name '*.sh' ;;
        planning)              find lib/planning -name '*.sh' ;;
        registry)              find lib/registry -name '*.sh' ;;
        rollout)               find lib/rollout -name '*.sh' ;;
        stacks)                find lib/stacks -name '*.sh' ;;
        stages)                find lib/stages -name '*.sh' ;;
        transverse)            find lib/transverse -name '*.sh' ;;
        *) echo "[gen-public-api] unknown notion: $1" >&2; return 2 ;;
    esac
}

# Build the auto-managed region (table + Total block) for a notion.
_gen_region() {
    local notion="$1"
    local strip="lib/" three_col=0
    [[ "$notion" == "execution-environment" ]] && { strip=""; three_col=1; }

    local rows="" count=0 file rel name ln def plat
    declare -A seen=()
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        rel="${file#"$strip"}"
        while IFS=: read -r ln def; do
            name="${def%%(*}"
            [[ -n "${seen[$name]:-}" ]] && continue
            seen[$name]=1
            count=$((count + 1))
            if [[ "$three_col" == 1 ]]; then
                plat="$(printf '%s' "$file" | cut -d/ -f2)"
                rows+="| \`${name}\` | ${plat} | \`${rel}:${ln}\` |"$'\n'
            else
                rows+="| \`${name}\` | \`${rel}:${ln}\` |"$'\n'
            fi
        done < <(grep -nE "${DEF_RE}" "${REPO_ROOT}/${file}" || true)
    done < <(_notion_files "$notion" | sort)

    if [[ "$three_col" == 1 ]]; then
        printf '| Function| Platform | Source file |\n|---|---|---|\n'
    else
        printf '| Function| Source file |\n|---|---|\n'
    fi
    printf '%s\n## Total\n\n**%d unique public functions** in notion `%s`.\n' \
        "$rows" "$count" "$notion"
}

_page_for() { printf '%s/%s-public-api.md' "${DOCS_DIR}" "$1"; }

# Print the page with the auto-managed region replaced by fresh content.
# Inserts the sentinels around the existing table+total block on first run.
# The region is passed via a file (awk -v cannot carry embedded newlines).
_render_page() {
    local notion="$1" page regfile
    page="$(_page_for "$notion")"
    regfile="$(mktemp "${TMPDIR:-/tmp}/brik-public-api.XXXXXX")"
    _gen_region "$notion" > "$regfile"

    if grep -qF "${BEGIN_MARK}" "$page"; then
        awk -v b="${BEGIN_MARK}" -v e="${END_MARK}" -v rf="${regfile}" '
            $0 == b { print; while ((getline l < rf) > 0) print l; close(rf); skip = 1; next }
            $0 == e { skip = 0 }
            !skip   { print }
        ' "$page"
    else
        # First run: wrap the existing "| Function ... ## Total ... **N ...**"
        # block in sentinels and replace it with the generated region.
        awk -v b="${BEGIN_MARK}" -v e="${END_MARK}" -v rf="${regfile}" '
            !done && $0 ~ /^\| Function/ {
                print b; while ((getline l < rf) > 0) print l; close(rf); print e
                done = 1; intbl = 1; next
            }
            done && intbl {
                if ($0 ~ /unique public functions/) { intbl = 0 }
                next
            }
            { print }
        ' "$page"
    fi
    rm -f "$regfile"
}

cmd_apply() {
    local target="$1" notion
    if [[ "$target" == "--all" || -z "$target" ]]; then
        for notion in "${NOTIONS[@]}"; do cmd_apply "$notion"; done
        return 0
    fi
    local page; page="$(_page_for "$target")"
    [[ -f "$page" ]] || { echo "[gen-public-api] no page: $page" >&2; return 2; }
    local tmp; tmp="$(mktemp)"
    _render_page "$target" > "$tmp"
    mv "$tmp" "$page"
    echo "[gen-public-api] updated ${target}-public-api.md"
}

cmd_check() {
    local notion page rc=0
    for notion in "${NOTIONS[@]}"; do
        page="$(_page_for "$notion")"
        [[ -f "$page" ]] || { echo "[gen-public-api] missing: $page" >&2; rc=1; continue; }
        if ! diff -q <(_render_page "$notion") "$page" >/dev/null; then
            echo "[gen-public-api] DRIFT: ${notion}-public-api.md is stale" >&2
            rc=1
        fi
    done
    [[ "$rc" == 0 ]] && echo "[gen-public-api] OK -- all public-api pages match the source"
    return "$rc"
}

main() {
    case "${1:-}" in
        --list)  printf '%s\n' "${NOTIONS[@]}" ;;
        --check) cmd_check ;;
        --apply) shift; cmd_apply "${1:-}" ;;
        "" | -h | --help)
            sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
        *)       _gen_region "$1" ;;
    esac
}

main "$@"

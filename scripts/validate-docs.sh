#!/usr/bin/env bash
# @description Validate every fenced ```yaml block in docs/reference/configuration/**/*.md
#              against the Brik JSON Schema.
#
# Each block is written to a tempfile and piped through `bin/brik validate`.
# Exit code is 0 when every block validates, non-zero otherwise.
#
# Usage:
#   ./scripts/validate-docs.sh             # walk docs/reference/configuration/
#   ./scripts/validate-docs.sh path/to.md  # validate a single file

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BRIK_BIN="${REPO_ROOT}/bin/brik"
DOCS_ROOT="${REPO_ROOT}/docs/reference/configuration"

if [[ ! -x "${BRIK_BIN}" ]]; then
    echo "[validate-docs] error: ${BRIK_BIN} not found or not executable" >&2
    exit 2
fi

declare -a files
if [[ $# -gt 0 ]]; then
    files=("$@")
else
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "${DOCS_ROOT}" -type f -name '*.md' -print0 | sort -z)
fi

if [[ ${#files[@]} -eq 0 ]]; then
    echo "[validate-docs] no markdown files found under ${DOCS_ROOT}"
    exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
index="${tmpdir}/index.tsv"
: > "${index}"

# Extract every fenced ```yaml block from a markdown file. Each block is
# written to ${tmpdir}/block-NNNNN.yml and registered in ${index}.
block_id=0
for md in "${files[@]}"; do
    if [[ ! -f "${md}" ]]; then
        echo "[validate-docs] skipping missing file: ${md}" >&2
        continue
    fi

    in_block=0
    start_line=0
    line_no=0
    out=""
    while IFS= read -r line; do
        line_no=$((line_no + 1))
        if [[ ${in_block} -eq 0 ]]; then
            if [[ "${line}" =~ ^\`\`\`yaml[[:space:]]*$ ]]; then
                in_block=1
                start_line=$((line_no + 1))
                block_id=$((block_id + 1))
                out="$(printf '%s/block-%05d.yml' "${tmpdir}" "${block_id}")"
                : > "${out}"
                printf '%s\t%s\t%s\n' "${md}" "${start_line}" "${out}" >> "${index}"
            fi
        else
            if [[ "${line}" =~ ^\`\`\`[[:space:]]*$ ]]; then
                in_block=0
                out=""
            else
                printf '%s\n' "${line}" >> "${out}"
            fi
        fi
    done < "${md}"
done

total=0
skipped=0
failures=0
while IFS=$'\t' read -r src start out; do
    [[ -z "${src}" ]] && continue

    # Only validate blocks that look like a complete brik.yml (i.e. carry
    # a top-level `version:` key at column 0). Anything else is an
    # illustrative fragment and is skipped silently.
    if ! grep -qE '^version:[[:space:]]' "${out}"; then
        skipped=$((skipped + 1))
        continue
    fi

    total=$((total + 1))
    if "${BRIK_BIN}" validate --config "${out}" >/dev/null 2>&1; then
        :
    else
        failures=$((failures + 1))
        echo "[validate-docs] FAIL ${src}:${start}"
        "${BRIK_BIN}" validate --config "${out}" 2>&1 | sed 's/^/  /'
    fi
done < "${index}"

if [[ ${total} -eq 0 ]]; then
    echo "[validate-docs] no fenced \`\`\`yaml blocks found"
    exit 0
fi

if [[ ${failures} -eq 0 ]]; then
    if [[ ${skipped} -gt 0 ]]; then
        echo "[validate-docs] OK -- ${total} block(s) validated, ${skipped} fragment(s) skipped"
    else
        echo "[validate-docs] OK -- ${total} block(s) validated"
    fi
    exit 0
fi

echo "[validate-docs] ${failures}/${total} block(s) failed"
exit 1

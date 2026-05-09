#!/usr/bin/env bash
# @module transverse/format
# @description Generic Unicode table renderer reading delimiter-separated
# input from stdin. Output uses single-trait box-drawing characters and
# is written to stderr to stay consistent with logging and banners.

# Guard against double-sourcing
[[ -n "${_BRIK_FORMAT_LOADED:-}" ]] && return 0
_BRIK_FORMAT_LOADED=1

# format.table - render a Unicode table to stderr from stdin.
# First non-empty line is the header. Default delimiter TAB; override
# with --delim <char>.
#
# Cell widths are computed from bash ${#cell} so all cells are expected
# to be plain text without ANSI escape sequences. Use plain Unicode
# glyphs (e.g. ✓ ✗) instead of color for cell content; emit colored
# context lines via log.success / log.error before or after the table.
#
# Usage:
#   { printf 'name|age\n'; printf 'alice|30\n'; } | format.table --delim '|'
format.table() {
    local delim=$'\t'
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --delim) delim="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local -a raw=()
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        raw+=("$line")
    done
    local n=${#raw[@]}
    (( n < 1 )) && return 0

    # Parse rows into a flat array (row-major) and compute column widths.
    local cols=0
    local -a flat=()
    local -a widths=()
    local r c
    for ((r=0; r<n; r++)); do
        local -a cells=()
        IFS="$delim" read -ra cells <<< "${raw[r]}"
        if (( r == 0 )); then
            cols=${#cells[@]}
            for ((c=0; c<cols; c++)); do widths[c]=0; done
        fi
        for ((c=0; c<cols; c++)); do
            local cell="${cells[c]:-}"
            flat[r * cols + c]="$cell"
            (( ${#cell} > widths[c] )) && widths[c]=${#cell}
        done
    done

    {
        # Top rule
        printf '┌'
        for ((c=0; c<cols; c++)); do
            local w=$((widths[c] + 2))
            local seg="" k
            for ((k=0; k<w; k++)); do seg+="─"; done
            printf '%s' "$seg"
            (( c < cols - 1 )) && printf '┬'
        done
        printf '┐\n'

        # Header row, mid rule, body rows.
        for ((r=0; r<n; r++)); do
            printf '│'
            for ((c=0; c<cols; c++)); do
                local cell="${flat[r * cols + c]}"
                local pad=$((widths[c] - ${#cell}))
                local sp="" k
                for ((k=0; k<pad; k++)); do sp+=" "; done
                printf ' %s%s │' "$cell" "$sp"
            done
            printf '\n'
            if (( r == 0 && n > 1 )); then
                printf '├'
                for ((c=0; c<cols; c++)); do
                    local w=$((widths[c] + 2))
                    local seg="" k
                    for ((k=0; k<w; k++)); do seg+="─"; done
                    printf '%s' "$seg"
                    (( c < cols - 1 )) && printf '┼'
                done
                printf '┤\n'
            fi
        done

        # Bottom rule
        printf '└'
        for ((c=0; c<cols; c++)); do
            local w=$((widths[c] + 2))
            local seg="" k
            for ((k=0; k<w; k++)); do seg+="─"; done
            printf '%s' "$seg"
            (( c < cols - 1 )) && printf '┴'
        done
        printf '┘\n'
    } >&2
}

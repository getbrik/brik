#!/usr/bin/env bash
# @module banner
# @description Visual banners for pipeline and stage delimitation.
#
# Provides two functions:
# - banner.brik: ASCII logo + version (called once at pipeline start)
# - banner.stage: stage delimiter (called before each stage)
#
# Both write to stderr to stay consistent with logging.sh
# and avoid polluting stdout (which may carry data).

# Guard against double-sourcing
[[ -n "${_BRIK_BANNER_LOADED:-}" ]] && return 0
_BRIK_BANNER_LOADED=1

# Path to the Braille art logo file (next to this script)
_BRIK_BANNER_DIR="${BASH_SOURCE[0]%/*}"

# Display the BRIK Lego brick logo with version (Braille art).
# The version is centered below the brick.
# Usage: banner.brik <version>
banner.brik() {
    local version="${1:-}"
    local logo_file="${_BRIK_BANNER_DIR}/ascii-logo.txt"

    echo >&2
    if [[ -f "$logo_file" ]]; then
        cat "$logo_file" >&2
    fi

    if [[ -n "$version" ]]; then
        local label="v${version#v}"
        printf '%s\n' "$label" >&2
    fi

    echo >&2
}

# Total banner width in characters. Inner content area is total_width - 2.
_BRIK_BANNER_WIDTH=100

# Repeat a single character n times. Safer than `printf '%*s' n ''` + `tr`
# when the character is multi-byte UTF-8 (box-drawing chars).
_banner._repeat() {
    local char="$1"
    local n="$2"
    local out=""
    local i
    for ((i=0; i<n; i++)); do
        out+="$char"
    done
    printf '%s' "$out"
}

# Build a metadata line content (without the surrounding `│ │`), padded
# to width. Format: "  KEY:     VALUE" with KEY column 8 chars wide.
_banner._meta_line() {
    local key="$1"
    local value="$2"
    local width="$3"
    local content
    content="  $(printf '%-8s' "${key}:")${value}"
    if (( ${#content} > width )); then
        content="${content:0:width}"
    fi
    local pad
    pad="$(_banner._repeat ' ' $((width - ${#content})))"
    printf '%s%s' "$content" "$pad"
}

# Display a stage banner: a single-trait box with the stage name spaced
# and centered on the title line, then a blank line, then the runner
# metadata. Missing runner is shown as '-'.
# Usage: banner.stage <stage_name> [<runner>]
#
# Note: a third positional argument was historically accepted for a
# per-stage "tech" identifier (e.g. "node 22.5.0"). It was never wired up
# (BRIK_STAGE_TECH was never set anywhere in lib/), always rendered as '-',
# and was removed for clarity. Callers passing a 3rd arg are silently
# ignored.
banner.stage() {
    local stage_name="${1:-}"
    local runner="${2:-}"
    [[ -z "$runner" ]] && runner="-"

    local upper
    upper="$(printf '%s' "$stage_name" | tr '[:lower:]' '[:upper:]')"

    # Spaced title: "S A S T". One space between each character.
    local spaced=""
    local i ch
    for ((i=0; i<${#upper}; i++)); do
        ch="${upper:$i:1}"
        if [[ -z "$spaced" ]]; then
            spaced="$ch"
        else
            spaced="${spaced} ${ch}"
        fi
    done

    local inner=$((_BRIK_BANNER_WIDTH - 2))
    local hr blank
    hr="$(_banner._repeat '─' "$inner")"
    blank="$(_banner._repeat ' ' "$inner")"

    # Center the title in the inner width.
    local pad_total=$(( inner - ${#spaced} ))
    local pad_left=$(( pad_total / 2 ))
    local pad_right=$(( pad_total - pad_left ))
    local left_sp right_sp
    left_sp="$(_banner._repeat ' ' "$pad_left")"
    right_sp="$(_banner._repeat ' ' "$pad_right")"

    local runner_line
    runner_line="$(_banner._meta_line "runner" "$runner" "$inner")"

    {
        echo
        printf '┌%s┐\n' "$hr"
        printf '│%s%s%s│\n' "$left_sp" "$spaced" "$right_sp"
        printf '│%s│\n' "$blank"
        printf '│%s│\n' "$runner_line"
        printf '└%s┘\n' "$hr"
    } >&2
}

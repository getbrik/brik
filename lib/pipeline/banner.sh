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

# shellcheck source=../transverse/render.sh
. "${BASH_SOURCE[0]%/*}/../transverse/render.sh"

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
    {
        echo
        {
            render.center "$spaced" --width "$inner"
            render.blank "$inner"
            render.kv "runner" "$runner" --key-width 6 --width "$inner"
        } | render.box --inner-width "$inner"
    } >&2
}

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

# Display a stage delimiter banner.
# The stage name is uppercased and left-aligned between two lines.
# Usage: banner.stage <stage_name>
banner.stage() {
    local stage_name="${1:-}"
    local upper_name
    upper_name="$(printf '%s' "$stage_name" | tr '[:lower:]' '[:upper:]')"

    cat >&2 <<EOF

══════════════════════════════════
  ${upper_name}
══════════════════════════════════
EOF
}

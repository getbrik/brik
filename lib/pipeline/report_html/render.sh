#!/usr/bin/env bash
# @module report_html.render
# @requires jq, sed
# @description Orchestrator for the HTML pipeline report.
#
# The HTML document is assembled from three pieces:
#   - head.sh  : <!DOCTYPE>, <head>, opening <body>, brand strip, body shell,
#                opening of the JSON data island.
#   - the aggregate-report.json itself, streamed verbatim into the data
#     island with `</` escaped to `<\/` so a literal "</script>" in any
#     payload cannot terminate the island.
#   - tail.sh  : closing of the JSON island, inline JS, closing tags.
#
# CSS lives in styles.css (sibling), JS in app.js (sibling); both are
# `cat`-ed into <style>/<script> tags inline so the output document is
# self-contained and renders offline with no external requests.
#
# Public API (private to lib/pipeline/report.sh):
#   _report._render_html <backend.json>
#     Print the HTML document on stdout. Returns BRIK_EXIT_IO_FAILURE when
#     the backend file is missing or unreadable.

[[ -n "${_BRIK_REPORT_HTML_RENDER_LOADED:-}" ]] && return 0
_BRIK_REPORT_HTML_RENDER_LOADED=1

# shellcheck source=../logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../logging.sh"
# shellcheck source=../error.sh
[[ -z "${_BRIK_ERROR_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../error.sh"
# shellcheck source=head.sh
. "${BASH_SOURCE[0]%/*}/head.sh"
# shellcheck source=tail.sh
. "${BASH_SOURCE[0]%/*}/tail.sh"

_report._render_html() {
    local backend="$1"
    if [[ -z "$backend" || ! -f "$backend" ]]; then
        log.error "report not found: $backend"
        return "$BRIK_EXIT_IO_FAILURE"
    fi
    if ! command -v jq >/dev/null 2>&1; then
        log.error "jq is required for _report._render_html"
        return "$BRIK_EXIT_MISSING_DEP"
    fi

    local items_count
    items_count="$(jq -r '
        [.stages[]? | (.business.findings.items // [])[]] | length
    ' "$backend" 2>/dev/null)"
    [[ "$items_count" =~ ^[0-9]+$ ]] || items_count=0

    _report._render_html_head "$items_count"

    # Embed JSON: escape </ to <\/ so a literal </script> in any payload
    # cannot terminate the data island. JSON parsers treat \/ as /.
    sed 's|</|<\\/|g' "$backend"

    _report._render_html_tail
}

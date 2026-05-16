#!/usr/bin/env bash
# @module report_html
# @requires jq, sed
# @description Render the aggregate pipeline report as a single self-contained
#   HTML5 document. CSS and JS are inlined; the source aggregate JSON is
#   embedded as a JSON data island. Visual direction: dark luxury / Plumber
#   radar, severity-coded findings panel, lifecycle timeline.
#
# Public API (private to lib/pipeline/report.sh):
#   _report._render_html <backend.json>
#     Print the HTML document on stdout. Returns BRIK_EXIT_IO_FAILURE when
#     the backend file is missing or unreadable.

[[ -n "${_BRIK_REPORT_HTML_LOADED:-}" ]] && return 0
_BRIK_REPORT_HTML_LOADED=1

# shellcheck source=logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/logging.sh"
# shellcheck source=error.sh
[[ -z "${_BRIK_ERROR_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/error.sh"
# shellcheck source=_branding.sh
[[ -z "${_BRIK_PIPELINE_BRANDING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/_branding.sh"

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

# KCOV_EXCL_START -- HTML/CSS/JS template body, not bash code
_report._render_html_head() {
    local count="$1"
    cat <<'HEAD_OPEN'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Brik Pipeline Report</title>
<style>
HEAD_OPEN
    # CSS lives in report_html/styles.css so it stays linter-friendly
    # (stylelint) and the heredoc body stays under 100 lines. The
    # surrounding <style></style> tags are kept inline so the output
    # remains a single self-contained HTML document.
    cat "${BASH_SOURCE[0]%/*}/report_html/styles.css"
    cat <<HEAD_DATA
</style>
</head>
<body data-findings-count="${count}">
HEAD_DATA
    # Brand strip and footer credit are interpolated from _branding.sh so
    # the home URL and logo stay in a single source of truth. The remaining
    # body shell stays in a quoted heredoc since it has no interpolation.
    cat <<HEAD_BRAND
<main>
  <header class="brand">
    <a href="${BRIK_HOME_URL}" target="_blank" rel="noopener" aria-label="Brik on GitHub">
      <img src="data:image/png;base64,${BRIK_LOGO_B64}" alt="Brik" width="28" height="28">
      <span class="brand-name">Brik</span>
    </a>
  </header>
HEAD_BRAND
    cat <<'HEAD_BODY'
  <section id="hero" class="card hero" aria-label="Pipeline summary"></section>
  <section id="timeline" class="card" aria-label="Lifecycle timeline">
    <h2>Lifecycle</h2>
    <div class="timeline-rail" id="timeline-rail"></div>
  </section>
  <section id="meta" class="card" aria-label="Policy and outcome">
    <h2>Policy and outcome</h2>
    <div class="kv-grid" id="meta-grid"></div>
  </section>
  <section id="business" class="card" aria-label="Per-stage business">
    <h2>Per-stage payload</h2>
    <div id="business-list"></div>
  </section>
HEAD_BODY
    cat <<HEAD_FOOTER
  <footer>Powered by <a href="${BRIK_HOME_URL}" target="_blank" rel="noopener">brik</a> - Write once, ship everywhere.</footer>
</main>
<script type="application/json" id="brik-report">
HEAD_FOOTER
}

_report._render_html_tail() {
    cat <<'TAIL_OPEN'
</script>
<script>
TAIL_OPEN
    # JS lives in report_html/app.js so it stays linter-friendly (eslint)
    # and the heredoc body stays small. The surrounding <script></script>
    # tags are kept inline so the output remains a single self-contained
    # HTML document with no external requests.
    cat "${BASH_SOURCE[0]%/*}/report_html/app.js"
    cat <<'TAIL_CLOSE'
</script>
</body>
</html>
TAIL_CLOSE
}
# KCOV_EXCL_STOP

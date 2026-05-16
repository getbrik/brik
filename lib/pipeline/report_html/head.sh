#!/usr/bin/env bash
# @module report_html.head
# @description Renders the <!DOCTYPE>, <head>, opening <body>, brand strip,
#   static body section anchors, and the opening of the JSON data island.
#
# CSS is loaded from sibling styles.css; the surrounding <style></style>
# tags stay inline so the output is self-contained. Brand strip and footer
# credit interpolate ${BRIK_HOME_URL} / ${BRIK_LOGO_B64} from _branding.sh.

[[ -n "${_BRIK_REPORT_HTML_HEAD_LOADED:-}" ]] && return 0
_BRIK_REPORT_HTML_HEAD_LOADED=1

# shellcheck source=../_branding.sh
[[ -z "${_BRIK_PIPELINE_BRANDING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../_branding.sh"

# KCOV_EXCL_START -- HTML/CSS template body, not bash code
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
    cat "${BASH_SOURCE[0]%/*}/styles.css"
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
# KCOV_EXCL_STOP

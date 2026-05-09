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
:root {
  color-scheme: dark;
  --canvas: #0b0d12;
  --canvas-grad: radial-gradient(at 20% -10%, oklch(28% 0.06 250 / 0.55) 0%, transparent 55%),
                 radial-gradient(at 90% 0%, oklch(30% 0.10 25 / 0.25) 0%, transparent 50%),
                 var(--canvas);
  --surface: rgba(255, 255, 255, 0.035);
  --surface-strong: rgba(255, 255, 255, 0.06);
  --surface-hi: rgba(255, 255, 255, 0.09);
  --border: rgba(255, 255, 255, 0.08);
  --border-strong: rgba(255, 255, 255, 0.16);
  --text: oklch(96% 0.01 250);
  --text-muted: oklch(72% 0.02 250);
  --text-faint: oklch(52% 0.02 250);
  --link: oklch(78% 0.12 230);
  --critical: oklch(64% 0.22 25);
  --high: oklch(72% 0.18 50);
  --medium: oklch(82% 0.14 80);
  --low: oklch(70% 0.10 230);
  --info: oklch(60% 0.04 250);
  --success: oklch(72% 0.18 165);
  --failed: oklch(64% 0.22 25);
  --skipped: oklch(55% 0.02 250);
  --warning: oklch(78% 0.16 65);
  --shadow-card: 0 1px 0 rgba(255,255,255,0.04) inset, 0 14px 40px rgba(0,0,0,0.4);
  --radius-card: 18px;
  --radius-chip: 999px;
  --radius-tile: 12px;
  --space-1: 4px; --space-2: 8px; --space-3: 12px; --space-4: 16px;
  --space-5: 24px; --space-6: 32px; --space-7: 48px; --space-8: 64px;
  --font-body: "Inter", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  --font-mono: "JetBrains Mono", ui-monospace, "SF Mono", Menlo, Consolas, monospace;
}
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body {
  background: var(--canvas-grad);
  color: var(--text);
  font-family: var(--font-body);
  font-size: 15px;
  line-height: 1.55;
  min-height: 100vh;
  -webkit-font-smoothing: antialiased;
}
main {
  max-width: 1180px;
  margin: 0 auto;
  padding: var(--space-7) var(--space-5) var(--space-8);
  display: flex; flex-direction: column; gap: var(--space-6);
}
a { color: var(--link); text-decoration: none; border-bottom: 1px solid transparent; transition: border-color .15s; }
a:hover { border-bottom-color: var(--link); }
.mono { font-family: var(--font-mono); font-feature-settings: "tnum" 1; }
.muted { color: var(--text-muted); }
.faint { color: var(--text-faint); }
.card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-card);
  padding: var(--space-6);
  backdrop-filter: blur(28px) saturate(140%);
  -webkit-backdrop-filter: blur(28px) saturate(140%);
  box-shadow: var(--shadow-card);
}
.card h2 {
  margin: 0 0 var(--space-4);
  font-size: 13px;
  font-weight: 600;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--text-faint);
}
.hero { display: flex; flex-direction: column; gap: var(--space-4); }
.hero .top-row { display: flex; align-items: baseline; gap: var(--space-4); flex-wrap: wrap; }
.hero h1 {
  margin: 0;
  font-size: clamp(2rem, 1.4rem + 2.4vw, 3.4rem);
  font-weight: 700;
  letter-spacing: -0.02em;
  line-height: 1.0;
}
.hero .pipeline-id { font-family: var(--font-mono); font-size: 18px; color: var(--text-muted); }
.hero .pill {
  display: inline-flex; align-items: center; gap: 6px;
  padding: 5px 12px;
  border-radius: var(--radius-chip);
  font-size: 12px; font-weight: 600;
  letter-spacing: 0.08em; text-transform: uppercase;
  border: 1px solid currentColor;
  background: color-mix(in oklch, currentColor 8%, transparent);
}
.hero .pill.success { color: var(--success); }
.hero .pill.failed  { color: var(--failed); box-shadow: 0 0 32px -10px var(--failed); }
.hero .pill.skipped { color: var(--skipped); }
.hero .pill.warning { color: var(--warning); }
.hero .meta { display: flex; flex-wrap: wrap; gap: var(--space-5); font-size: 14px; color: var(--text-muted); }
.hero .meta span strong { color: var(--text); font-weight: 500; margin-right: 4px; }
.hero .commit { font-size: 14px; color: var(--text-muted); }
.hero .commit .sha { color: var(--text); }
.hero .commit .subject { font-style: italic; }

.timeline-rail {
  display: flex; gap: var(--space-3); align-items: stretch;
  overflow-x: auto; padding: var(--space-2) 0 var(--space-3);
  scrollbar-color: var(--border-strong) transparent;
}
.timeline-cell {
  flex: 0 0 auto; min-width: 130px;
  padding: var(--space-4);
  background: var(--surface-strong);
  border: 1px solid var(--border);
  border-radius: var(--radius-tile);
  display: flex; flex-direction: column; gap: 4px;
  transition: transform .15s, border-color .15s;
}
.timeline-cell:hover { transform: translateY(-2px); border-color: var(--border-strong); }
.timeline-cell .stage-name { font-weight: 600; font-size: 14px; }
.timeline-cell .stage-status {
  font-family: var(--font-mono); font-size: 11px;
  letter-spacing: 0.08em; text-transform: uppercase;
}
.timeline-cell .stage-status.success { color: var(--success); }
.timeline-cell .stage-status.failed  { color: var(--failed); }
.timeline-cell .stage-status.skipped { color: var(--skipped); }
.timeline-cell .stage-status.warning { color: var(--warning); }
.timeline-cell .stage-duration { font-size: 12px; color: var(--text-muted); font-family: var(--font-mono); }
.timeline-cell.parallel-group {
  background: transparent; border-style: dashed;
  padding: var(--space-3);
  display: flex; flex-direction: column; gap: var(--space-2);
}
.timeline-cell.parallel-group .group-label {
  font-size: 10px; letter-spacing: 0.16em; text-transform: uppercase;
  color: var(--text-faint); align-self: center; margin-bottom: var(--space-1);
}
.timeline-cell.parallel-group .group-children {
  display: grid; grid-template-columns: repeat(2, minmax(110px, 1fr)); gap: var(--space-2);
}
.timeline-cell.parallel-group .group-children .timeline-cell {
  min-width: 0; padding: var(--space-2) var(--space-3);
}
.timeline-cell .stage-job { font-size: 11px; }

.findings-toolbar {
  display: flex; flex-wrap: wrap; gap: var(--space-3);
  align-items: center; justify-content: space-between;
  margin-bottom: var(--space-4);
}
.findings-counts { display: flex; gap: var(--space-3); flex-wrap: wrap; font-size: 13px; color: var(--text-muted); }
.findings-counts .count { display: inline-flex; align-items: center; gap: 6px; }
.findings-counts .count .dot {
  width: 8px; height: 8px; border-radius: 50%;
  background: currentColor; box-shadow: 0 0 8px currentColor;
}
.sev-critical { color: var(--critical); }
.sev-high     { color: var(--high); }
.sev-medium   { color: var(--medium); }
.sev-low      { color: var(--low); }
.sev-info     { color: var(--info); }
.findings-filters { display: flex; gap: var(--space-2); align-items: center; flex-wrap: wrap; }
.chip {
  padding: 5px 12px;
  border-radius: var(--radius-chip);
  border: 1px solid var(--border);
  background: var(--surface);
  color: var(--text-muted);
  font-size: 12px; font-weight: 500;
  cursor: pointer;
  transition: background .15s, color .15s, border-color .15s;
  text-transform: capitalize;
}
.chip:hover { background: var(--surface-hi); color: var(--text); }
.chip.active { background: var(--surface-hi); color: var(--text); border-color: var(--border-strong); }
.chip[data-sev="critical"].active { color: var(--critical); border-color: color-mix(in oklch, var(--critical) 50%, transparent); }
.chip[data-sev="high"].active     { color: var(--high);     border-color: color-mix(in oklch, var(--high) 50%, transparent); }
.chip[data-sev="medium"].active   { color: var(--medium);   border-color: color-mix(in oklch, var(--medium) 50%, transparent); }
.chip[data-sev="low"].active      { color: var(--low);      border-color: color-mix(in oklch, var(--low) 50%, transparent); }
.chip[data-sev="info"].active     { color: var(--info);     border-color: color-mix(in oklch, var(--info) 50%, transparent); }
.search-input {
  flex: 1 1 220px;
  padding: 7px 12px;
  border-radius: var(--radius-chip);
  border: 1px solid var(--border);
  background: var(--surface);
  color: var(--text);
  font-family: var(--font-body);
  font-size: 13px;
  min-width: 180px;
  margin-bottom: var(--space-3);
}
.search-input:focus { outline: none; border-color: var(--border-strong); background: var(--surface-strong); }
.findings-list { display: flex; flex-direction: column; gap: var(--space-2); }
.finding {
  display: grid;
  grid-template-columns: auto 1fr auto;
  gap: var(--space-3);
  align-items: center;
  padding: var(--space-3) var(--space-4);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-tile);
  cursor: pointer;
  transition: background .15s, border-color .15s;
}
.finding:hover { background: var(--surface-strong); border-color: var(--border-strong); }
.finding[data-open="true"] { background: var(--surface-strong); border-color: var(--border-strong); }
.finding .sev-dot {
  width: 10px; height: 10px; border-radius: 50%;
  background: currentColor; box-shadow: 0 0 12px currentColor;
}
.finding .ident { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.finding .ident .id { font-family: var(--font-mono); font-size: 13px; font-weight: 500; color: var(--text); }
.finding .ident .id a { color: var(--text); border-bottom-color: var(--border-strong); }
.finding .ident .pkg { font-size: 12px; color: var(--text-muted); font-family: var(--font-mono); }
.finding .right { display: flex; align-items: center; gap: var(--space-3); font-size: 12px; color: var(--text-muted); }
.finding .right .fix { font-family: var(--font-mono); }
.finding .chev { color: var(--text-faint); transition: transform .2s; }
.finding[data-open="true"] .chev { transform: rotate(90deg); }
.finding .finding-detail { display: none; }
.finding[data-open="true"] .finding-detail {
  display: grid;
  grid-column: 1 / -1;
  grid-template-columns: max-content 1fr;
  gap: var(--space-2) var(--space-4);
  padding-top: var(--space-3);
  margin-top: var(--space-3);
  border-top: 1px solid var(--border);
  font-size: 13px;
  color: var(--text-muted);
}
.finding-detail dt { color: var(--text-faint); font-size: 11px; letter-spacing: 0.08em; text-transform: uppercase; margin: 0; }
.finding-detail dd { margin: 0; color: var(--text); font-family: var(--font-mono); font-size: 12px; word-break: break-word; }
.finding-detail dd a { font-family: var(--font-body); }
.findings-empty { padding: var(--space-7); text-align: center; color: var(--text-faint); font-style: italic; }

.kv-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: var(--space-5); }
.kv-card {
  padding: var(--space-5);
  background: var(--surface-strong);
  border: 1px solid var(--border);
  border-radius: var(--radius-tile);
}
.kv-card h3 {
  margin: 0 0 var(--space-3);
  font-size: 11px; font-weight: 600;
  letter-spacing: 0.12em; text-transform: uppercase; color: var(--text-faint);
}
.kv-card .kv-line { display: flex; justify-content: space-between; gap: var(--space-3); padding: 4px 0; font-size: 13px; }
.kv-card .kv-line .k { color: var(--text-muted); }
.kv-card .kv-line .v { color: var(--text); font-family: var(--font-mono); text-align: right; }

.kv-card .desc { margin-top: var(--space-2); padding-top: var(--space-2); border-top: 1px solid var(--border); font-size: 12px; color: var(--text-faint); line-height: 1.5; }

.business-stage {
  padding: var(--space-5);
  background: var(--surface-strong);
  border: 1px solid var(--border);
  border-radius: var(--radius-tile);
  margin-bottom: var(--space-3);
  display: flex; flex-direction: column; gap: var(--space-3);
}
.business-stage h3 {
  margin: 0;
  font-size: 14px; font-weight: 600;
  display: flex; align-items: center; gap: var(--space-2);
}
.business-stage h3 .stage-dot { width: 8px; height: 8px; border-radius: 50%; background: currentColor; }
.business-stage h3.success { color: var(--success); }
.business-stage h3.failed  { color: var(--failed); }
.business-stage h3.skipped { color: var(--skipped); }
.business-stage h3 .stage-name { color: var(--text); }
.business-stage h3 .duration-badge {
  margin-left: auto;
  font-family: var(--font-mono); font-size: 11px; font-weight: 500;
  color: var(--text-muted);
  padding: 2px 8px; border-radius: var(--radius-chip);
  background: var(--surface);
  border: 1px solid var(--border);
}
.business-stage .kv-line {
  display: grid; grid-template-columns: minmax(160px, max-content) 1fr;
  gap: var(--space-3); padding: 3px 0; font-size: 13px;
}
.business-stage .kv-line .k { color: var(--text-muted); font-family: var(--font-mono); font-size: 12px; }
.business-stage .kv-line .v { color: var(--text); font-family: var(--font-mono); font-size: 12px; word-break: break-all; }

/* Failure banner ------------------------------------------------- */
.failure-banner {
  display: flex; align-items: center; gap: var(--space-3); flex-wrap: wrap;
  padding: var(--space-3) var(--space-4);
  background: color-mix(in oklch, var(--failed) 12%, transparent);
  border: 1px solid color-mix(in oklch, var(--failed) 35%, transparent);
  border-radius: var(--radius-tile);
}
.failure-banner .label {
  font-family: var(--font-mono); font-size: 11px; font-weight: 600;
  letter-spacing: 0.08em; text-transform: uppercase;
  color: var(--failed);
  padding: 3px 10px; border-radius: var(--radius-chip);
  background: color-mix(in oklch, var(--failed) 25%, transparent);
}
.failure-banner .reason { font-size: 13px; color: var(--text); }
.failure-banner .reason .code { font-family: var(--font-mono); }
.failure-banner .cta {
  margin-left: auto;
  font-size: 12px; font-weight: 500;
  padding: 5px 12px; border-radius: var(--radius-chip);
  background: var(--surface-hi);
  border: 1px solid var(--border-strong);
  color: var(--text);
}
.failure-banner .cta:hover { background: color-mix(in oklch, var(--failed) 15%, var(--surface-hi)); border-color: var(--failed); }

/* Stage-specific design tiles ------------------------------------ */
.stage-grid {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: var(--space-4);
}
.stage-tile {
  padding: var(--space-4);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-tile);
  display: flex; flex-direction: column; gap: var(--space-2);
}
.stage-tile .label {
  font-size: 10px; letter-spacing: 0.14em; text-transform: uppercase;
  color: var(--text-faint);
}
.stage-tile .value {
  font-size: 16px; font-weight: 600; color: var(--text);
  word-break: break-word;
}
.stage-tile .value.mono { font-family: var(--font-mono); font-size: 13px; font-weight: 500; }
.stage-tile .sub { font-size: 12px; color: var(--text-muted); font-family: var(--font-mono); word-break: break-word; }

.version-arrow {
  display: flex; align-items: baseline; gap: var(--space-2); font-family: var(--font-mono);
}
.version-arrow .from { color: var(--text-muted); font-size: 14px; }
.version-arrow .arrow { color: var(--text-faint); }
.version-arrow .to   { color: var(--text); font-size: 18px; font-weight: 600; }
.version-arrow .same { color: var(--text-muted); font-size: 16px; }

.size-badge {
  display: inline-block;
  padding: 1px 8px; border-radius: var(--radius-chip);
  background: var(--surface-hi);
  border: 1px solid var(--border);
  color: var(--text-muted);
  font-family: var(--font-mono); font-size: 11px; margin-left: var(--space-2);
}

.image-ref { font-family: var(--font-mono); font-size: 13px; word-break: break-all; }
.image-ref .registry { color: var(--text-muted); }
.image-ref .repo { color: var(--text); }
.image-ref .tag { color: var(--success); }
.digest-line { font-family: var(--font-mono); font-size: 11px; color: var(--text-faint); word-break: break-all; }

.commit-card {
  padding: var(--space-4);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-tile);
  display: grid; grid-template-columns: minmax(0, auto) 1fr; gap: var(--space-2) var(--space-4);
  align-items: baseline;
}
.commit-card .sha { font-family: var(--font-mono); font-size: 16px; font-weight: 600; color: var(--text); }
.commit-card .subject { color: var(--text); font-size: 14px; font-style: italic; }
.commit-card .meta-line { grid-column: 1 / -1; font-size: 12px; color: var(--text-muted); display: flex; gap: var(--space-3); flex-wrap: wrap; }
.commit-card .meta-line strong { color: var(--text); font-weight: 500; }

/* Severity bar (sast/scan/container-scan) ----------------------- */
.sev-bar {
  display: flex; height: 8px; border-radius: var(--radius-chip);
  overflow: hidden; background: var(--surface-hi);
  margin: var(--space-2) 0;
}
.sev-bar .seg.critical { background: var(--critical); }
.sev-bar .seg.high     { background: var(--high); }
.sev-bar .seg.medium   { background: var(--medium); }
.sev-bar .seg.low      { background: var(--low); }
.sev-bar .seg.info     { background: var(--info); }
.sev-legend { display: flex; gap: var(--space-3); flex-wrap: wrap; font-size: 12px; color: var(--text-muted); }
.sev-legend .lg { display: inline-flex; align-items: center; gap: 6px; }
.sev-legend .lg .dot { width: 8px; height: 8px; border-radius: 50%; background: currentColor; }
.findings-jump {
  align-self: flex-start;
  font-size: 12px; font-weight: 500;
  padding: 4px 10px; border-radius: var(--radius-chip);
  background: var(--surface-hi);
  border: 1px solid var(--border);
  color: var(--text-muted);
}
.findings-jump:hover { color: var(--text); border-color: var(--border-strong); }

/* Coverage progress bars (test stage) ---------------------------- */
.cov-bar { display: flex; flex-direction: column; gap: 6px; }
.cov-bar .row { display: flex; justify-content: space-between; font-size: 12px; }
.cov-bar .row .k { color: var(--text-muted); font-family: var(--font-mono); }
.cov-bar .row .v { color: var(--text); font-family: var(--font-mono); font-weight: 500; }
.cov-bar .track {
  height: 6px; border-radius: var(--radius-chip);
  background: var(--surface-hi); overflow: hidden;
}
.cov-bar .fill { height: 100%; background: var(--success); transition: width .3s; }
.cov-bar .fill.low  { background: var(--high); }
.cov-bar .fill.mid  { background: var(--medium); }

.tool-chips { display: flex; flex-wrap: wrap; gap: var(--space-2); }
.tool-chip {
  font-family: var(--font-mono); font-size: 11px;
  padding: 3px 10px; border-radius: var(--radius-chip);
  background: var(--surface-hi); border: 1px solid var(--border);
  color: var(--text-muted);
}
.tool-chip strong { color: var(--text); }

footer { color: var(--text-faint); font-size: 12px; text-align: center; padding-top: var(--space-5); }
HEAD_OPEN
    cat <<HEAD_DATA
</style>
</head>
<body data-findings-count="${count}">
HEAD_DATA
    cat <<'HEAD_BODY'
<main>
  <section id="hero" class="card hero" aria-label="Pipeline summary"></section>
  <section id="timeline" class="card" aria-label="Lifecycle timeline">
    <h2>Lifecycle</h2>
    <div class="timeline-rail" id="timeline-rail"></div>
  </section>
  <section id="findings" class="card" aria-label="Findings">
    <h2>Findings</h2>
    <div class="findings-toolbar">
      <div class="findings-counts" id="findings-counts"></div>
      <div class="findings-filters" id="findings-filters"></div>
    </div>
    <input type="search" class="search-input" id="findings-search" placeholder="Filter by id, package, message...">
    <div class="findings-list" id="findings-list"></div>
  </section>
  <section id="meta" class="card" aria-label="Policy and coverage">
    <h2>Policy and coverage</h2>
    <div class="kv-grid" id="meta-grid"></div>
  </section>
  <section id="business" class="card" aria-label="Per-stage business">
    <h2>Per-stage payload</h2>
    <div id="business-list"></div>
  </section>
  <footer>Generated by brik report.render.</footer>
</main>
<script type="application/json" id="brik-report">
HEAD_BODY
}

_report._render_html_tail() {
    cat <<'TAIL'
</script>
<script>
(function() {
  "use strict";
  const raw = document.getElementById('brik-report').textContent;
  let data;
  try { data = JSON.parse(raw); }
  catch (e) {
    document.body.innerHTML = '<main><pre>Failed to parse embedded aggregate JSON: ' + (e && e.message) + '</pre></main>';
    return;
  }

  const SEV_RANK = { critical: 4, high: 3, medium: 2, low: 1, info: 0 };
  const SEV_ORDER = ["critical", "high", "medium", "low", "info"];
  const STAGE_ORDER = ["init","release","build","lint","sast","scan","test","package","container-scan","deploy","notify"];
  const PARALLEL = new Set(["lint","sast","scan","test"]);

  const stageRank = (n) => { const i = STAGE_ORDER.indexOf(n); return i < 0 ? 99 : i; };
  const sevRank = (s) => SEV_RANK[s] || 0;
  const escapeHtml = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => (
    { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]
  ));

  const fmtDuration = (ms) => {
    if (ms == null || isNaN(ms)) return '-';
    if (ms < 1000) return Math.round(ms) + 'ms';
    const s = Math.floor(ms / 1000);
    if (s < 60) return s + 's';
    if (s < 3600) return Math.floor(s/60) + 'm' + String(s%60).padStart(2,'0') + 's';
    return Math.floor(s/3600) + 'h' + String(Math.floor((s%3600)/60)).padStart(2,'0') + 'm';
  };

  const totalDurationMs = () => {
    const a = Date.parse((data.pipeline||{}).started_at);
    const b = Date.parse((data.pipeline||{}).finished_at);
    if (isNaN(a) || isNaN(b)) return null;
    return b - a;
  };

  const $ = (id) => document.getElementById(id);

  function renderHero() {
    const p = data.pipeline || {};
    const status = p.status || 'unknown';
    const idText = p.url
      ? '<a href="' + escapeHtml(p.url) + '" target="_blank" rel="noopener">' + escapeHtml(p.id || '-') + '</a>'
      : escapeHtml(p.id || '-');
    const commit = p.commit || {};
    const sha = commit.sha || commit.short_sha || '';
    const cUrl = commitUrl(REPO, sha);
    const commitParts = [];
    if (commit.short_sha) {
      const label = '<span class="sha mono">' + escapeHtml(commit.short_sha) + '</span>';
      commitParts.push(cUrl ? '<a href="' + escapeHtml(cUrl) + '" target="_blank" rel="noopener">' + label + '</a>' : label);
    }
    if (commit.author) commitParts.push('<span>' + escapeHtml(commit.author) + '</span>');
    if (commit.message_subject) commitParts.push('<span class="subject">' + escapeHtml(commit.message_subject) + '</span>');
    const commitLine = commitParts.length ? '<div class="commit">' + commitParts.join(' &middot; ') + '</div>' : '';
    const total = fmtDuration(totalDurationMs());
    $('hero').innerHTML = ''
      + '<div class="top-row">'
      + '  <h1>' + escapeHtml(p.project || 'pipeline') + '</h1>'
      + '  <span class="pipeline-id mono">#' + idText + '</span>'
      + '  <span class="pill ' + status + '">' + escapeHtml(status) + '</span>'
      + '</div>'
      + commitLine
      + '<div class="meta">'
      + '  <span><strong>Platform:</strong>' + escapeHtml(p.platform || '-') + '</span>'
      + '  <span><strong>Started:</strong>' + escapeHtml(p.started_at || '-') + '</span>'
      + '  <span><strong>Total:</strong>' + escapeHtml(total) + '</span>'
      + '</div>';
  }

  function renderTimeline() {
    const stages = (data.stages || []).slice().sort((a,b) => stageRank(a.stage) - stageRank(b.stage));
    const rail = $('timeline-rail');
    rail.innerHTML = '';
    let i = 0;
    while (i < stages.length) {
      const s = stages[i];
      if (PARALLEL.has(s.stage)) {
        const group = [];
        while (i < stages.length && PARALLEL.has(stages[i].stage)) { group.push(stages[i]); i++; }
        rail.appendChild(renderParallelGroup(group));
      } else {
        rail.appendChild(renderStageCell(s));
        i++;
      }
    }
  }
  function renderStageCell(s) {
    const cell = document.createElement('div');
    cell.className = 'timeline-cell';
    const status = s.status || 'unknown';
    const job = (s.runner && s.runner.job_url) || '';
    const jobHtml = job ? '<div class="stage-job"><a href="' + escapeHtml(job) + '" target="_blank" rel="noopener">job</a></div>' : '';
    cell.innerHTML = ''
      + '<div class="stage-name">' + escapeHtml(s.stage || '-') + '</div>'
      + '<div class="stage-status ' + status + '">' + escapeHtml(status) + '</div>'
      + '<div class="stage-duration">' + fmtDuration(s.duration_ms) + '</div>'
      + jobHtml;
    return cell;
  }
  function renderParallelGroup(stages) {
    const wrap = document.createElement('div');
    wrap.className = 'timeline-cell parallel-group';
    const label = document.createElement('div');
    label.className = 'group-label';
    label.textContent = 'verify (parallel)';
    const children = document.createElement('div');
    children.className = 'group-children';
    stages.forEach((s) => children.appendChild(renderStageCell(s)));
    wrap.appendChild(label); wrap.appendChild(children);
    return wrap;
  }

  function renderFindings() {
    const all = (data.stages || []).flatMap((s) => ((s.business || {}).findings || {}).items || []);
    all.sort((a,b) => sevRank(b.severity) - sevRank(a.severity) || (b.score||0) - (a.score||0));

    const counts = {};
    SEV_ORDER.forEach((k) => counts[k] = 0);
    all.forEach((f) => { counts[f.severity] = (counts[f.severity] || 0) + 1; });
    const totalLine = '<span class="count">' + all.length + ' findings</span>';
    const sevLines = SEV_ORDER.filter((k) => counts[k] > 0).map((k) => (
      '<span class="count sev-' + k + '"><span class="dot"></span>' + counts[k] + ' ' + k + '</span>'
    )).join('');
    $('findings-counts').innerHTML = totalLine + sevLines;

    const filters = $('findings-filters');
    filters.innerHTML = '';
    const chips = [{ key: 'all', label: 'all' }].concat(
      SEV_ORDER.filter((k) => counts[k] > 0).map((k) => ({ key: k, label: k, sev: k }))
    );
    chips.forEach((c) => {
      const chip = document.createElement('button');
      chip.className = 'chip' + (c.key === 'all' ? ' active' : '');
      chip.dataset.filter = c.key;
      if (c.sev) chip.dataset.sev = c.sev;
      chip.textContent = c.label;
      chip.addEventListener('click', () => {
        filters.querySelectorAll('.chip').forEach((x) => x.classList.remove('active'));
        chip.classList.add('active');
        renderList();
      });
      filters.appendChild(chip);
    });

    const list = $('findings-list');
    const search = $('findings-search');
    search.addEventListener('input', renderList);

    function activeFilter() {
      const a = filters.querySelector('.chip.active');
      return a ? a.dataset.filter : 'all';
    }
    function renderList() {
      const f = activeFilter();
      const q = (search.value || '').trim().toLowerCase();
      const matches = all.filter((it) => {
        if (f !== 'all' && it.severity !== f) return false;
        if (!q) return true;
        const hay = [
          it.id, it.message,
          it.package && it.package.name, it.package && it.package.version,
          it.tool && it.tool.name
        ].filter(Boolean).join(' ').toLowerCase();
        return hay.indexOf(q) !== -1;
      });
      list.innerHTML = '';
      if (matches.length === 0) {
        list.innerHTML = '<div class="findings-empty">No findings match the current filter.</div>';
        return;
      }
      matches.forEach((it) => list.appendChild(renderFindingCard(it)));
    }
    renderList();
  }
  function renderFindingCard(it) {
    const card = document.createElement('div');
    card.className = 'finding sev-' + (it.severity || 'info');
    card.dataset.open = 'false';
    const idHtml = it.help_uri
      ? '<a href="' + escapeHtml(it.help_uri) + '" target="_blank" rel="noopener" onclick="event.stopPropagation()">' + escapeHtml(it.id || '-') + '</a>'
      : escapeHtml(it.id || '-');
    const pkg = it.package
      ? escapeHtml(it.package.name + ' ' + it.package.version)
      : '<span class="faint">-</span>';
    const fix = (it.fix && it.fix.available)
      ? '<span class="fix">-&gt; ' + escapeHtml((it.fix.versions || []).join(', ')) + '</span>'
      : '<span class="faint">no fix</span>';

    card.innerHTML = ''
      + '<span class="sev-dot"></span>'
      + '<div class="ident">'
      + '  <span class="id">' + idHtml + '</span>'
      + '  <span class="pkg">' + pkg + '</span>'
      + '</div>'
      + '<div class="right">' + fix + '<span class="chev">&rsaquo;</span></div>'
      + buildFindingDetail(it);
    card.addEventListener('click', () => {
      card.dataset.open = card.dataset.open === 'true' ? 'false' : 'true';
    });
    return card;
  }
  function buildFindingDetail(it) {
    const rows = [];
    if (it.message) rows.push(['Message', escapeHtml(it.message)]);
    if (it.score != null) rows.push(['CVSS', escapeHtml(String(it.score))]);
    if (it.tool && it.tool.name) rows.push(['Tool', escapeHtml(it.tool.name + (it.tool.version ? ' ' + it.tool.version : ''))]);
    if (it.location && it.location.uri) {
      const region = (it.location.start_line != null) ? ':' + it.location.start_line : '';
      rows.push(['Location', escapeHtml(it.location.uri + region)]);
    }
    if (it.location && it.location.logical) rows.push(['Logical', escapeHtml(it.location.logical)]);
    if (it.cwe && it.cwe.length) rows.push(['CWE', it.cwe.map(escapeHtml).join(', ')]);
    if (it.help_uri) rows.push(['Advisory', '<a href="' + escapeHtml(it.help_uri) + '" target="_blank" rel="noopener" onclick="event.stopPropagation()">' + escapeHtml(it.help_uri) + '</a>']);
    if (rows.length === 0) return '';
    return '<dl class="finding-detail">'
      + rows.map((r) => '<dt>' + r[0] + '</dt><dd>' + r[1] + '</dd>').join('')
      + '</dl>';
  }

  // Policy preset descriptions (mirror lib/transverse/findings.sh A2 matrix).
  const POLICY_DESC = {
    pragmatic:  'Ignores findings below the severity floor, then those without an upstream fix or marked wont-fix. Fails the rest.',
    strict:     'Ignores findings below the severity floor only. Fails everything else, including findings with no upstream fix.',
    permissive: 'Effective floor is critical. Ignores anything below critical, plus criticals without a fix. Fails only criticals with an upstream fix.'
  };

  // Repo URL helpers ------------------------------------------------
  function detectRepo(p) {
    if (!p || !p.url) return null;
    let m = p.url.match(/^(.+?)\/-\/pipelines\/[^/]+/);
    if (m) return { base: m[1], platform: 'gitlab' };
    m = p.url.match(/^(.+?)\/actions\/runs\/[^/]+/);
    if (m) return { base: m[1], platform: 'github' };
    return null;
  }
  function commitUrl(repo, sha) {
    if (!repo || !sha) return null;
    if (repo.platform === 'gitlab') return repo.base + '/-/commit/' + sha;
    if (repo.platform === 'github' || repo.platform === 'gitea') return repo.base + '/commit/' + sha;
    return null;
  }
  function blobUrl(repo, ref, path) {
    if (!repo || !path) return null;
    const r = ref || 'HEAD';
    if (repo.platform === 'gitlab') return repo.base + '/-/blob/' + r + '/' + path.replace(/^\//, '');
    if (repo.platform === 'github') return repo.base + '/blob/' + r + '/' + path.replace(/^\//, '');
    if (repo.platform === 'gitea')  return repo.base + '/src/branch/' + r + '/' + path.replace(/^\//, '');
    return null;
  }
  function linkOrText(url, label) {
    if (!url) return escapeHtml(label);
    return '<a href="' + escapeHtml(url) + '" target="_blank" rel="noopener">' + escapeHtml(label) + '</a>';
  }
  const REPO = detectRepo(data.pipeline || {});

  function renderMeta() {
    const grid = $('meta-grid');
    grid.innerHTML = '';
    const policy = (data.summary || {}).policy;
    if (policy) {
      const lines = [['preset', policy.preset || '-'], ['source', policy.source || '-']];
      if (policy.org_policy_url) lines.push(['org URL', policy.org_policy_url]);
      if (policy.org_policy_loaded_at) lines.push(['loaded at', policy.org_policy_loaded_at]);
      const desc = POLICY_DESC[policy.preset] || '';
      grid.appendChild(kvCard('Policy', lines, desc));
    }
    const test = (data.stages || []).find((s) => s.stage === 'test');
    const cov = test && test.business && test.business.coverage;
    if (cov) {
      const lines = [];
      if (cov.line_pct != null)   lines.push(['lines',    cov.line_pct + '%']);
      if (cov.branch_pct != null) lines.push(['branches', cov.branch_pct + '%']);
      if (lines.length) grid.appendChild(kvCard('Coverage', lines));
    }
    const stages = (data.summary || {}).stages || {};
    grid.appendChild(kvCard('Stages', [
      ['total',   stages.total   || 0],
      ['passed',  stages.passed  || 0],
      ['failed',  stages.failed  || 0],
      ['skipped', stages.skipped || 0]
    ]));
    if ((policy && (policy.expiring_soon || []).length > 0)) {
      const lines = policy.expiring_soon.map((e) => [e.id || e.glob || 'entry', e.expires || '-']);
      grid.appendChild(kvCard('Expiring soon', lines));
    }
  }
  function kvCard(title, lines, desc) {
    const c = document.createElement('div');
    c.className = 'kv-card';
    c.innerHTML = '<h3>' + escapeHtml(title) + '</h3>'
      + lines.map((l) => '<div class="kv-line"><span class="k">' + escapeHtml(l[0]) + '</span><span class="v">' + escapeHtml(String(l[1])) + '</span></div>').join('')
      + (desc ? '<div class="desc">' + escapeHtml(desc) + '</div>' : '');
    return c;
  }

  // Severity bar component shared by sast/scan/container-scan
  function severityBar(by_sev, total) {
    const t = total || SEV_ORDER.reduce((acc, k) => acc + (by_sev[k] || 0), 0);
    if (t === 0) return '<div class="muted" style="font-size:13px;">No findings.</div>';
    const segs = SEV_ORDER.filter((k) => (by_sev[k] || 0) > 0).map((k) => {
      const w = ((by_sev[k] || 0) / t * 100).toFixed(1);
      return '<div class="seg ' + k + '" style="width:' + w + '%;" title="' + by_sev[k] + ' ' + k + '"></div>';
    }).join('');
    const legend = SEV_ORDER.filter((k) => (by_sev[k] || 0) > 0).map((k) => (
      '<span class="lg sev-' + k + '"><span class="dot"></span>' + by_sev[k] + ' ' + k + '</span>'
    )).join('');
    return '<div class="sev-bar">' + segs + '</div>'
         + '<div class="sev-legend">' + legend + '</div>';
  }
  function tile(label, valueHtml, subHtml, opts) {
    opts = opts || {};
    const cls = opts.mono ? 'value mono' : 'value';
    return '<div class="stage-tile">'
      + '<div class="label">' + escapeHtml(label) + '</div>'
      + '<div class="' + cls + '">' + valueHtml + '</div>'
      + (subHtml ? '<div class="sub">' + subHtml + '</div>' : '')
      + '</div>';
  }
  function fmtBytes(n) {
    if (n == null || isNaN(n)) return '-';
    if (n === 0) return '0 B';
    const u = ['B','KB','MB','GB','TB'];
    let i = 0; while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
    return (i === 0 ? n : n.toFixed(1)) + ' ' + u[i];
  }
  function trunc(s, n) { s = String(s == null ? '' : s); return s.length > n ? s.slice(0, n) + '...' : s; }
  function shaCell(sha) {
    if (!sha) return '<span class="faint">-</span>';
    return '<code class="mono" title="' + escapeHtml(sha) + '">' + escapeHtml(trunc(sha, 12)) + '</code>';
  }

  // Per-stage renderers ----------------------------------------------
  function renderInit(b) {
    const c = b.commit || {};
    const sha = c.sha || c.short_sha || '';
    const url = commitUrl(REPO, sha);
    const shaLabel = c.short_sha || (sha ? trunc(sha, 8) : '-');
    const subject = c.message_subject ? '<span class="subject">' + escapeHtml(c.message_subject) + '</span>' : '';
    const meta = [];
    if (c.author)             meta.push('<span><strong>Author:</strong> ' + escapeHtml(c.author) + '</span>');
    if (c.ref)                meta.push('<span><strong>Ref:</strong> ' + escapeHtml(c.ref) + '</span>');
    if (c.timestamp)          meta.push('<span><strong>When:</strong> ' + escapeHtml(c.timestamp) + '</span>');
    if (b.triggered_by)       meta.push('<span><strong>Triggered by:</strong> ' + escapeHtml(b.triggered_by) + '</span>');
    return '<div class="commit-card">'
      + '<span class="sha">' + (url ? linkOrText(url, shaLabel) : escapeHtml(shaLabel)) + '</span>'
      + (subject || '<span></span>')
      + (meta.length ? '<div class="meta-line">' + meta.join('') + '</div>' : '')
      + '</div>';
  }
  function renderRelease(b) {
    const fromV = b.previous_version || '-';
    const toV   = b.new_version || '-';
    const same = (fromV === toV);
    const tag = b.tag || {};
    const tagName = tag.name || '';
    const tagUrl = (tagName && REPO) ? blobUrl(REPO, tagName, '') : null;
    const arrow = same
      ? '<div class="version-arrow"><span class="same">' + escapeHtml(toV) + ' (no bump)</span></div>'
      : '<div class="version-arrow"><span class="from">' + escapeHtml(fromV) + '</span><span class="arrow">-&gt;</span><span class="to">' + escapeHtml(toV) + '</span></div>';
    const tiles = [
      tile('Version', arrow, b.bump_type ? 'bump: ' + escapeHtml(b.bump_type) : ''),
    ];
    if (tagName) {
      const tagHtml = tagUrl ? linkOrText(tagUrl, tagName) : escapeHtml(tagName);
      tiles.push(tile('Tag', '<span class="mono">' + tagHtml + '</span>', tag.annotated ? 'annotated' : 'lightweight'));
    }
    return '<div class="stage-grid">' + tiles.join('') + '</div>';
  }
  function renderBuild(b) {
    const a = b.artifact || {};
    const tiles = [
      tile('Artifact', escapeHtml(a.name || '-') + (a.size_bytes != null ? '<span class="size-badge">' + fmtBytes(a.size_bytes) + '</span>' : ''), a.type ? escapeHtml(a.type) : ''),
    ];
    if (a.sha256) tiles.push(tile('SHA-256', shaCell(a.sha256), ''));
    if (a.path)   tiles.push(tile('Path', '<span class="mono">' + escapeHtml(a.path) + '</span>', ''));
    return '<div class="stage-grid">' + tiles.join('') + '</div>';
  }
  function renderLint(b, t) {
    const tools = (t && t.tools) || {};
    const checks = (t && t.checks) || [];
    const chips = [];
    if (checks.length) chips.push('<div class="tool-chips">' + checks.map((c) => '<span class="tool-chip"><strong>check:</strong> ' + escapeHtml(c) + '</span>').join('') + '</div>');
    const toolKeys = Object.keys(tools);
    if (toolKeys.length) chips.push('<div class="tool-chips">' + toolKeys.map((k) => '<span class="tool-chip">' + escapeHtml(k) + ': <strong>' + escapeHtml(tools[k]) + '</strong></span>').join('') + '</div>');
    if (chips.length === 0) return '<div class="muted" style="font-size:13px;">No lint metadata reported.</div>';
    return chips.join('');
  }
  function renderFindingsStage(b, label) {
    const f = b.findings || {};
    const bs = f.by_severity || {};
    const total = f.total || 0;
    const failing = f.failing || 0;
    const ignored = (f.ignored && f.ignored.total) || 0;
    const tiles = [
      tile('Total', '<span style="font-size:24px;">' + total + '</span>', label || ''),
      tile('Failing', '<span class="' + (failing > 0 ? 'sev-high' : 'muted') + '" style="font-size:24px;">' + failing + '</span>', '', { mono: false }),
      tile('Ignored', '<span style="font-size:24px;">' + ignored + '</span>', f.ignored && f.ignored.by_source ? Object.keys(f.ignored.by_source).join(', ') : ''),
    ];
    let html = '<div class="stage-grid">' + tiles.join('') + '</div>';
    if (total > 0) html += severityBar(bs, total);
    if ((f.items || []).length > 0) {
      html += '<a class="findings-jump" href="#findings">View ' + f.items.length + ' findings &uarr;</a>';
    }
    return html;
  }
  function renderScan(b) {
    const blocks = [];
    const deps = b.deps || {};
    const dv = deps.vulnerabilities || {};
    const depsTotal = dv.total || 0;
    const depsTiles = [
      tile('Vulnerable deps', '<span style="font-size:20px;">' + depsTotal + '</span>', deps.affected_packages != null ? deps.affected_packages + ' affected packages' : ''),
    ];
    if (deps.sbom_path) {
      depsTiles.push(tile('SBOM', '<span class="mono">' + escapeHtml(deps.sbom_path.split('/').pop()) + '</span>', escapeHtml(deps.sbom_path)));
    }
    blocks.push('<div><div class="label" style="font-size:10px;letter-spacing:0.14em;text-transform:uppercase;color:var(--text-faint);margin-bottom:var(--space-2);">Dependencies</div><div class="stage-grid">' + depsTiles.join('') + '</div>'
      + (depsTotal > 0 ? severityBar(dv.by_severity || {}, depsTotal) : '') + '</div>');
    const sec = b.secret || {};
    const secTiles = [
      tile('Secrets', '<span class="' + ((sec.findings_count||0) > 0 ? 'sev-high' : 'muted') + '" style="font-size:20px;">' + (sec.findings_count || 0) + '</span>', 'gitleaks scan'),
    ];
    blocks.push('<div><div class="label" style="font-size:10px;letter-spacing:0.14em;text-transform:uppercase;color:var(--text-faint);margin-bottom:var(--space-2);">Secrets</div><div class="stage-grid">' + secTiles.join('') + '</div></div>');
    return blocks.join('');
  }
  function renderTest(b) {
    const cov = b.coverage || {};
    const line = parseFloat(cov.line_pct);
    const branch = parseFloat(cov.branch_pct);
    const bar = (label, pct) => {
      if (isNaN(pct)) return '';
      const cls = pct >= 80 ? '' : (pct >= 60 ? 'mid' : 'low');
      return '<div class="cov-bar">'
        + '<div class="row"><span class="k">' + label + '</span><span class="v">' + pct.toFixed(2) + '%</span></div>'
        + '<div class="track"><div class="fill ' + cls + '" style="width:' + Math.min(100, Math.max(0, pct)) + '%;"></div></div>'
        + '</div>';
    };
    const bars = [bar('lines', line), bar('branches', branch)].filter(Boolean).join('<div style="height:var(--space-3);"></div>');
    return bars || '<div class="muted" style="font-size:13px;">No coverage reported.</div>';
  }
  function renderPackage(b) {
    const img = b.image || {};
    const reg = b.registry || {};
    const fullName = img.full_name || (img.name && img.tag ? img.name + ':' + img.tag : img.name);
    const m = fullName ? fullName.match(/^(?:(.+?)\/)?([^/]+\/[^:]+)(?::(.+))?$/) : null;
    let imgHtml = '<span class="image-ref">' + escapeHtml(fullName || '-') + '</span>';
    if (m) {
      imgHtml = '<span class="image-ref">'
        + (m[1] ? '<span class="registry">' + escapeHtml(m[1]) + '/</span>' : '')
        + '<span class="repo">' + escapeHtml(m[2]) + '</span>'
        + (m[3] ? '<span>:</span><span class="tag">' + escapeHtml(m[3]) + '</span>' : '')
        + '</span>';
    }
    const tiles = [tile('Image', imgHtml, img.digest ? '<span class="digest-line">' + escapeHtml(img.digest) + '</span>' : '')];
    if (reg.host) tiles.push(tile('Registry', '<span class="mono">' + escapeHtml(reg.host) + '</span>', (reg.namespace ? reg.namespace + '/' : '') + (reg.repository || '')));
    return '<div class="stage-grid">' + tiles.join('') + '</div>';
  }
  function renderDeploy(b) {
    const tiles = [];
    if (b.environment) tiles.push(tile('Environment', '<span class="mono">' + escapeHtml(b.environment) + '</span>', ''));
    if (b.target)      tiles.push(tile('Target', '<span class="mono">' + escapeHtml(b.target) + '</span>', ''));
    if (b.strategy)    tiles.push(tile('Strategy', escapeHtml(b.strategy), b.profile ? 'profile: ' + escapeHtml(b.profile) : ''));
    if (b.version)     tiles.push(tile('Version', '<span class="mono">' + escapeHtml(b.version) + '</span>', ''));
    if (tiles.length === 0) return '<div class="muted" style="font-size:13px;">No deploy metadata.</div>';
    return '<div class="stage-grid">' + tiles.join('') + '</div>';
  }

  const STAGE_RENDERERS = {
    'init':           (b, t) => renderInit(b),
    'release':        (b, t) => renderRelease(b),
    'build':          (b, t) => renderBuild(b),
    'lint':           (b, t) => renderLint(b, t),
    'sast':           (b)    => renderFindingsStage(b, 'static analysis'),
    'scan':           (b)    => renderScan(b),
    'test':           (b)    => renderTest(b),
    'package':        (b)    => renderPackage(b),
    'container-scan': (b)    => renderFindingsStage(b, 'container vulns'),
    'deploy':         (b)    => renderDeploy(b),
    'notify':         ()     => null
  };

  function failureBanner(s) {
    if (s.status !== 'failed') return '';
    const ec = (s.tech && s.tech.exit_code != null) ? s.tech.exit_code : (s.rc != null ? s.rc : '?');
    const job = (s.runner && s.runner.job_url) || '';
    const cta = job
      ? '<a class="cta" href="' + escapeHtml(job) + '" target="_blank" rel="noopener">View job logs &rarr;</a>'
      : '';
    return '<div class="failure-banner">'
      + '<span class="label">Failed</span>'
      + '<span class="reason">Stage exited with <span class="code">code ' + escapeHtml(String(ec)) + '</span>. Check the job logs for the root cause.</span>'
      + cta
      + '</div>';
  }

  function renderBusiness() {
    const list = $('business-list');
    list.innerHTML = '';
    const stages = (data.stages || []).slice().sort((a,b) => stageRank(a.stage) - stageRank(b.stage));
    let any = false;
    stages.forEach((s) => {
      const renderer = STAGE_RENDERERS[s.stage];
      const b = s.business || {};
      let inner = null;
      if (renderer) inner = renderer(b, s.tech || {});
      if (inner == null && Object.keys(b).length === 0 && s.status !== 'failed') return;
      if (inner == null) inner = renderFlat(b);
      any = true;
      const wrap = document.createElement('div');
      wrap.className = 'business-stage';
      const status = s.status || 'unknown';
      const dur = s.duration_ms != null ? '<span class="duration-badge">' + fmtDuration(s.duration_ms) + '</span>' : '';
      wrap.innerHTML = '<h3 class="' + status + '"><span class="stage-dot"></span><span class="stage-name">' + escapeHtml(s.stage || '-') + '</span>' + dur + '</h3>'
        + failureBanner(s)
        + inner;
      list.appendChild(wrap);
    });
    if (!any) {
      list.innerHTML = '<div class="findings-empty">No business payload reported.</div>';
    }
  }
  function renderFlat(b) {
    const lines = flattenBusiness(b);
    if (lines.length === 0) return '<div class="muted" style="font-size:13px;">No payload.</div>';
    return lines.map((l) => '<div class="kv-line"><span class="k">' + escapeHtml(l[0]) + '</span><span class="v">' + escapeHtml(String(l[1])) + '</span></div>').join('');
  }
  function flattenBusiness(b) {
    const out = [];
    const walk = (path, val) => {
      if (val === null || val === undefined) return;
      if (path[0] === 'findings') return;
      const t = typeof val;
      if (t === 'object' && !Array.isArray(val)) {
        for (const k of Object.keys(val)) walk(path.concat(k), val[k]);
      } else if (Array.isArray(val)) {
        if (val.every((x) => x == null || typeof x !== 'object')) {
          if (val.length > 0) out.push([path.join('.'), val.map((x) => x == null ? '' : x).join(', ')]);
        }
      } else if (t !== 'function') {
        out.push([path.join('.'), val]);
      }
    };
    walk([], b);
    out.sort((a, b) => a[0].localeCompare(b[0]));
    return out;
  }

  renderHero();
  renderTimeline();
  renderFindings();
  renderMeta();
  renderBusiness();
})();
</script>
</body>
</html>
TAIL
}
# KCOV_EXCL_STOP

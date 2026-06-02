#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module report
# @description Persistent pipeline-level report aggregator (facade).
#
# Records tech and business metrics per stage to a JSON backing store
# ($BRIK_LOG_DIR/aggregate-report.json) and renders Markdown + JSON + HTML
# outputs for human readers and CI artifacts.
#
# Lifecycle:
#   report.init                              # once, at pipeline start
#   report.record <stage> <cat> <key> <val>  # from each stage (cat = tech|business)
#   report.render [--format md|json|html|both]  # once, at pipeline end (default: both)
#
# This file is a thin facade: it owns the shared dependencies, the canonical
# jq duration library (used by both the Markdown and terminal renderers), and
# sources the implementation modules. The API surface is unchanged from when
# everything lived in this file -- consumers still `source report.sh` and call
# report.* / _report._* exactly as before. Implementation lives in report/:
#   report/store.sh            init, record(_object), has_status, read, append helpers
#   report/fragment.sh         write_fragment, aggregate_fragments, enrich, stage_order
#   report/render_md.sh        render, _render_aggregate_md, _render_md
#   report/render_terminal.sh  render_terminal, render_aggregate_terminal
#   report_html/render.sh      _render_html (self-contained HTML view)

# Guard against double-sourcing
[[ -n "${_BRIK_REPORT_LOADED:-}" ]] && return 0
_BRIK_REPORT_LOADED=1

# Source dependencies
# shellcheck source=logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/logging.sh"
# shellcheck source=error.sh
[[ -z "${_BRIK_ERROR_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/error.sh"
# shellcheck source=../transverse/sarif.sh
[[ -z "${_BRIK_TRANSVERSE_SARIF_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/../transverse/sarif.sh"
# shellcheck source=report_html/render.sh
[[ -z "${_BRIK_REPORT_HTML_RENDER_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/report_html/render.sh"

# Canonical jq helpers for rendering durations. Defined here (before the
# render modules are sourced) so the terminal Duration KV, the terminal
# Stages table, and the Markdown report format milliseconds identically.
# Previously three divergent implementations existed: a bash branch (capped
# at minutes), a jq fmt_ms (capped at seconds), and the full
# human_duration_ms (hours + zero-padding) -- the same 2m view could show
# "2m15s" in one place and "135s" in another. Accepts a number or a numeric
# string; null/non-numeric renders as "-". Consumed by report/render_md.sh
# and report/render_terminal.sh as a facade-owned global.
# KCOV_EXCL_START -- jq function library, not bash code
_BRIK_JQ_DURATION_DEFS=$(cat <<'JQ'
def pad2($n):
  ($n | tostring) | if length == 1 then "0" + . else . end;
# 80 -> "80ms", 1142 -> "1s", 33339 -> "33s", 141000 -> "2m21s", 3661000 -> "1h01m".
def human_duration_ms($ms):
  ( if $ms == null then null
    elif ($ms | type) == "number" then $ms
    else ($ms | tonumber?) end ) as $n
  | if $n == null then "-"
    elif $n < 1000 then "\($n)ms"
    else
      ($n / 1000 | floor) as $s
      | if $s < 60 then "\($s)s"
        elif $s < 3600 then
          ($s / 60 | floor) as $m | ($s % 60) as $sec
          | "\($m)m\(pad2($sec))s"
        else
          ($s / 3600 | floor) as $h | (($s % 3600) / 60 | floor) as $m
          | "\($h)h\(pad2($m))m"
        end
    end;
JQ
)
# KCOV_EXCL_STOP

# Source the implementation modules. Order is not behaviourally significant
# (Bash resolves function names at call time), but follows the dependency
# direction for readability: storage, then fragment aggregation, then the
# renderers that consume the jq library defined above.
# shellcheck source=report/lifecycle.sh
. "${BASH_SOURCE[0]%/*}/report/lifecycle.sh"
# shellcheck source=report/store.sh
. "${BASH_SOURCE[0]%/*}/report/store.sh"
# shellcheck source=report/fragment.sh
. "${BASH_SOURCE[0]%/*}/report/fragment.sh"
# shellcheck source=report/render_md.sh
. "${BASH_SOURCE[0]%/*}/report/render_md.sh"
# shellcheck source=report/render_terminal.sh
. "${BASH_SOURCE[0]%/*}/report/render_terminal.sh"

#!/usr/bin/env bash
# @module report_html.tail
# @description Closes the JSON data island, inlines the rendering JS, and
#   emits the closing </body></html> tags.
#
# JS is loaded from sibling app.js; the surrounding <script></script> tags
# stay inline so the document remains self-contained.

[[ -n "${_BRIK_REPORT_HTML_TAIL_LOADED:-}" ]] && return 0
_BRIK_REPORT_HTML_TAIL_LOADED=1

# KCOV_EXCL_START -- HTML/JS template body, not bash code
_report._render_html_tail() {
    cat <<'TAIL_OPEN'
</script>
<script>
TAIL_OPEN
    cat "${BASH_SOURCE[0]%/*}/app.js"
    cat <<'TAIL_CLOSE'
</script>
</body>
</html>
TAIL_CLOSE
}
# KCOV_EXCL_STOP

#shellcheck shell=bash
# Phase 3: HTML self-contained renderer for the aggregate report.
# Visual direction is dark luxury / Plumber radar inspired; structure matches
# what HTML consumers (browsers, archived CI artefacts) need.

Describe "_report._render_html"
  Include "$BRIK_PIPELINE_LIB/report.sh"

  setup_html_env() {
    HTML_TMP="$(mktemp -d)"
    BACKEND="$HTML_TMP/aggregate.json"
  }
  cleanup_html_env() { rm -rf "$HTML_TMP"; }
  Before 'setup_html_env'
  After  'cleanup_html_env'

  write_minimal_aggregate() {
    cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.0",
  "pipeline": {
    "id": "42", "platform": "gitlab", "project": "demo",
    "started_at": "2026-05-09T10:00:00+0000",
    "finished_at": "2026-05-09T10:02:00+0000",
    "status": "success",
    "url": "https://example.test/p/42"
  },
  "stages": [
    { "stage": "init", "status": "success", "rc": 0, "duration_ms": 100, "business": {} }
  ],
  "summary": { "stages": {"total":1,"passed":1,"failed":0,"skipped":0} }
}
JSON
  }

  write_rich_aggregate() {
    cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.0",
  "pipeline": {
    "id": "1330", "platform": "gitlab", "project": "java-complete",
    "started_at": "2026-05-09T12:51:47+0000",
    "finished_at": "2026-05-09T12:54:08+0000",
    "status": "failed",
    "url": "https://example.test/brik/java-complete/-/pipelines/1330",
    "commit": { "short_sha": "68f2e141", "author": "alice", "message_subject": "Initial commit" }
  },
  "stages": [
    { "stage": "container-scan", "status": "failed", "rc": 10, "duration_ms": 33339,
      "runner": { "job_url": "https://example.test/jobs/12440" },
      "business": {
        "findings": {
          "total": 2, "failing": 1,
          "by_severity": {"critical":1,"high":1,"medium":0,"low":0,"info":0},
          "items": [
            { "id": "CVE-2026-9001", "severity": "critical", "score": 9.5, "level": "error",
              "message": "kernel panic", "tool": {"name":"grype","version":"0.111.1"},
              "package": {"name":"kernel","version":"6.1.0","ecosystem":"apk"},
              "fix": {"versions":["6.1.1"], "available": true},
              "help_uri": "https://example.test/CVE-2026-9001",
              "location": {"uri":null,"start_line":null,"end_line":null,"snippet":null,"logical":null},
              "cwe": [] },
            { "id": "CVE-2026-42010", "severity": "high", "score": 7.1, "level": "error",
              "message": "gnutls vuln", "tool": {"name":"grype","version":"0.111.1"},
              "package": {"name":"gnutls","version":"3.8.12-r0","ecosystem":"apk"},
              "fix": {"versions":["3.8.13-r0"], "available": true},
              "help_uri": "https://security.example.test/CVE-2026-42010",
              "location": {"uri":null,"start_line":null,"end_line":null,"snippet":null,"logical":null},
              "cwe": [] }
          ]
        }
      }
    },
    { "stage": "init", "status": "success", "rc": 0, "duration_ms": 466,
      "business": { "project_name": "java-complete" } }
  ],
  "summary": {
    "stages": {"total":2,"passed":1,"failed":1,"skipped":0},
    "policy": {"preset":"pragmatic","source":"brik.yml"}
  }
}
JSON
  }

  Describe "argument validation"
    It "fails when the backend file does not exist"
      run() { _report._render_html "/nonexistent/aggregate.json"; }
      When call run
      The status should not equal 0
      The stderr should include "report not found"
    End
  End

  Describe "skeleton and self-containment"
    Before 'write_minimal_aggregate'

    It "starts with a valid HTML5 doctype"
      run() { _report._render_html "$BACKEND" | head -1; }
      When call run
      The output should equal "<!DOCTYPE html>"
    End

    It "declares utf-8 charset and a viewport meta"
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should include 'charset="utf-8"'
      The output should include "viewport"
    End

    It "embeds CSS inline (no external stylesheet link)"
      run() { _report._render_html "$BACKEND" | grep -cE '<link rel="stylesheet"' || true; }
      When call run
      The output should equal "0"
    End

    It "embeds the aggregate JSON inline under id=brik-report"
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should include '<script type="application/json" id="brik-report">'
    End

    It "embeds the same pipeline id as the source aggregate"
      run() {
        _report._render_html "$BACKEND" \
          | awk '/<script type="application\/json" id="brik-report">/{p=1; next} /<\/script>/{p=0} p' \
          | jq -r '.pipeline.id'
      }
      When call run
      The output should equal "42"
    End

    It "has matching open/close <html> tags"
      run() {
        local out; out="$(_report._render_html "$BACKEND")"
        printf '%s' "$out" | grep -cE '^<html[ >]'
        printf '%s' "$out" | grep -cE '^</html>'
      }
      When call run
      The line 1 of output should equal "1"
      The line 2 of output should equal "1"
    End
  End

  Describe "content sections"
    Before 'write_rich_aggregate'

    It "renders a hero region tagged with id=hero"
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should include 'id="hero"'
    End

    It "renders a lifecycle timeline region tagged with id=timeline"
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should include 'id="timeline"'
    End

    It "renders a findings panel region tagged with id=findings"
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should include 'id="findings"'
    End

    It "carries the embedded JSON items count to a data attribute"
      run() { _report._render_html "$BACKEND" | grep -oE 'data-findings-count="[0-9]+"' | head -1; }
      When call run
      The output should equal 'data-findings-count="2"'
    End

    It "exposes the project name in the hero"
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should include "java-complete"
    End

    It "uses ASCII dashes only, never em or en dashes"
      run() {
        _report._render_html "$BACKEND" \
          | LC_ALL=C grep -cE $'\xe2\x80\x93|\xe2\x80\x94' || true
      }
      When call run
      The output should equal "0"
    End
  End

  Describe "JSON embedding safety"
    write_aggregate_with_script_tag() {
      cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.0",
  "pipeline": {"id":"99","platform":"local","project":"demo",
    "started_at":"2026-05-09T10:00:00+0000",
    "finished_at":"2026-05-09T10:00:01+0000","status":"success"},
  "stages": [
    { "stage": "init", "status": "success", "rc": 0, "duration_ms": 1,
      "business": { "note": "contains </script> raw close tag" } }
  ],
  "summary": {"stages":{"total":1,"passed":1,"failed":0,"skipped":0}}
}
JSON
    }
    Before 'write_aggregate_with_script_tag'

    It "escapes any </script> sequence inside the embedded JSON"
      run() { _report._render_html "$BACKEND" | grep -cE '</script>' || true; }
      When call run
      # Exactly two closing tags: the data-island close and the renderer
      # script close. Any raw </script> in the JSON must be escaped, so
      # the count stays at 2 even when business payload contains </script>.
      The output should equal "2"
    End

    It "preserves the original JSON content when the escape is inverted"
      run() {
        _report._render_html "$BACKEND" \
          | awk '/<script type="application\/json" id="brik-report">/{p=1; next} /<\/script>/{p=0} p' \
          | sed 's|<\\/|</|g' \
          | jq -r '.stages[0].business.note'
      }
      When call run
      The output should equal "contains </script> raw close tag"
    End
  End
End

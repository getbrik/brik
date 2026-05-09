#shellcheck shell=bash
# Phase 2 polish for _report._render_aggregate_md:
#   - Stages listed in execution order, not alphabetical.
#   - Human durations (1s, 33s, 2m21s) instead of raw ms.
#   - Total pipeline duration line in the header.
#   - ASCII status glyphs ([OK]/[FAIL]/[SKIP]/[WARN]) safe for `cat`.
#   - Pipeline URL and per-stage job URLs rendered as Markdown links.
#   - Top findings (most severe) section sourced from business.findings.items.
#   - Business payload rendered as flat dotted scalars; no inline JSON dumps.

Describe "_report._render_aggregate_md - Phase 2 polish"
  Include "$BRIK_PIPELINE_LIB/report.sh"

  setup_md_env() {
    AGG_TMP="$(mktemp -d)"
    BACKEND="$AGG_TMP/aggregate.json"
  }
  cleanup_md_env() { rm -rf "$AGG_TMP"; }
  Before 'setup_md_env'
  After  'cleanup_md_env'

  # Aggregate that mirrors the production java-complete shape, with stages
  # in alphabetical input order so we can prove the renderer reorders them.
  write_prod_like_aggregate() {
    cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.0",
  "pipeline": {
    "id": "1330", "platform": "gitlab", "project": "java-complete",
    "started_at": "2026-05-09T12:51:47+0000",
    "finished_at": "2026-05-09T12:54:08+0000",
    "status": "failed",
    "url": "http://gitlab.example.test/brik/java-complete/-/pipelines/1330",
    "commit": { "sha": "68f2e141d", "short_sha": "68f2e141", "ref": "v0.1.0",
      "tag": "v0.1.0", "author": "alice", "message_subject": "Initial commit" }
  },
  "stages": [
    { "stage": "build", "status": "success", "rc": 0, "duration_ms": 1142,
      "runner": { "platform": "gitlab", "job_url": "http://gitlab.example.test/jobs/12434" },
      "business": { "artifact": { "type": "directory", "name": "dist", "size_bytes": 0,
        "sha256": "e20d6cbd2932e553faaaaa6c00f3f4e9be9e9dd14466560622ebe2445fc3cc02",
        "path": "/builds/brik/java-complete/dist" } } },
    { "stage": "container-scan", "status": "failed", "rc": 10, "duration_ms": 33339,
      "runner": { "platform": "gitlab", "job_url": "http://gitlab.example.test/jobs/12440" },
      "business": {
        "findings": {
          "total": 40, "failing": 7,
          "by_severity": {"critical":1,"high":6,"medium":11,"low":15,"info":7},
          "ignored": {"total":33,"by_source":{"policy.built-in.below-severity":33},
                      "by_severity":{"critical":0,"high":0,"medium":11,"low":15,"info":7}},
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
              "help_uri": "https://security.alpinelinux.org/vuln/CVE-2026-42010",
              "location": {"uri":null,"start_line":null,"end_line":null,"snippet":null,"logical":null},
              "cwe": [] },
            { "id": "CVE-2026-7777", "severity": "low", "score": 2.0, "level": "note",
              "message": "minor", "tool": {"name":"grype","version":"0.111.1"},
              "package": {"name":"libfoo","version":"1.0.0","ecosystem":"apk"},
              "fix": {"versions":[], "available": false},
              "help_uri": null,
              "location": {"uri":null,"start_line":null,"end_line":null,"snippet":null,"logical":null},
              "cwe": [] }
          ]
        },
        "report": {"format":"sarif","path":"brik-artifacts/container-scan/findings.sarif"}
      } },
    { "stage": "init", "status": "success", "rc": 0, "duration_ms": 466,
      "runner": { "platform": "gitlab", "job_url": "http://gitlab.example.test/jobs/12432" },
      "business": { "project_name": "java-complete", "platform": "gitlab",
        "commit": {"sha":"68f2e141d","short_sha":"68f2e141","ref":"v0.1.0","author":"alice"},
        "pipeline": {"id":"1330","url":"http://gitlab.example.test/pipelines/1330"},
        "triggered_by": "alice" } },
    { "stage": "lint", "status": "success", "rc": 0, "duration_ms": 8390,
      "runner": { "platform": "gitlab", "job_url": "http://gitlab.example.test/jobs/12435" },
      "business": {} },
    { "stage": "package", "status": "success", "rc": 0, "duration_ms": 5429,
      "runner": { "platform": "gitlab", "job_url": "http://gitlab.example.test/jobs/12439" },
      "business": { "image": {"name":"reg.example/brik/java-complete","tag":"0.1.0",
        "full_name":"reg.example/brik/java-complete:0.1.0",
        "digest":"sha256:4d6ea0ccf72fa5160eb86af6d80e3ff487b708685bfa0d47c83beb836c140837"} } },
    { "stage": "release", "status": "success", "rc": 0, "duration_ms": 80,
      "runner": { "platform": "gitlab", "job_url": "http://gitlab.example.test/jobs/12433" },
      "business": { "previous_version": "0.1.0", "new_version": "0.1.0", "bump_type": "explicit" } },
    { "stage": "sast", "status": "success", "rc": 0, "duration_ms": 6625,
      "runner": { "platform": "gitlab", "job_url": "http://gitlab.example.test/jobs/12436" },
      "business": { "findings": {"total":0,"failing":0,
        "by_severity":{"critical":0,"high":0,"medium":0,"low":0,"info":0}} } },
    { "stage": "scan", "status": "success", "rc": 0, "duration_ms": 3120,
      "runner": { "platform": "gitlab", "job_url": "http://gitlab.example.test/jobs/12437" },
      "business": {} },
    { "stage": "test", "status": "success", "rc": 0, "duration_ms": 12072,
      "runner": { "platform": "gitlab", "job_url": "http://gitlab.example.test/jobs/12438" },
      "business": { "coverage": {"line_pct":"85.71","branch_pct":"100.00"} } }
  ],
  "summary": {
    "stages": {"total":9,"passed":8,"failed":1,"skipped":0},
    "warnings": [],
    "policy": {"preset":"pragmatic","source":"brik.yml"}
  }
}
JSON
  }

  Describe "stage ordering and durations"
    Before 'write_prod_like_aggregate'

    It "lists stages in execution order, not alphabetical"
      run() { _report._render_aggregate_md "$BACKEND" \
              | awk '/^## Stages/{p=1; next} /^## /{p=0} p && /^\| [a-z]/{print $2}'; }
      When call run
      The line 1 of output should equal "init"
      The line 2 of output should equal "release"
      The line 3 of output should equal "build"
      The line 4 of output should equal "lint"
      The line 5 of output should equal "sast"
      The line 6 of output should equal "scan"
      The line 7 of output should equal "test"
      The line 8 of output should equal "package"
      The line 9 of output should equal "container-scan"
    End

    It "renders human durations (s/m) for each stage, not raw ms"
      run() { _report._render_aggregate_md "$BACKEND"; }
      When call run
      The output should include "33s"
      The output should include "12s"
      The output should not include "33339"
      The output should not include "12072"
    End

    It "shows total pipeline duration computed from started_at/finished_at"
      run() { _report._render_aggregate_md "$BACKEND" | grep -E "^- \*\*Total duration"; }
      When call run
      The output should include "2m21s"
    End
  End

  Describe "ASCII status glyphs"
    Before 'write_prod_like_aggregate'

    It "renders [OK] for successful stages"
      run() { _report._render_aggregate_md "$BACKEND" | grep -E '^\| init '; }
      When call run
      The output should include "[OK]"
    End

    It "renders [FAIL] for failed stages"
      run() { _report._render_aggregate_md "$BACKEND" | grep -E '^\| container-scan '; }
      When call run
      The output should include "[FAIL]"
    End

    It "renders [FAIL] in the pipeline header for a failed pipeline"
      run() { _report._render_aggregate_md "$BACKEND" | grep -E "^- \*\*Status"; }
      When call run
      The output should include "[FAIL]"
    End
  End

  Describe "Markdown links"
    Before 'write_prod_like_aggregate'

    It "renders the pipeline URL as a Markdown link in the header"
      run() { _report._render_aggregate_md "$BACKEND" | grep -E "Pipeline ID"; }
      When call run
      The output should include "[1330](http://gitlab.example.test/brik/java-complete/-/pipelines/1330)"
    End

    It "renders job URLs as Markdown links in the stages table"
      run() { _report._render_aggregate_md "$BACKEND" | grep -E '^\| init '; }
      When call run
      The output should include "[job](http://gitlab.example.test/jobs/12432)"
    End
  End

  Describe "Top findings (most severe)"
    Before 'write_prod_like_aggregate'

    It "renders a Top findings section when at least one items[] exists"
      run() { _report._render_aggregate_md "$BACKEND"; }
      When call run
      The output should include "## Top findings"
    End

    It "lists CVE id linked to help_uri when present"
      run() { _report._render_aggregate_md "$BACKEND"; }
      When call run
      The output should include "[CVE-2026-9001](https://example.test/CVE-2026-9001)"
      The output should include "[CVE-2026-42010](https://security.alpinelinux.org/vuln/CVE-2026-42010)"
    End

    It "lists package name + current version + fix arrow"
      run() { _report._render_aggregate_md "$BACKEND"; }
      When call run
      The output should include "kernel 6.1.0"
      The output should include "-> 6.1.1"
      The output should include "gnutls 3.8.12-r0"
      The output should include "-> 3.8.13-r0"
    End

    It "lists no-fix items with their package and current version"
      run() { _report._render_aggregate_md "$BACKEND" | grep -E 'CVE-2026-7777'; }
      When call run
      The output should include "libfoo 1.0.0"
    End

    It "sorts items by severity desc (critical first)"
      run() {
        _report._render_aggregate_md "$BACKEND" \
          | awk '/^## Top findings/{p=1; next} /^## /{p=0} p && /^\| [chml]/{print $2}'
      }
      When call run
      The line 1 of output should equal "critical"
      The line 2 of output should equal "high"
      The line 3 of output should equal "low"
    End
  End

  Describe "Business payload (no inline JSON, dotted scalars)"
    Before 'write_prod_like_aggregate'

    It "renders nested business as dotted-key scalars, not raw JSON"
      run() { _report._render_aggregate_md "$BACKEND"; }
      When call run
      The output should include "**artifact.sha256:**"
      The output should include "**image.full_name:**"
      The output should include "**commit.short_sha:**"
    End

    It "does not contain raw JSON object dumps in the business section"
      run() { _report._render_aggregate_md "$BACKEND" | grep -cE ': \{"' || true; }
      When call run
      The output should equal "0"
    End

    It "skips the business.findings sub-tree (already rendered above)"
      run() { _report._render_aggregate_md "$BACKEND" | grep -cE 'findings\.items\.|findings\.by_severity\.' || true; }
      When call run
      The output should equal "0"
    End
  End
End

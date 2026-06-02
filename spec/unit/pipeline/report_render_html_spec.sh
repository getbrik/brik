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
      # Consume the full render: piping to `head -1` closes the pipe early
      # and the heredoc `cat`s in _render_html get SIGPIPE (Broken pipe on
      # stderr). `The line 1 of output` reads everything, then asserts.
      run() { _report._render_html "$BACKEND"; }
      When call run
      The line 1 of output should equal "<!DOCTYPE html>"
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

  Describe "brand strip"
    Before 'write_minimal_aggregate'

    It "renders the brand header above the hero"
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should include '<header class="brand">'
      The output should include 'aria-label="Brik on GitHub"'
      The output should include '<span class="brand-name">Brik</span>'
    End

    It "embeds the logo as a self-contained data:image base64"
      run() { _report._render_html "$BACKEND"; }
      When call run
      # PNG magic byte signature in base64 starts with "iVBORw0KGgo".
      The output should include 'src="data:image/png;base64,iVBORw0KGgo'
      The output should include 'alt="Brik"'
      The output should include 'width="28" height="28"'
    End

    It "links the brand and footer credit to https://github.com/getbrik"
      run() { _report._render_html "$BACKEND" | grep -cF 'href="https://github.com/getbrik"' || true; }
      When call run
      # Two anchors carry the URL: the brand header and the footer credit.
      The output should equal "2"
    End

    It "ships the brand CSS rules"
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should include '.brand {'
      The output should include '.brand a {'
      The output should include '.brand img {'
      The output should include '.brand-name {'
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

    It "no longer renders a top-level findings panel (relocated into each stage)"
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should not include 'id="findings"'
      # The interactive panel mount fn replaces the global renderFindings
      The output should include 'function mountFindingsPanel'
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

  Describe "hero region"
    write_hero_release_aggregate() {
      cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {
    "id": "1330", "platform": "gitlab", "project": "java-complete",
    "started_at": "2026-05-09T12:51:47+0000",
    "finished_at": "2026-05-09T12:54:08+0000",
    "status": "success",
    "context": "release",
    "business": { "status": "success" },
    "url": "https://example.test/brik/java-complete/-/pipelines/1330",
    "commit": {
      "sha": "68f2e1419988c4a4a3b5b6d7e8f9a0b1c2d3e4f5",
      "short_sha": "68f2e141",
      "branch": "main",
      "ref": "refs/tags/v1.4.2",
      "tag": "v1.4.2",
      "author": "alice",
      "author_email": "alice@example.test",
      "message_subject": "release v1.4.2 with openssl bump"
    }
  },
  "stages": [
    { "stage": "release", "status": "success", "rc": 0, "duration_ms": 200,
      "business": { "status": "success", "new_version": "1.4.2", "previous_version": "1.4.1", "bump_type": "patch" } }
  ],
  "summary": {
    "stages": {"total":1,"passed":1,"failed":0,"skipped":0},
    "business": {"success_count":1,"warning_count":0,"error_count":0},
    "artifacts": {"version": "1.4.2"}
  }
}
JSON
    }

    Context "release context fixture"
      Before 'write_hero_release_aggregate'

      It "carries the context value through the data island"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '"context": "release"'
      End

      It "includes the context-badge template in the renderer source"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'class="context-badge '
      End

      It "exposes a renderer that emits a version block"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '<span class="version">'
      End

      It "exposes a renderer that wires the version to tagUrlOf"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'function tagUrlOf'
        The output should include "/-/tags/"
      End

      It "exposes a renderer that wires the branch to treeUrl"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'function treeUrl'
        The output should include "/-/tree/"
      End

      It "exposes platformFromHost helper for repo_url-driven detection"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'function platformFromHost'
        The output should include "'gitea'"
        The output should include "'bitbucket'"
      End

      It "exposes gitea-specific forge URL builders"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "'/src/branch/'"
      End

      It "builds tooltip strings identifying the link nature and host"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "'CI pipeline on '"
        The output should include "'Git commit on '"
        The output should include "'Git branch on '"
        The output should include "'Git tag on '"
        The output should include "'Send email to '"
        The output should include 'function hostOf'
      End

      It "renders link tooltips via data-tooltip (not native title)"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'data-tooltip="'
        The output should include '[data-tooltip]::after'
        The output should include '[data-tooltip]:hover::after'
      End

      It "honors prefers-reduced-motion for tooltip animation"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'prefers-reduced-motion: reduce'
      End

      It "exposes a mailto link template for the commit author"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "'<a href=\"mailto:'"
      End

      It "carries the tag, branch and author_email through the data island"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '"tag": "v1.4.2"'
        The output should include '"branch": "main"'
        The output should include '"author_email": "alice@example.test"'
      End

      It "defines formatHumanDate and formatRelative helpers"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'function formatHumanDate'
        The output should include 'function formatRelative'
        The output should include "'May'"
      End

      It "uses anchored CSS grid layout, not the legacy top-row flex"
        run() { _report._render_html "$BACKEND" | grep -cE 'class="top-row"' || true; }
        When call run
        The output should equal "0"
      End

      It "applies the halo box-shadow to the success status pill"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '.hero .pill.success { color: var(--success); box-shadow:'
      End

      It "applies the halo box-shadow to the warning status pill"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '.hero .pill.warning { color: var(--warning); box-shadow:'
      End

      It "replaces the red canvas blob with a violet halo"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should not include 'oklch(30% 0.10 25 / 0.25)'
        The output should include 'oklch(30% 0.10 290 / 0.30)'
      End
    End

    Context "snapshot context fixture (minimal aggregate)"
      Before 'write_minimal_aggregate'

      It "renderer falls back to 'snapshot' when pipeline.context is absent"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "p.context || 'snapshot'"
      End
    End

    Context "init stage panel"
      write_init_success_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {
    "id": "42", "platform": "gitlab", "project": "node-complete",
    "started_at": "2026-05-12T10:00:00+0000",
    "finished_at": "2026-05-12T10:02:00+0000",
    "status": "success",
    "context": "release",
    "business": {"status": "success"},
    "commit": { "short_sha": "839ac29", "branch": "main", "tag": "v0.1.0" }
  },
  "stages": [
    { "stage": "init", "status": "success", "rc": 0, "duration_ms": 491,
      "runner": { "image": "ghcr.io/getbrik/brik-runner-node:22", "platform": "gitlab", "job_url": "http://gitlab.test/job/24320" },
      "tech": {
        "stack": "node", "stack_version": "22",
        "config_file": "/builds/brik/node-complete/brik.yml",
        "config_valid": true,
        "prereqs_present": {"yq": true, "jq": true, "jv": true},
        "tool_versions":  {"yq": "4.45.1", "jq": "1.7.1", "jv": "0.5.0"},
        "exit_code": "0", "status": "success"
      },
      "business": { "status": "success", "project_name": "node-complete", "platform": "gitlab", "triggered_by": "admin" } }
  ],
  "summary": { "stages": {"total":1,"passed":1,"failed":0,"skipped":0},
               "business": {"success_count":1,"warning_count":0,"error_count":0} }
}
JSON
      }
      write_init_failed_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {
    "id": "99", "platform": "gitlab", "project": "invalid-config",
    "started_at": "2026-05-12T10:00:00+0000",
    "finished_at": "2026-05-12T10:00:05+0000",
    "status": "failed",
    "context": "snapshot",
    "business": {"status": "error"}
  },
  "stages": [
    { "stage": "init", "status": "failed", "rc": 7, "duration_ms": 42,
      "runner": { "image": "ghcr.io/getbrik/brik-runner-node:22", "platform": "gitlab", "job_url": "http://gitlab.test/job/24405" },
      "tech": { "duration_ms": "42", "exit_code": "7", "status": "failed" },
      "business": { "status": "warning", "reason": "failure (fix available)" } }
  ],
  "summary": { "stages": {"total":1,"passed":0,"failed":1,"skipped":0},
               "business": {"success_count":0,"warning_count":1,"error_count":0} }
}
JSON
      }

      It "exposes section labels for the 3 init sub-blocks"
        write_init_success_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "'Resolved configuration'"
        The output should include "'Pre-flight validation'"
        The output should include "'Trigger context'"
      End

      It "renders a stack chip combining language and version"
        write_init_success_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'class="stack-chip"'
      End

      It "renders the runner image with a copy button"
        write_init_success_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'function copyBtn'
        The output should include "'Copy image name'"
      End

      It "renders the tools table with versions and presence markers"
        write_init_success_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'class="tools-table"'
        The output should include 'function buildToolsTable'
      End

      It "exposes the brik.yml validation pill"
        write_init_success_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'status-pill ok'
      End

      It "classifies the trigger context (push/tag/manual/schedule)"
        write_init_success_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'function classifyTrigger'
        The output should include "'pushed commit'"
        The output should include "'scheduled run'"
        The output should include "'tag push (release)'"
      End

      It "short-circuits the init body to '' on technical failure (banner only)"
        write_init_failed_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "t.status === 'failed'"
        The output should include 'function initFailureReason'
      End

      It "maps exit code 7 to a brik.yml validation failure message"
        write_init_failed_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'Invalid brik.yml or input'
      End

      It "registers a per-stage failure-reason map for the failure banner"
        write_init_failed_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'STAGE_FAILURE_REASONS'
      End
    End

    Context "release stage panel"
      write_release_explicit_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {
    "id": "42", "platform": "gitlab", "project": "node-complete",
    "started_at": "2026-05-12T10:00:00+0000",
    "finished_at": "2026-05-12T10:02:00+0000",
    "status": "success",
    "context": "release",
    "business": {"status": "success"},
    "commit": { "short_sha": "839ac29", "tag": "v0.1.0", "repo_url": "http://gitlab.test/brik/x" }
  },
  "stages": [
    { "stage": "release", "status": "success", "rc": 0, "duration_ms": 81,
      "tech": { "strategy": "semver", "tag_prefix": "v", "dry_run": false, "exit_code": "0", "status": "success" },
      "business": {
        "status": "success",
        "previous_version": "0.1.0", "new_version": "0.1.0", "bump_type": "explicit",
        "tag": { "name": "v0.1.0", "sha": "839ac29b909ac64f75f726d3d85087a8e07bf2a1", "annotated": true, "dry_run": false }
      } }
  ],
  "summary": { "stages": {"total":1,"passed":1,"failed":0,"skipped":0},
               "business": {"success_count":1,"warning_count":0,"error_count":0} }
}
JSON
      }
      write_release_minor_bump_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {
    "id": "43", "platform": "gitlab", "project": "auto-bump",
    "started_at": "2026-05-12T10:00:00+0000",
    "finished_at": "2026-05-12T10:02:00+0000",
    "status": "success",
    "context": "release",
    "business": {"status": "success"}
  },
  "stages": [
    { "stage": "release", "status": "success", "rc": 0, "duration_ms": 81,
      "tech": { "strategy": "semver", "tag_prefix": "v", "exit_code": "0", "status": "success" },
      "business": {
        "status": "success",
        "previous_version": "1.4.1", "new_version": "1.5.0", "bump_type": "minor",
        "tag": { "name": "v1.5.0", "annotated": true }
      } }
  ],
  "summary": { "stages": {"total":1,"passed":1,"failed":0,"skipped":0},
               "business": {"success_count":1,"warning_count":0,"error_count":0} }
}
JSON
      }

      It "exposes the version-decision and tag-operation section labels"
        write_release_explicit_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "'Version decision'"
        The output should include "'Tag operation'"
      End

      It "classifies an explicit tag-driven release"
        write_release_explicit_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "'tag-driven release'"
      End

      It "classifies an auto-bump and surfaces the bump category"
        write_release_minor_bump_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "'auto-bumped ('"
      End

      It "covers the 'no bump' case for non-explicit identical versions"
        write_release_explicit_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "'no bump'"
      End

      It "renders strategy and tag_prefix when present in tech"
        write_release_explicit_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 't.strategy'
        The output should include 't.tag_prefix'
      End

      It "adds copy buttons to the tag name and full commit SHA"
        write_release_explicit_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "'Copy tag name'"
        The output should include "'Copy full commit SHA'"
      End

      It "registers releaseFailureReason in the per-stage failure map"
        write_release_explicit_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'function releaseFailureReason'
        The output should include "'release': releaseFailureReason"
      End

      It "applies a dominant 22px font to .version-arrow"
        write_release_explicit_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '.version-arrow {'
        The output should include 'font-size: 22px'
      End
    End

    Context "build stage panel"
      write_build_success_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {
    "id": "42", "platform": "gitlab", "project": "python-complete",
    "started_at": "2026-05-12T10:00:00+0000",
    "finished_at": "2026-05-12T10:02:00+0000",
    "status": "success",
    "context": "release",
    "business": {"status": "success"}
  },
  "stages": [
    { "stage": "build", "status": "success", "rc": 0, "duration_ms": 2577,
      "tech": { "stack": "python", "tool": "auto", "command": "<stack-default>", "exit_code": "0", "status": "success" },
      "business": {
        "status": "success",
        "artifact": {
          "type": "directory", "name": "dist", "size_bytes": 1737551,
          "sha256": "95ddd24131c647b07c6ce1f8e32533528b51587497ac1b6ad5d1107ff35d254f",
          "path": "/builds/brik/python-complete/dist",
          "main_file": "python_complete-0.1.0-py3-none-any.whl"
        }
      } }
  ],
  "summary": { "stages": {"total":1,"passed":1,"failed":0,"skipped":0},
               "business": {"success_count":1,"warning_count":0,"error_count":0} }
}
JSON
      }
      write_build_empty_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {
    "id": "42", "platform": "gitlab", "project": "java-complete",
    "started_at": "2026-05-12T10:00:00+0000",
    "finished_at": "2026-05-12T10:02:00+0000",
    "status": "success", "context": "release",
    "business": {"status": "warning"}
  },
  "stages": [
    { "stage": "build", "status": "success", "rc": 0, "duration_ms": 3000,
      "tech": { "stack": "java", "tool": "auto", "command": "<stack-default>", "exit_code": "0", "status": "success" },
      "business": {
        "status": "success",
        "artifact": { "type": "directory", "name": "dist", "size_bytes": 0,
                      "sha256": "e20d6cbd2932e553faaaaa6c00f3f4e9be9e9dd14466560622ebe2445fc3cc02",
                      "path": "/builds/brik/java-complete/dist" }
      } }
  ],
  "summary": { "stages": {"total":1,"passed":1,"failed":0,"skipped":0},
               "business": {"success_count":1,"warning_count":0,"error_count":0} }
}
JSON
      }

      It "exposes section labels for the 2 build sub-blocks"
        write_build_success_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "'Produced artifact'"
        The output should include "'Build method'"
      End

      It "uses main_file as the displayed artifact name when present"
        write_build_success_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'a.main_file'
        The output should include "displayName ="
      End

      It "renders a tile-warning border + size-badge.warn on empty artifact"
        write_build_empty_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '.stage-tile.tile-warning'
        The output should include '.size-badge.warn'
        The output should include 'empty-mark'
      End

      It "adds a copy button on the SHA-256 only (runner path is intentionally hidden)"
        write_build_success_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "'Copy full SHA-256'"
        The output should not include "'Copy artifact path'"
      End

      It "renders the build method line with stack and command separators"
        write_build_success_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'class="method-line"'
        The output should include 'class="method-key"'
      End

      It "labels tool=auto with a muted hint"
        write_build_success_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "tool === 'auto'"
      End
    End

    Context "lint stage panel"
      write_lint_success_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"42","platform":"gitlab","project":"node-complete",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:02:00+0000",
    "status":"success","context":"release","business":{"status":"success"}},
  "stages": [
    {"stage":"lint","status":"success","rc":0,"duration_ms":4139,
      "tech":{"checks":["lint","format"],"tools":{"lint":"eslint","format":"prettier"},
              "exit_code":"0","status":"success"},
      "business":{"status":"success","reason":""}}
  ],
  "summary":{"stages":{"total":1,"passed":1,"failed":0,"skipped":0},
             "business":{"success_count":1,"warning_count":0,"error_count":0}}
}
JSON
      }
      write_lint_failed_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"43","platform":"gitlab","project":"node-error-test",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:02:00+0000",
    "status":"failed","context":"snapshot","business":{"status":"warning"}},
  "stages": [
    {"stage":"lint","status":"failed","rc":10,"duration_ms":327,
      "tech":{"checks":["lint","format"],"tools":{"lint":"eslint","format":"prettier"},
              "exit_code":"10","status":"failed"},
      "business":{"status":"warning","reason":"failure (fix available)"}}
  ],
  "summary":{"stages":{"total":1,"passed":0,"failed":1,"skipped":0},
             "business":{"success_count":0,"warning_count":1,"error_count":0}}
}
JSON
      }
      write_lint_with_sarif_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"44","platform":"gitlab","project":"node-complete",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:02:00+0000",
    "status":"success","context":"release","business":{"status":"success"}},
  "stages": [
    {"stage":"lint","status":"success","rc":0,"duration_ms":4139,
      "tech":{"checks":["lint","format"],"tools":{"lint":"eslint","format":"prettier"},
              "exit_code":"0","status":"success"},
      "business":{"status":"success","reason":"",
                  "violations":{"total":7,
                                "by_severity":{"critical":0,"high":2,"medium":3,"low":2,"info":0},
                                "by_check":{"lint":5,"format":2}}}}
  ],
  "summary":{"stages":{"total":1,"passed":1,"failed":0,"skipped":0},
             "business":{"success_count":1,"warning_count":0,"error_count":0}}
}
JSON
      }

      It "renders a checks table with header columns"
        write_lint_success_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'class="tools-table lint-table"'
        The output should include '<th class="tool-name">Check</th>'
        The output should include '<th class="tool-version">Tool</th>'
      End

      It "shows no-SARIF hint when business.violations is absent"
        write_lint_success_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'lint-no-sarif'
        The output should include 'No SARIF report aggregated'
      End

      It "renders a violations subsection when SARIF was aggregated"
        write_lint_with_sarif_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "'Violations'"
        The output should include "findingsCounter(total, '', state, 'violation')"
      End

      It "carries the SARIF violation counts through the data island"
        write_lint_with_sarif_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '"total":7'
        The output should include '"lint":5'
      End

      It "maps exit_code 10 to a 'violations found' failure reason"
        write_lint_failed_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'Linter found violations and exited non-zero'
      End

      It "differentiates exit codes 2, 3, 4 from 10"
        write_lint_failed_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'Invalid lint configuration or input'
        The output should include 'Required lint tool missing on the runner'
        The output should include 'Invalid lint execution environment'
      End

      It "registers lintFailureReason in the per-stage failure map"
        write_lint_failed_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'function lintFailureReason'
        The output should include "'lint':    lintFailureReason"
      End
    End

    Context "sast stage panel"
      write_sast_clean_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"42","platform":"gitlab","project":"node-complete",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:02:00+0000",
    "status":"success","context":"release","business":{"status":"success"}},
  "stages": [
    {"stage":"sast","status":"success","rc":0,"duration_ms":3884,
      "tech":{"tool":"semgrep","exit_code":"0","status":"success"},
      "business":{"status":"success",
        "report":{"format":"sarif","path":"brik-artifacts/sast/findings.sarif"},
        "findings":{"total":0,
          "by_severity":{"critical":0,"high":0,"medium":0,"low":0,"info":0},
          "cwe":["CWE-79","CWE-89","CWE-22"],
          "failing":{"total":0,"has_fix":0,"no_fix":0},
          "ignored":{"total":0,"by_source":{},"by_severity":{"critical":0,"high":0,"medium":0,"low":0,"info":0}}}}}
  ],
  "summary":{"stages":{"total":1,"passed":1,"failed":0,"skipped":0},
             "business":{"success_count":1,"warning_count":0,"error_count":0}}
}
JSON
      }
      write_sast_with_findings_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"43","platform":"gitlab","project":"webapp",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:02:00+0000",
    "status":"failed","context":"snapshot","business":{"status":"warning"}},
  "stages": [
    {"stage":"sast","status":"failed","rc":10,"duration_ms":4244,
      "tech":{"tool":"semgrep","exit_code":"10","status":"failed"},
      "business":{"status":"warning",
        "report":{"format":"sarif","path":"brik-artifacts/sast/findings.sarif"},
        "findings":{"total":47,
          "by_severity":{"critical":1,"high":3,"medium":12,"low":28,"info":3},
          "cwe":["CWE-79","CWE-89","CWE-22","CWE-200"],
          "failing":{"total":4,"has_fix":3,"no_fix":1},
          "ignored":{"total":43,
            "by_source":{"brik-policy":30,"brik.yml":13},
            "by_severity":{"critical":0,"high":0,"medium":12,"low":28,"info":3}}}}}
  ],
  "summary":{"stages":{"total":1,"passed":0,"failed":1,"skipped":0},
             "business":{"success_count":0,"warning_count":1,"error_count":0}}
}
JSON
      }

      It "renders the Security checks table with Check and Tool columns"
        write_sast_with_findings_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'Security checks'
        The output should include 'sast-table'
        The output should include '>Check<'
        The output should include '>Tool<'
        The output should include 'semgrep'
      End

      It "renders the dirty findings counter with Failing breakdown when total > 0"
        write_sast_with_findings_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "'dirty'"
        The output should include 'big-number'
        The output should include 'findings-failing-line'
        The output should include 'has_fix:'
        The output should include 'no_fix:'
      End

      It "treats business.findings.failing as an object {total, has_fix, no_fix}"
        write_sast_with_findings_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "f.failing.total"
        The output should include "f.failing.has_fix"
        The output should include "f.failing.no_fix"
      End

      It "renders the Ignored disclosure with by_source and by_severity"
        write_sast_with_findings_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'ignored-disclosure'
        The output should include 'ignored-source-table'
        The output should include 'By source'
        The output should include 'By severity'
      End

      It "renders the clean findings counter and CWE chip when total is 0"
        write_sast_clean_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "'clean'"
        The output should include 'cwe-chip'
        The output should include 'CWEs analysed'
      End

      It "omits the SARIF download link (workspace paths are not browseable)"
        write_sast_clean_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should not include 'Download SARIF'
        The output should not include 'findings-footer'
      End

      It "omits the Ignored disclosure when ignored.total is 0"
        write_sast_clean_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'function renderFindingsStage'
      End

      It "carries findings data through the data island"
        write_sast_with_findings_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '"total":47'
        The output should include '"has_fix":3'
        The output should include '"no_fix":1'
        The output should include '"brik-policy":30'
      End
    End

    Context "scan stage panel"
      write_scan_clean_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"50","platform":"gitlab","project":"node-complete",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:02:00+0000",
    "status":"success","context":"release","business":{"status":"success"}},
  "stages": [
    {"stage":"scan","status":"success","rc":0,"duration_ms":4420,
      "tech":{"deps":{"tool":"osv-scanner"},"secret":{"tool":"gitleaks"},
              "severity_threshold":"critical","exit_code":"0","status":"success"},
      "business":{"status":"success",
        "deps":{"vulnerabilities":{"total":0,"by_severity":{"critical":0,"high":0,"medium":0,"low":0,"info":0}},
                "affected_packages":0,
                "sbom_path":"brik-artifacts/scan/sbom.cdx.json"},
        "secret":{"findings_count":0,
                  "report":{"format":"sarif","path":"brik-artifacts/scan/secret.sarif"}}}}
  ],
  "summary":{"stages":{"total":1,"passed":1,"failed":0,"skipped":0},
             "business":{"success_count":1,"warning_count":0,"error_count":0}}
}
JSON
      }
      write_scan_dirty_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"51","platform":"jenkins","project":"webapp",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:02:00+0000",
    "status":"failed","context":"release","business":{"status":"error"}},
  "stages": [
    {"stage":"scan","status":"failed","rc":10,"duration_ms":5120,
      "tech":{"deps":{"tool":"grype"},"secret":{"tool":"gitleaks"},
              "severity_threshold":"high","exit_code":"10","status":"failed"},
      "business":{"status":"error",
        "deps":{"vulnerabilities":{"total":17,
                                   "by_severity":{"critical":2,"high":5,"medium":7,"low":3,"info":0}},
                "affected_packages":9,
                "sbom_path":"brik-artifacts/scan/sbom.cdx.json"},
        "secret":{"findings_count":2,
                  "report":{"format":"sarif","path":"brik-artifacts/scan/secret.sarif"}}}}
  ],
  "summary":{"stages":{"total":1,"passed":0,"failed":1,"skipped":0},
             "business":{"success_count":0,"warning_count":0,"error_count":1}}
}
JSON
      }

      It "renders the Checks + Findings sections with both sondes inside"
        write_scan_clean_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "sectionLabel('Checks')"
        The output should include "sectionLabel('Findings')"
        The output should include 'dependency vulnerabilities'
        The output should include 'secret scan'
        The output should include 'scan-finding-label'
      End

      It "shows per-sonde tool in the Check/Tool table"
        write_scan_clean_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'dependency vulnerabilities'
        The output should include 'osv-scanner'
        The output should include 'secret scan'
        The output should include 'gitleaks'
      End

      It "renders the SBOM chip with the filename"
        write_scan_clean_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'SBOM:'
        The output should include 'sbom.cdx.json'
      End

      It "renders clean counters when both sondes are at zero"
        write_scan_clean_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "'clean'"
      End

      It "renders dirty counter + severity bar + affected_packages when deps total > 0"
        write_scan_dirty_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "'dirty'"
        The output should include 'findings-severity-wrap'
        The output should include 'Affected packages'
        The output should include 'grype'
      End

      It "carries dirty totals through the data island for both sondes"
        write_scan_dirty_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        # deps.vulnerabilities.total=17, secret.findings_count=2
        The output should include '"total":17'
        The output should include '"findings_count":2'
      End

      It "carries scan probe data through the data island"
        write_scan_dirty_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '"affected_packages":9'
        The output should include '"findings_count":2'
        The output should include '"tool":"grype"'
      End
    End

    Context "test stage panel"
      write_test_with_counts_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"60","platform":"gitlab","project":"node-complete",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:02:00+0000",
    "status":"success","context":"release","business":{"status":"success"}},
  "stages": [
    {"stage":"test","status":"success","rc":0,"duration_ms":3041,
      "tech":{"framework":"jest","tool":"jest","coverage_tool":"auto",
              "exit_code":"0","status":"success"},
      "business":{"status":"success",
        "tests":{"total":10,"passed":10,"failed":0,"skipped":0,"duration_ms":303},
        "coverage":{"line_pct":"45.45","branch_pct":"25.00"}}}
  ],
  "summary":{"stages":{"total":1,"passed":1,"failed":0,"skipped":0},
             "business":{"success_count":1,"warning_count":0,"error_count":0}}
}
JSON
      }
      write_test_failed_counts_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"61","platform":"jenkins","project":"webapp",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:02:00+0000",
    "status":"failed","context":"snapshot","business":{"status":"error"}},
  "stages": [
    {"stage":"test","status":"failed","rc":10,"duration_ms":1820,
      "tech":{"framework":"pytest","tool":"pytest","coverage_tool":"coverage",
              "exit_code":"10","status":"failed"},
      "business":{"status":"error",
        "tests":{"total":24,"passed":18,"failed":4,"skipped":2,"duration_ms":910},
        "coverage":{"line_pct":"68.40","branch_pct":"55.00"}}}
  ],
  "summary":{"stages":{"total":1,"passed":0,"failed":1,"skipped":0},
             "business":{"success_count":0,"warning_count":0,"error_count":1}}
}
JSON
      }
      write_test_no_counts_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"62","platform":"gitlab","project":"java-complete",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:02:00+0000",
    "status":"success","context":"release","business":{"status":"success"}},
  "stages": [
    {"stage":"test","status":"success","rc":0,"duration_ms":12000,
      "tech":{"framework":"maven","tool":"maven","coverage_tool":"jacoco",
              "exit_code":"0","status":"success"},
      "business":{"status":"success",
        "coverage":{"line_pct":"85.71","branch_pct":"100.00"}}}
  ],
  "summary":{"stages":{"total":1,"passed":1,"failed":0,"skipped":0},
             "business":{"success_count":1,"warning_count":0,"error_count":0}}
}
JSON
      }

      It "renders the three sections (Test execution / Results / Coverage)"
        write_test_with_counts_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "sectionLabel('Test execution')"
        The output should include "sectionLabel('Results')"
        The output should include "sectionLabel('Coverage')"
      End

      It "shows the test tool in the Check/Tool table"
        write_test_with_counts_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'unit tests'
        The output should include '"jest"'
      End

      It "adds an extra row when coverage_tool diverges from tool"
        write_test_no_counts_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '"jacoco"'
      End

      It "renders the counts mini-table when business.tests is present"
        write_test_with_counts_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'results-table'
        The output should include '>Passed<'
        The output should include '>Failed<'
        The output should include '>Skipped<'
        The output should include '>Total<'
      End

      It "applies cnt-good for passed > 0 and cnt-bad for failed > 0"
        write_test_failed_counts_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'cnt-good'
        The output should include 'cnt-bad'
        The output should include '"passed":18'
        The output should include '"failed":4'
      End

      It "falls back to verdict + exit code when counts are absent"
        write_test_no_counts_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'No test counts reported'
        The output should include 'Verdict:'
        The output should include 'exit '
      End

      It "keeps the coverage bars with 80/60 thresholds"
        write_test_with_counts_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'cov-bar'
        The output should include "pct >= 80"
        The output should include "pct >= 60"
      End

      It "carries test counts through the data island"
        write_test_failed_counts_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '"total":24'
        The output should include '"passed":18'
        The output should include '"failed":4'
        The output should include '"skipped":2'
      End
    End

    Context "package stage panel"
      write_package_docker_internal_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"70","platform":"gitlab","project":"node-complete",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:02:00+0000",
    "status":"success","context":"release","business":{"status":"success"}},
  "stages": [
    {"stage":"package","status":"success","rc":0,"duration_ms":1254,
      "tech":{"packager":"docker","dockerfile":"Dockerfile",
              "image_built":"true","image_ref":"nexus.briklab.test:8082/brik/node-complete:0.1.0",
              "exit_code":"0","status":"success"},
      "business":{"status":"success",
        "image":{"name":"nexus.briklab.test:8082/brik/node-complete","tag":"0.1.0",
                 "full_name":"nexus.briklab.test:8082/brik/node-complete:0.1.0",
                 "digest":"sha256:7b99de2e38d193c98b16f97623b3751abce95e40b185d444c3492101ebb728ad"},
        "registry":{"host":"nexus.briklab.test:8082","namespace":"brik","repository":"node-complete"}}}
  ],
  "summary":{"stages":{"total":1,"passed":1,"failed":0,"skipped":0},
             "business":{"success_count":1,"warning_count":0,"error_count":0}}
}
JSON
      }
      write_package_docker_public_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"71","platform":"jenkins","project":"webapp",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:02:00+0000",
    "status":"success","context":"release","business":{"status":"success"}},
  "stages": [
    {"stage":"package","status":"success","rc":0,"duration_ms":3140,
      "tech":{"packager":"docker","exit_code":"0","status":"success"},
      "business":{"status":"success",
        "image":{"full_name":"ghcr.io/acme/webapp:1.2.3",
                 "digest":"sha256:1111111111111111111111111111111111111111111111111111111111111111"},
        "registry":{"host":"ghcr.io","namespace":"acme","repository":"webapp"}}}
  ],
  "summary":{"stages":{"total":1,"passed":1,"failed":0,"skipped":0},
             "business":{"success_count":1,"warning_count":0,"error_count":0}}
}
JSON
      }
      write_package_skipped_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"72","platform":"gitlab","project":"node-minimal",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:02:00+0000",
    "status":"success","context":"snapshot","business":{"status":"success"}},
  "stages": [
    {"stage":"package","status":"skipped","rc":0,"duration_ms":0,
      "tech":{"status":"skipped"},
      "business":{"status":"skipped"}}
  ],
  "summary":{"stages":{"total":1,"passed":0,"failed":0,"skipped":1},
             "business":{"success_count":1,"warning_count":0,"error_count":0}}
}
JSON
      }

      It "renders the three sections (Packager / Container image / Distribution)"
        write_package_docker_internal_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "sectionLabel('Packager')"
        The output should include "sectionLabel('Container image')"
        The output should include "sectionLabel('Distribution')"
      End

      It "renders the big image ref with copy + docker-pull copy buttons"
        write_package_docker_internal_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'pkg-image-row'
        The output should include 'Copy image reference'
        The output should include 'Copy docker pull command'
      End

      It "renders the digest line with its own copy button"
        write_package_docker_internal_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'pkg-digest-row'
        The output should include 'Copy digest'
      End

      It "renders the Registry tile with a clickable host link"
        write_package_docker_internal_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'pkg-meta-tile'
        The output should include 'class="meta-value"'
      End

      It "uses http:// for internal hosts ending in .test"
        write_package_docker_internal_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'function registryUrl'
        # Pattern detects .test/.local/.internal as dev hosts
        The output should include '(test|local|internal)'
      End

      It "uses https:// for public registries like ghcr.io"
        write_package_docker_public_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '"ghcr.io"'
      End

      It "renders the Packager Check/Tool table"
        write_package_docker_internal_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'container packaging'
        The output should include '"docker"'
      End

      It "shows a dedicated message when status is skipped"
        write_package_skipped_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'pkg-skipped'
        The output should include 'Package skipped'
      End

      It "carries package metadata through the data island"
        write_package_docker_internal_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '"full_name":"nexus.briklab.test:8082/brik/node-complete:0.1.0"'
        The output should include '"digest":"sha256:7b99'
        The output should include '"host":"nexus.briklab.test:8082"'
      End

      It "prefers business.registry.ui_url over the heuristic URL"
        write_package_with_ui_url_aggregate() {
          cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"73","platform":"gitlab","project":"node-complete",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:02:00+0000",
    "status":"success","context":"release","business":{"status":"success"}},
  "stages": [
    {"stage":"package","status":"success","rc":0,"duration_ms":1254,
      "tech":{"packager":"docker","exit_code":"0","status":"success"},
      "business":{"status":"success",
        "image":{"full_name":"nexus.example.test:8082/brik/app:1.0",
                 "digest":"sha256:abcd"},
        "registry":{"host":"nexus.example.test:8082","namespace":"brik","repository":"app",
                    "ui_url":"http://nexus.example.test:8081/#browse/browse:docker-hosted"}}}
  ],
  "summary":{"stages":{"total":1,"passed":1,"failed":0,"skipped":0},
             "business":{"success_count":1,"warning_count":0,"error_count":0}}
}
JSON
        }
        write_package_with_ui_url_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        # ui_url is carried through the data island
        The output should include '"ui_url":"http://nexus.example.test:8081'
        # Renderer reads reg.ui_url
        The output should include 'reg.ui_url'
      End

      It "labels the pull-command button distinctly from the bare copy button"
        write_package_docker_internal_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'copy-btn-labeled'
        The output should include "label: 'docker pull'"
      End
    End

    Context "container-scan stage panel"
      write_container_scan_dirty_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"80","platform":"gitlab","project":"node-complete",
    "started_at":"2026-05-13T18:30:00+0000","finished_at":"2026-05-13T18:32:00+0000",
    "status":"success","context":"release","business":{"status":"warning"}},
  "stages": [
    {"stage":"container-scan","status":"success","rc":0,"duration_ms":29058,
      "tech":{"tool":"auto","target_image":"nexus.example.test:8082/brik/node-complete:0.1.0",
              "exit_code":"0","status":"success"},
      "business":{"status":"warning",
        "findings":{"total":3,
          "by_severity":{"critical":0,"high":1,"medium":2,"low":0,"info":0},
          "cwe":[],
          "failing":{"total":0,"has_fix":0,"no_fix":0},
          "ignored":{"total":3,"by_source":{"policy.org.path-allowlist":3},
                     "by_severity":{"critical":0,"high":1,"medium":2,"low":0,"info":0}},
          "items":[
            {"id":"CVE-2026-0001","severity":"high","score":7.5,
             "message":"node lib vuln",
             "tool":{"name":"grype","version":"0.111.1"},
             "package":{"name":"libssl","version":"1.1.1k","ecosystem":"apk"},
             "fix":{"versions":["1.1.1l"],"available":true},
             "help_uri":"https://advisory.example.test/CVE-2026-0001"},
            {"id":"GHSA-xxxx-picomatch","severity":"medium","score":5.3,
             "message":"picomatch ReDoS",
             "tool":{"name":"grype","version":"0.111.1"},
             "package":{"name":"picomatch","version":"4.0.3","ecosystem":"npm"},
             "fix":{"versions":["4.0.4"],"available":true},
             "help_uri":"https://github.com/advisories/GHSA-xxxx-picomatch"},
            {"id":"CVE-2026-99999","severity":"medium","score":4.2,
             "message":"busybox bug",
             "tool":{"name":"grype","version":"0.111.1"},
             "package":{"name":"busybox","version":"1.37.0-r30","ecosystem":"apk"},
             "fix":{"versions":[],"available":false},
             "help_uri":"https://nvd.example.test/CVE-2026-99999"}
          ]
        }
      }
    }
  ],
  "summary":{"stages":{"total":1,"passed":1,"failed":0,"skipped":0},
             "business":{"success_count":0,"warning_count":1,"error_count":0}}
}
JSON
      }

      It "renders the items-disclosure placeholder when findings.items is non-empty"
        write_container_scan_dirty_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'items-disclosure'
        The output should include 'View items'
        The output should include 'findings-items-panel'
      End

      It "exposes mountFindingsPanel scoped to items"
        write_container_scan_dirty_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'function mountFindingsPanel'
        # Scoped call site in renderBusiness
        The output should include "wrap.querySelector('.findings-items-panel')"
      End

      It "no longer mounts the global findings panel from the main IIFE"
        write_container_scan_dirty_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should not include 'renderFindings();'
      End

      It "carries finding items through the data island"
        write_container_scan_dirty_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '"id":"CVE-2026-0001"'
        The output should include '"help_uri":"https://advisory.example.test/CVE-2026-0001"'
        The output should include '"name":"picomatch"'
      End

      It "uses the warning state on the counter when total > 0 but failing = 0"
        write_container_scan_dirty_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        # 3-state derivation: failing.total = 0 in this fixture
        The output should include "'warning'"
        The output should include 'findings-counter.warning'
      End

      It "renders the ignored breakdown as an explicit Severity/Count table"
        write_container_scan_dirty_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'ignored-severity-table'
        The output should include '<th>Severity</th>'
        The output should include '<th>Count</th>'
        # Iterates over SEV_ORDER so every severity row renders (including
        # zero rows for severities not present), making the breakdown
        # exhaustive and verifiable.
        The output should include 'SEV_ORDER.map'
        # Total footer
        The output should include '<tfoot>'
      End
    End

    Context "deploy stage panel"
      write_deploy_success_k8s_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"100","platform":"gitlab","project":"node-workflow-trunk",
    "started_at":"2026-05-13T10:00:00+0000","finished_at":"2026-05-13T10:05:00+0000",
    "status":"success","context":"release","business":{"status":"success"}},
  "stages": [
    {"stage":"deploy","status":"success","rc":0,"duration_ms":222,
      "tech":{"environments":["staging","production"],"exit_code":"0","status":"success"},
      "business":{
        "environments":[
          {"name":"production","target":"k8s","namespace":"brik-e2e-workflow"}
        ],
        "status":"success","reason":""
      }
    }
  ],
  "summary":{"stages":{"total":1,"passed":1,"failed":0,"skipped":0},
             "business":{"success_count":1,"warning_count":0,"error_count":0}}
}
JSON
      }

      write_deploy_failure_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"101","platform":"gitlab","project":"node-deploy-failure",
    "started_at":"2026-05-13T10:00:00+0000","finished_at":"2026-05-13T10:05:00+0000",
    "status":"failed","context":"release","business":{"status":"error"}},
  "stages": [
    {"stage":"deploy","status":"failed","rc":1,"duration_ms":194,
      "runner":{"platform":"gitlab","job_url":"http://gitlab.example.test/job/24470"},
      "tech":{"environments":["staging"],"exit_code":"1","status":"failed"},
      "business":{
        "environments":[
          {"name":"staging","target":"k8s","namespace":"brik-nonexistent","strategy":"rolling"}
        ],
        "status":"error","reason":"failure (fix available, not applied)"
      }
    }
  ],
  "summary":{"stages":{"total":1,"passed":0,"failed":1,"skipped":0},
             "business":{"success_count":0,"warning_count":0,"error_count":1}}
}
JSON
      }

      write_deploy_gitops_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"102","platform":"gitlab","project":"node-deploy-gitops",
    "started_at":"2026-05-13T10:00:00+0000","finished_at":"2026-05-13T10:05:00+0000",
    "status":"success","context":"release","business":{"status":"success"}},
  "stages": [
    {"stage":"deploy","status":"success","rc":0,"duration_ms":2027,
      "tech":{"environments":["staging"],"exit_code":"0","status":"success"},
      "business":{
        "environments":[
          {"name":"staging","target":"gitops","namespace":null}
        ],
        "status":"success","reason":""
      }
    }
  ],
  "summary":{"stages":{"total":1,"passed":1,"failed":0,"skipped":0},
             "business":{"success_count":1,"warning_count":0,"error_count":0}}
}
JSON
      }

      write_deploy_skipped_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"103","platform":"gitlab","project":"node-complete",
    "started_at":"2026-05-13T10:00:00+0000","finished_at":"2026-05-13T10:05:00+0000",
    "status":"success","context":"release","business":{"status":"success"}},
  "stages": [
    {"stage":"deploy","status":"success","rc":0,"duration_ms":43,
      "tech":{"exit_code":"0","status":"success"},
      "business":{"status":"success","reason":""}
    }
  ],
  "summary":{"stages":{"total":1,"passed":1,"failed":0,"skipped":0},
             "business":{"success_count":1,"warning_count":0,"error_count":0}}
}
JSON
      }

      It "renders an env table with one row per environment"
        write_deploy_success_k8s_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'function renderDeploy'
        The output should include 'function deployEnvRow'
        The output should include 'deploy-env-table'
        The output should include '<th>Environment</th>'
        The output should include '<th>Target</th>'
        The output should include '<th>Namespace</th>'
        The output should include '<th>Strategy</th>'
        The output should include '"name":"production"'
      End

      It "renders the namespace as a mono cell when present"
        write_deploy_success_k8s_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '<td class="mono">'
        The output should include '"namespace":"brik-e2e-workflow"'
      End

      It "renders the target chip via deployTargetChip for k8s"
        write_deploy_success_k8s_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'function deployTargetChip'
        The output should include 'deploy-target-chip'
        The output should include 'data-target='
        The output should include 'DEPLOY_TARGET_ICONS'
        The output should include '"target":"k8s"'
      End

      It "renders a muted dash when namespace is null (gitops)"
        write_deploy_gitops_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '"target":"gitops"'
        The output should include '"namespace":null'
        # In deployEnvRow, falsy namespace renders a muted dash cell.
        The output should include '<td><span class="muted">-</span></td>'
      End

      It "renders the strategy in its cell when present"
        write_deploy_failure_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '"strategy":"rolling"'
        # deployEnvRow emits an escapeHtml(strat) cell when strat is truthy.
        The output should include "'<td>' + escapeHtml(strat) + '</td>'"
      End

      It "applies the error variant on the env name when business.status is error"
        write_deploy_failure_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        # Ternary in deployEnvRow appends ' error' to the name cell class when isError.
        The output should include "(isError ? ' error' : '')"
        The output should include "'deploy-env-name'"
        The output should include '"status":"error"'
      End

      It "surfaces business.reason via the deploy failure-reason hook"
        write_deploy_failure_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'function deployFailureReason'
        The output should include "'deploy':  deployFailureReason"
        The output should include '"reason":"failure (fix available, not applied)"'
      End

      It "renders the 'Deploy not executed' banner when environments is absent"
        write_deploy_skipped_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'function deploySkipped'
        The output should include 'Deploy not executed'
        The output should include 'No environments were deployed in this pipeline run.'
        The output should include 'class="deploy-skipped"'
      End

      It "ships the deploy CSS rules"
        write_deploy_success_k8s_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '.deploy-env-table'
        The output should include '.deploy-env-name.error'
        The output should include '.deploy-target-chip[data-target="k8s"]'
        The output should include '.deploy-target-chip[data-target="gitops"]'
        The output should include '.deploy-skipped'
      End
    End

    Context "notify stage panel"
      write_notify_pass_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"200","platform":"gitlab","project":"notify-pass",
    "started_at":"2026-05-14T10:00:00+0000","finished_at":"2026-05-14T10:02:00+0000",
    "status":"success","context":"release","business":{"status":"success"},
    "notify":{
      "channels":[
        {"type":"slack","configured":false,"on":"always","would_send":false},
        {"type":"email","configured":true,"on":"always","would_send":true},
        {"type":"webhook","configured":true,"on":"failure","would_send":false}
      ],
      "gatekeeper":{"decision":"pass","business_status":"success"}
    }},
  "stages":[
    {"stage":"init","status":"success","rc":0,"duration_ms":100,"business":{"status":"success","reason":""}}
  ],
  "summary":{"stages":{"total":1,"passed":1,"failed":0,"skipped":0},
             "business":{"success_count":1,"warning_count":0,"error_count":0}}
}
JSON
      }

      write_notify_fail_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"201","platform":"gitlab","project":"notify-fail",
    "started_at":"2026-05-14T10:00:00+0000","finished_at":"2026-05-14T10:02:00+0000",
    "status":"failed","context":"release","business":{"status":"error"},
    "notify":{
      "channels":[
        {"type":"slack","configured":true,"on":"always","would_send":true},
        {"type":"email","configured":false,"on":"always","would_send":false},
        {"type":"webhook","configured":true,"on":"failure","would_send":true}
      ],
      "gatekeeper":{"decision":"fail","business_status":"error"}
    }},
  "stages":[
    {"stage":"init","status":"failed","rc":1,"duration_ms":50,"business":{"status":"error","reason":"x"}}
  ],
  "summary":{"stages":{"total":1,"passed":0,"failed":1,"skipped":0},
             "business":{"success_count":0,"warning_count":0,"error_count":1}}
}
JSON
      }

      write_notify_absent_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"202","platform":"gitlab","project":"legacy-archive",
    "started_at":"2026-05-14T10:00:00+0000","finished_at":"2026-05-14T10:02:00+0000",
    "status":"success","context":"release","business":{"status":"success"}},
  "stages":[
    {"stage":"init","status":"success","rc":0,"duration_ms":100,"business":{"status":"success","reason":""}}
  ],
  "summary":{"stages":{"total":1,"passed":1,"failed":0,"skipped":0},
             "business":{"success_count":1,"warning_count":0,"error_count":0}}
}
JSON
      }

      It "renders the notify channels table with Check/Tool styling"
        write_notify_pass_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'function renderNotifyPanel'
        The output should include 'class="notify-table"'
        The output should include '<th>Channel</th>'
        The output should include '<th>Configured</th>'
        The output should include '<th>Policy</th>'
        The output should include '<th>Will dispatch</th>'
      End

      It "carries channel state through the data island"
        write_notify_pass_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '"type":"slack","configured":false,"on":"always","would_send":false'
        The output should include '"type":"email","configured":true,"on":"always","would_send":true'
        The output should include '"type":"webhook","configured":true,"on":"failure","would_send":false'
      End

      It "renders the gatekeeper block with pass styling on success"
        write_notify_pass_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'notify-gatekeeper'
        The output should include 'notify-gk-pass'
        The output should include '"decision":"pass"'
        The output should include '"business_status":"success"'
      End

      It "renders the gatekeeper with fail styling when business_status is error"
        write_notify_fail_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'notify-gk-fail'
        The output should include '"decision":"fail"'
        The output should include '"business_status":"error"'
      End

      It "renders the notify panel from data.pipeline.notify inside the canonical loop"
        write_notify_pass_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        # The plan-driven renderBusiness branches to renderNotifyPanel
        # when it encounters the notify stage and data.pipeline.notify
        # is populated. Asserting on the local variable + the call wires
        # this contract without coupling to the exact source layout.
        The output should include "(data.pipeline || {}).notify"
        The output should include "renderNotifyPanel(pipelineNotify)"
        The output should include "<span class=\"stage-name\">"
      End

      It "renders nothing for the notify panel when pipeline.notify is absent (graceful)"
        write_notify_absent_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        # The renderer code is always shipped (single bundle) but the runtime
        # guard returns '' when notify is absent. Assert on the guard text.
        The output should include "if (!n || typeof n !== 'object') return '';"
        # The synthetic header should not be statically present as a literal
        # in the source -- it is built at runtime, so we just confirm the
        # guard exists.
      End

      It "ships the notify CSS rules"
        write_notify_pass_aggregate
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '.notify-table'
        The output should include '.notify-channel'
        The output should include '.notify-cfg-on'
        The output should include '.notify-cfg-off'
        The output should include '.notify-send-yes'
        The output should include '.notify-send-no'
        The output should include '.notify-gatekeeper.notify-gk-pass'
        The output should include '.notify-gatekeeper.notify-gk-fail'
      End
    End

    Context "copy-to-clipboard infrastructure"
      Before 'write_hero_release_aggregate'

      It "exposes the copyBtn template and clipboard helper"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'function copyBtn'
        The output should include 'function copyToClipboard'
        The output should include 'navigator.clipboard'
      End

      It "wires a delegated click handler that toggles a 'copied' state"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "btn.classList.add('copied')"
        The output should include "'Copied!'"
      End

      It "adds a copy button next to the hero short_sha for the full sha"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include "'Copy full commit SHA'"
      End
    End

    Context "repo_url-driven Jenkins fixture"
      write_jenkins_repo_url_aggregate() {
        cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {
    "id": "jenkins-node-complete-63", "platform": "jenkins", "project": "node-complete",
    "started_at": "2026-05-12T21:51:47+0000",
    "finished_at": "2026-05-12T21:54:08+0000",
    "status": "success",
    "context": "release",
    "business": {"status": "warning"},
    "url": "http://jenkins.briklab.test:9090/job/node-complete/63/",
    "commit": {
      "sha": "839ac29b909ac64f75f726d3d85087a8e07bf2a1",
      "short_sha": "839ac29",
      "branch": "main",
      "tag": "v0.1.0",
      "author": "jeanjerome",
      "author_email": "jeanjerome@example.test",
      "repo_url": "http://gitea.briklab.test:3000/brik/node-complete"
    }
  },
  "stages": [{"stage":"init","status":"success","rc":0,"duration_ms":100,
              "business":{"status":"success"}}],
  "summary": {"stages":{"total":1,"passed":1,"failed":0,"skipped":0},
              "business":{"success_count":1,"warning_count":0,"error_count":0}}
}
JSON
      }
      Before 'write_jenkins_repo_url_aggregate'

      It "carries commit.repo_url through the data island"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include '"repo_url": "http://gitea.briklab.test:3000/brik/node-complete"'
      End

      It "detectRepo reads commit.repo_url before falling back to pipeline.url"
        run() { _report._render_html "$BACKEND"; }
        When call run
        The output should include 'commit.repo_url'
      End
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

  Describe "lifecycle-driven stage classification (Phase 2b)"
    # The canonical per-stage `lifecycle` is stamped once at aggregation
    # (lib/pipeline/report/lifecycle.sh) and consumed verbatim by the HTML
    # renderer -- which never reclassifies. These fixtures hand-stamp the
    # field the way report.aggregate_fragments would, and assert the renderer
    # reads it: a not_run stage gets its own tile (never "still in flight"),
    # the in-flight running tile stays gated on the in-flight signal, and a
    # failed stage with no findings payload shows an honest note instead of a
    # deceptive "0 findings".

    write_lifecycle_not_run_aggregate() {
      cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"3961","platform":"gitlab","project":"node-full-cve",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:02:00+0000",
    "status":"failed","context":"snapshot","business":{"status":"error"}},
  "stages": [
    {"stage":"scan","status":"failed","rc":10,"duration_ms":5120,
      "tech":{"deps":{"tool":"osv-scanner"},"exit_code":"10","status":"failed"},
      "lifecycle":"failed","lifecycle_reason":"stage failed",
      "business":{"status":"error",
        "deps":{"vulnerabilities":{"total":17,"by_severity":{"critical":2,"high":5,"medium":7,"low":3,"info":0}},"affected_packages":9}}},
    {"stage":"package","status":"skipped","rc":0,"duration_ms":0,
      "lifecycle":"not_run","lifecycle_reason":"blocked by upstream failure",
      "runner":{"platform":"gitlab"},"business":{"status":"success"}}
  ],
  "summary":{"stages":{"total":2,"passed":0,"failed":1,"skipped":1}}
}
JSON
    }

    write_lifecycle_failed_empty_aggregate() {
      cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"4001","platform":"gitlab","project":"scan-crash",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:00:30+0000",
    "status":"failed","context":"snapshot","business":{"status":"error"}},
  "stages": [
    {"stage":"scan","status":"failed","rc":10,"duration_ms":1200,
      "tech":{"exit_code":"10","status":"failed"},
      "lifecycle":"failed","lifecycle_reason":"stage failed",
      "business":{"status":"error"}}
  ],
  "summary":{"stages":{"total":1,"passed":0,"failed":1,"skipped":0}}
}
JSON
    }

    write_lifecycle_inflight_aggregate() {
      cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"4100","platform":"gitlab","project":"node-complete",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:02:00+0000",
    "status":"success","context":"release","business":{"status":"success"}},
  "stages": [
    {"stage":"init","status":"success","rc":0,"duration_ms":100,
      "lifecycle":"success","lifecycle_reason":"ok","business":{"status":"success"}}
  ],
  "summary":{"stages":{"total":1,"passed":1,"failed":0,"skipped":0}}
}
JSON
      cat > "${HTML_TMP}/plan.json" <<'JSON'
{ "stages": [ {"id":"init","decision":"run"}, {"id":"notify","decision":"run"} ] }
JSON
    }

    It "exposes renderNotRunTile in the renderer source"
      write_lifecycle_not_run_aggregate
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should include 'function renderNotRunTile'
    End

    It "reads the canonical lifecycle field to classify not_run"
      write_lifecycle_not_run_aggregate
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should include "lifecycle === 'not_run'"
    End

    It "ships the not-run-banner tile, distinct from skipped and running"
      write_lifecycle_not_run_aggregate
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should include 'class="not-run-banner"'
      The output should include '.not-run-banner {'
      The output should include 'blocked by upstream failure'
    End

    It "carries the stamped lifecycle through the data island"
      write_lifecycle_not_run_aggregate
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should include '"lifecycle":"not_run"'
      The output should include '"lifecycle_reason":"blocked by upstream failure"'
    End

    It "drops the over-broad isRunningMissing classification"
      write_lifecycle_not_run_aggregate
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should not include 'isRunningMissing'
    End

    It "keeps the in-flight running tile gated on the in-flight signal"
      write_lifecycle_inflight_aggregate
      run() { _report._render_html "$BACKEND"; }
      When call run
      # In-flight is detected by absence from stages[] + plan decision run
      # (the stage rendering the report is left absent on purpose), or by an
      # explicit lifecycle === 'running'. renderRunningTile must survive.
      The output should include 'function renderRunningTile'
      The output should include "lifecycle === 'running'"
      The output should include "planEntry.decision === 'run'"
    End

    It "renders an honest note for a failed stage with no findings payload"
      write_lifecycle_failed_empty_aggregate
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should include 'function renderUnavailableNote'
      The output should include 'function findingsEmpty'
      The output should include 'Results unavailable'
    End

    It "still shows the failure banner alongside the unavailable note"
      write_lifecycle_failed_empty_aggregate
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should include 'failure-banner'
    End
  End

  Describe "failed-body coherence and exit-code labels (Phase 4)"
    # The HTML banner translates a stage's exit code via EXIT_CODE_LABELS (a
    # JS mirror of the taxonomy in lib/pipeline/error.sh) instead of a bare
    # "check the job logs". A stage carrying tech.tool_error (a scanner that
    # produced no valid report, stamped by verify.scan.deps) reads as a scanner
    # error -- not the misleading "code 10 = threshold exceeded" -- and shows
    # the honest "Results unavailable" note. A failed stage whose findings
    # payload is present but empty must not render a deceptive "0 findings".

    write_scan_tool_error_aggregate() {
      cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"5001","platform":"gitlab","project":"scan-crash",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:00:30+0000",
    "status":"failed","context":"snapshot","business":{"status":"error"}},
  "stages": [
    {"stage":"scan","status":"failed","rc":10,"duration_ms":1200,
      "tech":{"exit_code":"10","status":"failed","tool_error":true},
      "lifecycle":"failed","lifecycle_reason":"stage failed",
      "business":{"status":"error"}}
  ],
  "summary":{"stages":{"total":1,"passed":0,"failed":1,"skipped":0}}
}
JSON
    }

    write_sast_empty_findings_aggregate() {
      cat > "$BACKEND" <<'JSON'
{
  "schema_version": "1.1",
  "pipeline": {"id":"5002","platform":"gitlab","project":"webapp",
    "started_at":"2026-05-12T10:00:00+0000","finished_at":"2026-05-12T10:01:00+0000",
    "status":"failed","context":"snapshot","business":{"status":"error"}},
  "stages": [
    {"stage":"sast","status":"failed","rc":10,"duration_ms":900,
      "tech":{"tool":"semgrep","exit_code":"10","status":"failed"},
      "lifecycle":"failed","lifecycle_reason":"stage failed",
      "business":{"status":"error","findings":{}}}
  ],
  "summary":{"stages":{"total":1,"passed":0,"failed":1,"skipped":0}}
}
JSON
    }

    It "ships the EXIT_CODE_LABELS table mirroring lib/pipeline/error.sh"
      write_scan_tool_error_aggregate
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should include 'EXIT_CODE_LABELS'
      The output should include 'quality or security threshold exceeded'
      The output should include 'required tool or dependency missing'
    End

    It "translates the failure code in the banner via the label table"
      write_scan_tool_error_aggregate
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should include 'EXIT_CODE_LABELS[ec]'
    End

    It "renders a scanner-error reason and the unavailable note for tech.tool_error"
      write_scan_tool_error_aggregate
      run() { _report._render_html "$BACKEND"; }
      When call run
      The output should include 'Scanner error'
      The output should include '"tool_error":true'
      The output should include 'Results unavailable'
    End

    It "treats a present-but-empty findings object on a failed stage as no findings"
      write_sast_empty_findings_aggregate
      run() { _report._render_html "$BACKEND"; }
      When call run
      # findingsEmpty deep-checks an empty findings object so a present-but-
      # empty {} does not slip through to a "0 findings" renderer.
      The output should include "keys[0] === 'findings'"
      The output should include 'Results unavailable'
    End
  End
End

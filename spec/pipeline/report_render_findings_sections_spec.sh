#shellcheck shell=bash
# Tests for the chantier 20260508 P6.B markdown sections rendered by
# _report._render_aggregate_md: Active policy, Failing findings, Ignored
# findings, Expiring soon.

Describe "_report._render_aggregate_md - findings sections (P6.B)"
  Include "$BRIK_PIPELINE_LIB/report.sh"

  setup_md_env() {
    AGG_TMP="$(mktemp -d)"
    BACKEND="$AGG_TMP/aggregate.json"
  }
  cleanup_md_env() { rm -rf "$AGG_TMP"; }
  Before 'setup_md_env'
  After  'cleanup_md_env'

  # Write a fixture aggregate.json with policy + L4 v2 findings shape.
  write_full_aggregate() {
    cat > "$BACKEND" <<'JSON'
{
  "pipeline": {
    "id": "test-1", "project": "demo", "platform": "gitlab",
    "status": "success", "started_at": "2026-05-08T18:00:00Z", "finished_at": "2026-05-08T18:05:00Z"
  },
  "stages": [
    { "stage": "sast", "status": "success", "rc": 0, "duration_ms": 1234,
      "business": { "findings": {
        "total": 4, "failing": 1,
        "by_severity": {"critical":0,"high":1,"medium":3,"low":0,"info":0},
        "ignored": {
          "total": 3,
          "by_source": {"policy.built-in.below-severity":2,"policy.built-in.no-upstream-fix":1},
          "by_severity": {"critical":0,"high":0,"medium":3,"low":0,"info":0}
        }
      } } },
    { "stage": "container_scan", "status": "success", "rc": 0,
      "business": { "findings": {
        "total": 14, "failing": 0,
        "by_severity": {"critical":1,"high":2,"medium":10,"low":1,"info":0},
        "ignored": {
          "total": 14,
          "by_source": {"policy.built-in.below-severity":11,"policy.built-in.no-upstream-fix":3},
          "by_severity": {"critical":1,"high":2,"medium":10,"low":1,"info":0}
        }
      } } }
  ],
  "summary": {
    "stages": {"total":2,"passed":2,"failed":0,"skipped":0},
    "policy": {
      "preset": "pragmatic",
      "source": "org-policy",
      "org_policy_url": "https://example.com/brik-policy.yml",
      "org_policy_loaded_at": "2026-05-08T17:55:00Z",
      "expiring_soon": [
        {"id":"CVE-2026-9001","expires":"2026-05-20","days_remaining":12}
      ]
    }
  }
}
JSON
  }

  # Aggregate without policy + without ignored entries (legacy shape).
  write_minimal_aggregate() {
    cat > "$BACKEND" <<'JSON'
{
  "pipeline": {"id":"min","status":"success","started_at":"2026-05-08T18:00:00Z","finished_at":"2026-05-08T18:01:00Z"},
  "stages": [{"stage":"build","status":"success","rc":0}],
  "summary": {"stages":{"total":1,"passed":1,"failed":0,"skipped":0}}
}
JSON
  }

  Describe "rich aggregate"
    setup_rich() { write_full_aggregate; }
    Before 'setup_rich'

    It "renders the Active policy section with preset and URL"
      run() { _report._render_aggregate_md "$BACKEND"; }
      When call run
      The output should include "## Active policy"
      The output should include "**Preset:** pragmatic"
      The output should include "**Source:** org-policy"
      The output should include "https://example.com/brik-policy.yml"
    End

    It "renders the Failing findings table with the failing stage row"
      run() { _report._render_aggregate_md "$BACKEND"; }
      When call run
      The output should include "## Failing findings"
      The output should include "| sast | 1 | 4 | H:1 M:3 |"
      The output should not include "| container_scan | 0 | 14 |"
    End

    It "renders the Ignored findings table with by_source + by_severity"
      run() { _report._render_aggregate_md "$BACKEND"; }
      When call run
      The output should include "## Ignored findings"
      The output should include "policy.built-in.below-severity=2"
      The output should include "policy.built-in.no-upstream-fix=3"
      The output should include "C:1 H:2 M:10 L:1"
    End

    It "renders the Expiring soon table with the upcoming entry"
      run() { _report._render_aggregate_md "$BACKEND"; }
      When call run
      The output should include "## Expiring soon"
      The output should include "| CVE-2026-9001 | 2026-05-20 | 12 |"
    End
  End

  Describe "minimal legacy aggregate"
    setup_min() { write_minimal_aggregate; }
    Before 'setup_min'

    It "skips the Active policy section when summary.policy is absent"
      run() { _report._render_aggregate_md "$BACKEND"; }
      When call run
      The output should not include "## Active policy"
    End

    It "shows _No failing findings._ when no stage carries findings.failing"
      run() { _report._render_aggregate_md "$BACKEND"; }
      When call run
      The output should include "## Failing findings"
      The output should include "_No failing findings._"
    End

    It "shows _No ignored findings._ when no stage carries findings.ignored"
      run() { _report._render_aggregate_md "$BACKEND"; }
      When call run
      The output should include "## Ignored findings"
      The output should include "_No ignored findings._"
    End

    It "skips the Expiring soon section when expiring_soon is empty"
      run() { _report._render_aggregate_md "$BACKEND"; }
      When call run
      The output should not include "## Expiring soon"
    End
  End
End

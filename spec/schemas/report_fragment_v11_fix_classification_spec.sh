#shellcheck shell=bash
# v1.1 fragment schema: business.findings.failing.{total, has_fix, no_fix}
# typed int >= 0.
#
# Introduced by master chantier
# docs/chantiers/20260511_pipeline-behavior-model.md sub-chantier 1.
#
# Contract:
#   - business.findings stays an open block (additionalProperties: true) so
#     FMF L4 fields (total, by_severity, ignored.*) continue to land without
#     a schema bump.
#   - business.findings.failing is a strict sub-object with three optional
#     integer counts: total, has_fix, no_fix (each >= 0, additionalProperties
#     forbidden). A stage that produces no findings is not required to write
#     the failing block at all.
#   - by_source / by_severity / ignored.* shapes are NOT re-tested here:
#     they were already locked by the FMF chantier and live under the open
#     findings block.

Describe "schemas/report/v1.1/fragment.schema.json business.findings.failing"
  FRAGMENT_V11_SCHEMA="${BRIK_HOME}/schemas/report/v1.1/fragment.schema.json"

  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  validate_fragment_v11() {
    local payload="$1"
    local tmp
    tmp="$(mktemp).json"
    printf '%s\n' "$payload" > "$tmp"
    jv "$FRAGMENT_V11_SCHEMA" "$tmp" >/dev/null 2>&1
    local rc=$?
    rm -f "$tmp"
    return "$rc"
  }

  Describe "failing block typed contract"
    It "accepts a fragment with failing.{total, has_fix, no_fix} as non-negative integers"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "container-scan",
        "timestamp": "2026-05-11T10:00:00+0000",
        "rc": 10,
        "status": "failed",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "check-failed" },
        "business": {
          "status": "error",
          "reason": "11 fixable findings, 0 accepted",
          "findings": {
            "total": 18,
            "failing": { "total": 11, "has_fix": 11, "no_fix": 0 }
          }
        }
      }'
      When call validate_fragment_v11 "$payload"
      The status should be success
    End

    It "accepts a fragment with failing.has_fix=0 and failing.no_fix>0 (release-warning case)"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "sast",
        "timestamp": "2026-05-11T10:00:00+0000",
        "rc": 10,
        "status": "failed",
        "runner": { "platform": "jenkins" },
        "tech": { "kind": "check-failed" },
        "business": {
          "status": "warning",
          "reason": "3 findings without upstream fix",
          "findings": {
            "total": 3,
            "failing": { "total": 3, "has_fix": 0, "no_fix": 3 }
          }
        }
      }'
      When call validate_fragment_v11 "$payload"
      The status should be success
    End

    It "accepts a fragment with no findings block at all (backward compat)"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "build",
        "timestamp": "2026-05-11T10:00:00+0000",
        "rc": 0,
        "status": "success",
        "runner": { "platform": "local" },
        "tech": { "kind": "ok" },
        "business": { "status": "success" }
      }'
      When call validate_fragment_v11 "$payload"
      The status should be success
    End

    It "accepts a fragment with findings block but no failing sub-block (stage produced findings but none failing)"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "scan",
        "timestamp": "2026-05-11T10:00:00+0000",
        "rc": 0,
        "status": "success",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "ok" },
        "business": {
          "status": "success",
          "findings": { "total": 0 }
        }
      }'
      When call validate_fragment_v11 "$payload"
      The status should be success
    End

    It "rejects failing.total when negative"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "container-scan",
        "timestamp": "2026-05-11T10:00:00+0000",
        "rc": 10,
        "status": "failed",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "check-failed" },
        "business": {
          "status": "error",
          "findings": { "failing": { "total": -1, "has_fix": 0, "no_fix": 0 } }
        }
      }'
      When call validate_fragment_v11 "$payload"
      The status should not equal 0
    End

    It "rejects failing.has_fix when negative"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "container-scan",
        "timestamp": "2026-05-11T10:00:00+0000",
        "rc": 10,
        "status": "failed",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "check-failed" },
        "business": {
          "status": "error",
          "findings": { "failing": { "has_fix": -5 } }
        }
      }'
      When call validate_fragment_v11 "$payload"
      The status should not equal 0
    End

    It "rejects failing.no_fix when negative"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "container-scan",
        "timestamp": "2026-05-11T10:00:00+0000",
        "rc": 10,
        "status": "failed",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "check-failed" },
        "business": {
          "status": "error",
          "findings": { "failing": { "no_fix": -1 } }
        }
      }'
      When call validate_fragment_v11 "$payload"
      The status should not equal 0
    End

    It "rejects failing.total when not an integer (string)"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "container-scan",
        "timestamp": "2026-05-11T10:00:00+0000",
        "rc": 10,
        "status": "failed",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "check-failed" },
        "business": {
          "status": "error",
          "findings": { "failing": { "total": "11" } }
        }
      }'
      When call validate_fragment_v11 "$payload"
      The status should not equal 0
    End

    It "rejects failing.has_fix when not an integer (float)"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "container-scan",
        "timestamp": "2026-05-11T10:00:00+0000",
        "rc": 10,
        "status": "failed",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "check-failed" },
        "business": {
          "status": "error",
          "findings": { "failing": { "has_fix": 1.5 } }
        }
      }'
      When call validate_fragment_v11 "$payload"
      The status should not equal 0
    End

    It "rejects unknown properties inside failing (strict block)"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "container-scan",
        "timestamp": "2026-05-11T10:00:00+0000",
        "rc": 10,
        "status": "failed",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "check-failed" },
        "business": {
          "status": "error",
          "findings": { "failing": { "total": 1, "has_fix": 1, "unknown": 0 } }
        }
      }'
      When call validate_fragment_v11 "$payload"
      The status should not equal 0
    End
  End

  Describe "findings block stays open for FMF L4 fields"
    It "accepts findings.total + findings.by_severity (FMF L4 contract preserved)"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "sast",
        "timestamp": "2026-05-11T10:00:00+0000",
        "rc": 0,
        "status": "success",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "ok" },
        "business": {
          "status": "success",
          "findings": {
            "total": 3,
            "by_severity": { "critical": 0, "high": 0, "medium": 3, "low": 0, "info": 0 },
            "ignored": { "total": 3, "by_source": { "policy.built-in.below-severity": 3 } }
          }
        }
      }'
      When call validate_fragment_v11 "$payload"
      The status should be success
    End

    It "accepts findings.failing alongside findings.ignored.* (full FMF + fix-exists)"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "container-scan",
        "timestamp": "2026-05-11T10:00:00+0000",
        "rc": 10,
        "status": "failed",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "check-failed" },
        "business": {
          "status": "error",
          "reason": "11 fixable findings, 7 accepted",
          "findings": {
            "total": 18,
            "by_severity": { "critical": 0, "high": 11, "medium": 5, "low": 2, "info": 0 },
            "failing": { "total": 11, "has_fix": 11, "no_fix": 0 },
            "ignored": {
              "total": 7,
              "by_source": { "policy.built-in.below-severity": 7 },
              "by_severity": { "high": 0, "medium": 5, "low": 2 }
            }
          }
        }
      }'
      When call validate_fragment_v11 "$payload"
      The status should be success
    End
  End
End

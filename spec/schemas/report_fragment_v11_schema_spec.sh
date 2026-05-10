#shellcheck shell=bash
# Validation contract for the strict v1.1 fragment schema.
#
# v1.1 is the post-refactor schema (see chantier
# docs/chantiers/20260510_tech-business-orthogonal-axes.md):
#   - business.{status, reason} typed strict (status enum, reason string)
#   - tech.kind typed string
#   - tech.warning and tech.warning_reason rejected (replaced by business)
#   - schema_version pinned to "1.1"
#
# v1.0 remains available with additive fields and stays open under tech /
# business. v1.1 closes the doors that the legacy SKIP_WITH_WARNING design
# had pried open.

Describe "schemas/report/v1.1/fragment.schema.json"
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

  Describe "schema file"
    It "exists at the expected path"
      When call test -f "$FRAGMENT_V11_SCHEMA"
      The status should be success
    End

    It "is valid JSON"
      When call jq -e . "$FRAGMENT_V11_SCHEMA"
      The status should be success
      The output should not be blank
    End

    It "declares draft 2020-12"
      check_draft() { jq -r '."$schema"' "$FRAGMENT_V11_SCHEMA"; }
      When call check_draft
      The output should equal "https://json-schema.org/draft/2020-12/schema"
      The status should be success
    End

    It "pins schema_version as const 1.1"
      check_const() { jq -r '.properties.schema_version.const' "$FRAGMENT_V11_SCHEMA"; }
      When call check_const
      The output should equal "1.1"
      The status should be success
    End
  End

  Describe "minimal valid fragment"
    It "validates a stage with success technical status and success business outcome"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "build",
        "timestamp": "2026-05-10T10:00:00+0000",
        "rc": 0,
        "status": "success",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "ok" },
        "business": { "status": "success" }
      }'
      When call validate_fragment_v11 "$payload"
      The status should be success
    End
  End

  Describe "business block is strict"
    It "accepts business.status=success without reason"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "lint",
        "timestamp": "2026-05-10T10:00:00+0000",
        "rc": 0,
        "status": "success",
        "runner": { "platform": "jenkins" },
        "tech": { "kind": "ok" },
        "business": { "status": "success" }
      }'
      When call validate_fragment_v11 "$payload"
      The status should be success
    End

    It "accepts business.status=warning with a reason"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "container-scan",
        "timestamp": "2026-05-10T10:00:00+0000",
        "rc": 0,
        "status": "success",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "ok" },
        "business": {
          "status": "warning",
          "reason": "14 findings ignored by policy: 11 below severity, 3 no upstream fix"
        }
      }'
      When call validate_fragment_v11 "$payload"
      The status should be success
    End

    It "accepts business.status=error with a reason"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "test",
        "timestamp": "2026-05-10T10:00:00+0000",
        "rc": 1,
        "status": "failed",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "check-failed" },
        "business": {
          "status": "error",
          "reason": "test stage failed: 0 tests detected"
        }
      }'
      When call validate_fragment_v11 "$payload"
      The status should be success
    End

    It "rejects business.status outside the enum"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "lint",
        "timestamp": "2026-05-10T10:00:00+0000",
        "rc": 0,
        "status": "success",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "ok" },
        "business": { "status": "tolerated" }
      }'
      When call validate_fragment_v11 "$payload"
      The status should not equal 0
    End

    It "rejects unknown keys under business"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "lint",
        "timestamp": "2026-05-10T10:00:00+0000",
        "rc": 0,
        "status": "success",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "ok" },
        "business": { "status": "success", "garbage": "rejected" }
      }'
      When call validate_fragment_v11 "$payload"
      The status should not equal 0
    End
  End

  Describe "tech.warning is rejected (legacy SKIP_WITH_WARNING removed)"
    It "rejects a fragment that carries tech.warning=true"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "lint",
        "timestamp": "2026-05-10T10:00:00+0000",
        "rc": 0,
        "status": "skipped",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "ok", "warning": true },
        "business": { "status": "warning", "reason": "lint disabled by config (legacy)" }
      }'
      When call validate_fragment_v11 "$payload"
      The status should not equal 0
    End

    It "rejects a fragment that carries tech.warning_reason"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "lint",
        "timestamp": "2026-05-10T10:00:00+0000",
        "rc": 0,
        "status": "skipped",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "ok", "warning_reason": "legacy" },
        "business": { "status": "warning", "reason": "legacy" }
      }'
      When call validate_fragment_v11 "$payload"
      The status should not equal 0
    End
  End

  Describe "tech.kind is typed"
    It "accepts the canonical tech.kind values"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "stage": "scan",
        "timestamp": "2026-05-10T10:00:00+0000",
        "rc": 8,
        "status": "failed",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "timeout" },
        "business": { "status": "error", "reason": "timeout" }
      }'
      When call validate_fragment_v11 "$payload"
      The status should be success
    End
  End

  Describe "schema_version pinning"
    It "rejects fragments that declare schema_version other than 1.1"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "stage": "build",
        "timestamp": "2026-05-10T10:00:00+0000",
        "rc": 0,
        "status": "success",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "ok" },
        "business": { "status": "success" }
      }'
      When call validate_fragment_v11 "$payload"
      The status should not equal 0
    End
  End
End

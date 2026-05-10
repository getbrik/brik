#shellcheck shell=bash
# Validation contract for the strict v1.1 aggregate schema.
#
# v1.1 deltas vs v1.0 (see chantier
# docs/chantiers/20260510_tech-business-orthogonal-axes.md):
#   - pipeline.context required, enum {snapshot, release}
#   - summary.business required, typed strict {success_count, warning_count, error_count}
#   - pipeline.business required, typed strict {status enum}
#   - summary.warnings rejected (replaced by summary.business + per-stage business.reason)
#   - schema_version pinned to "1.1"
#   - stages[] items reference v1.1 fragment schema (carries business block)

Describe "schemas/report/v1.1/aggregate.schema.json"
  AGGREGATE_V11_SCHEMA="${BRIK_HOME}/schemas/report/v1.1/aggregate.schema.json"

  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  validate_aggregate_v11() {
    local payload="$1"
    local tmp
    tmp="$(mktemp).json"
    printf '%s\n' "$payload" > "$tmp"
    jv \
      --map "https://brik.dev/schemas/=${BRIK_HOME}/schemas/" \
      "$AGGREGATE_V11_SCHEMA" "$tmp" >/dev/null 2>&1
    local rc=$?
    rm -f "$tmp"
    return "$rc"
  }

  Describe "schema file"
    It "exists at the expected path"
      When call test -f "$AGGREGATE_V11_SCHEMA"
      The status should be success
    End

    It "is valid JSON"
      When call jq -e . "$AGGREGATE_V11_SCHEMA"
      The status should be success
      The output should not be blank
    End

    It "declares draft 2020-12"
      check_draft() { jq -r '."$schema"' "$AGGREGATE_V11_SCHEMA"; }
      When call check_draft
      The output should equal "https://json-schema.org/draft/2020-12/schema"
      The status should be success
    End

    It "pins schema_version as const 1.1"
      check_const() { jq -r '.properties.schema_version.const' "$AGGREGATE_V11_SCHEMA"; }
      When call check_const
      The output should equal "1.1"
      The status should be success
    End

    It "references the v1.1 fragment schema for stages array items"
      check_ref() { jq -r '.properties.stages.items."$ref"' "$AGGREGATE_V11_SCHEMA"; }
      When call check_ref
      The output should include "v1.1/fragment.schema.json"
      The status should be success
    End

    It "declares pipeline.context as a required property"
      check_required() { jq -r '.properties.pipeline.required | index("context") // -1' "$AGGREGATE_V11_SCHEMA"; }
      When call check_required
      The output should not equal "-1"
      The status should be success
    End

    It "constrains pipeline.context to {snapshot, release}"
      check_enum() { jq -c '.properties.pipeline.properties.context.enum' "$AGGREGATE_V11_SCHEMA"; }
      When call check_enum
      The output should equal '["snapshot","release"]'
      The status should be success
    End

    It "declares summary.business as a required key"
      check_required() { jq -r '.properties.summary.required | index("business") // -1' "$AGGREGATE_V11_SCHEMA"; }
      When call check_required
      The output should not equal "-1"
      The status should be success
    End

    It "rejects summary.warnings entirely (legacy)"
      check_no_warnings() { jq -e '.properties.summary.properties | has("warnings") | not' "$AGGREGATE_V11_SCHEMA"; }
      When call check_no_warnings
      The status should be success
      The output should equal "true"
    End
  End

  Describe "minimal valid v1.1 aggregate"
    minimal_payload='{
      "schema_version": "1.1",
      "pipeline": {
        "id": "1",
        "platform": "local",
        "project": "demo",
        "started_at": "2026-05-10T10:00:00+0000",
        "finished_at": "2026-05-10T10:15:00+0000",
        "status": "success",
        "context": "snapshot",
        "business": { "status": "success" }
      },
      "stages": [],
      "summary": {
        "stages":   { "total": 0, "passed": 0, "failed": 0, "skipped": 0 },
        "business": { "success_count": 0, "warning_count": 0, "error_count": 0 }
      }
    }'

    It "validates"
      Skip if "jv not installed" jv_missing
      When call validate_aggregate_v11 "$minimal_payload"
      The status should be success
    End
  End

  Describe "summary.business is strict"
    It "accepts non-zero counts"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "pipeline": {
          "id": "1", "platform": "gitlab", "project": "demo",
          "started_at": "2026-05-10T10:00:00+0000",
          "finished_at": "2026-05-10T10:15:00+0000",
          "status": "success",
          "context": "release",
          "business": { "status": "warning" }
        },
        "stages": [],
        "summary": {
          "stages":   { "total": 9, "passed": 8, "failed": 0, "skipped": 1 },
          "business": { "success_count": 7, "warning_count": 2, "error_count": 0 }
        }
      }'
      When call validate_aggregate_v11 "$payload"
      The status should be success
    End

    It "rejects negative counts"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "pipeline": {
          "id": "1", "platform": "gitlab", "project": "demo",
          "started_at": "2026-05-10T10:00:00+0000",
          "finished_at": "2026-05-10T10:15:00+0000",
          "status": "success",
          "context": "snapshot",
          "business": { "status": "success" }
        },
        "stages": [],
        "summary": {
          "stages":   { "total": 0, "passed": 0, "failed": 0, "skipped": 0 },
          "business": { "success_count": -1, "warning_count": 0, "error_count": 0 }
        }
      }'
      When call validate_aggregate_v11 "$payload"
      The status should not equal 0
    End

    It "rejects unknown keys under summary.business"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "pipeline": {
          "id": "1", "platform": "gitlab", "project": "demo",
          "started_at": "2026-05-10T10:00:00+0000",
          "finished_at": "2026-05-10T10:15:00+0000",
          "status": "success",
          "context": "snapshot",
          "business": { "status": "success" }
        },
        "stages": [],
        "summary": {
          "stages":   { "total": 0, "passed": 0, "failed": 0, "skipped": 0 },
          "business": { "success_count": 0, "warning_count": 0, "error_count": 0, "tolerated_count": 0 }
        }
      }'
      When call validate_aggregate_v11 "$payload"
      The status should not equal 0
    End

    It "rejects an aggregate that omits summary.business"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "pipeline": {
          "id": "1", "platform": "gitlab", "project": "demo",
          "started_at": "2026-05-10T10:00:00+0000",
          "finished_at": "2026-05-10T10:15:00+0000",
          "status": "success",
          "context": "snapshot",
          "business": { "status": "success" }
        },
        "stages": [],
        "summary": {
          "stages": { "total": 0, "passed": 0, "failed": 0, "skipped": 0 }
        }
      }'
      When call validate_aggregate_v11 "$payload"
      The status should not equal 0
    End
  End

  Describe "pipeline.business is strict"
    It "accepts pipeline.business.status=warning"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "pipeline": {
          "id": "1", "platform": "gitlab", "project": "demo",
          "started_at": "2026-05-10T10:00:00+0000",
          "finished_at": "2026-05-10T10:15:00+0000",
          "status": "success",
          "context": "snapshot",
          "business": { "status": "warning" }
        },
        "stages": [],
        "summary": {
          "stages":   { "total": 0, "passed": 0, "failed": 0, "skipped": 0 },
          "business": { "success_count": 0, "warning_count": 0, "error_count": 0 }
        }
      }'
      When call validate_aggregate_v11 "$payload"
      The status should be success
    End

    It "rejects pipeline.business.status outside the enum"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "pipeline": {
          "id": "1", "platform": "gitlab", "project": "demo",
          "started_at": "2026-05-10T10:00:00+0000",
          "finished_at": "2026-05-10T10:15:00+0000",
          "status": "success",
          "context": "snapshot",
          "business": { "status": "tolerated" }
        },
        "stages": [],
        "summary": {
          "stages":   { "total": 0, "passed": 0, "failed": 0, "skipped": 0 },
          "business": { "success_count": 0, "warning_count": 0, "error_count": 0 }
        }
      }'
      When call validate_aggregate_v11 "$payload"
      The status should not equal 0
    End
  End

  Describe "pipeline.context is strict"
    It "rejects an unknown context value"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "pipeline": {
          "id": "1", "platform": "gitlab", "project": "demo",
          "started_at": "2026-05-10T10:00:00+0000",
          "finished_at": "2026-05-10T10:15:00+0000",
          "status": "success",
          "context": "rehearsal",
          "business": { "status": "success" }
        },
        "stages": [],
        "summary": {
          "stages":   { "total": 0, "passed": 0, "failed": 0, "skipped": 0 },
          "business": { "success_count": 0, "warning_count": 0, "error_count": 0 }
        }
      }'
      When call validate_aggregate_v11 "$payload"
      The status should not equal 0
    End

    It "rejects a payload that omits pipeline.context"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "pipeline": {
          "id": "1", "platform": "gitlab", "project": "demo",
          "started_at": "2026-05-10T10:00:00+0000",
          "finished_at": "2026-05-10T10:15:00+0000",
          "status": "success",
          "business": { "status": "success" }
        },
        "stages": [],
        "summary": {
          "stages":   { "total": 0, "passed": 0, "failed": 0, "skipped": 0 },
          "business": { "success_count": 0, "warning_count": 0, "error_count": 0 }
        }
      }'
      When call validate_aggregate_v11 "$payload"
      The status should not equal 0
    End
  End

  Describe "summary.warnings is rejected (legacy)"
    It "rejects an aggregate that carries summary.warnings"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.1",
        "pipeline": {
          "id": "1", "platform": "gitlab", "project": "demo",
          "started_at": "2026-05-10T10:00:00+0000",
          "finished_at": "2026-05-10T10:15:00+0000",
          "status": "success",
          "context": "snapshot",
          "business": { "status": "warning" }
        },
        "stages": [],
        "summary": {
          "stages":   { "total": 0, "passed": 0, "failed": 0, "skipped": 0 },
          "business": { "success_count": 0, "warning_count": 0, "error_count": 0 },
          "warnings": [ { "stage": "lint", "reason": "legacy form" } ]
        }
      }'
      When call validate_aggregate_v11 "$payload"
      The status should not equal 0
    End
  End

  Describe "schema_version pinning"
    It "rejects fragments that declare schema_version 1.0"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "pipeline": {
          "id": "1", "platform": "gitlab", "project": "demo",
          "started_at": "2026-05-10T10:00:00+0000",
          "finished_at": "2026-05-10T10:15:00+0000",
          "status": "success",
          "context": "snapshot",
          "business": { "status": "success" }
        },
        "stages": [],
        "summary": {
          "stages":   { "total": 0, "passed": 0, "failed": 0, "skipped": 0 },
          "business": { "success_count": 0, "warning_count": 0, "error_count": 0 }
        }
      }'
      When call validate_aggregate_v11 "$payload"
      The status should not equal 0
    End
  End
End

Describe "schemas/report/v1/aggregate.schema.json"
  AGGREGATE_SCHEMA="${BRIK_HOME}/schemas/report/v1/aggregate.schema.json"
  FRAGMENT_SCHEMA="${BRIK_HOME}/schemas/report/v1/fragment.schema.json"

  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  # The aggregate schema embeds a $ref to fragment.schema.json (same dir).
  # jv resolves $ref by URL by default; --map redirects the canonical
  # https://brik.dev/schemas/ prefix to the local schemas/ directory so
  # validation works without network access.
  validate_aggregate() {
    local payload="$1"
    local tmp
    tmp="$(mktemp).json"
    printf '%s\n' "$payload" > "$tmp"
    jv \
      --map "https://brik.dev/schemas/=${BRIK_HOME}/schemas/" \
      "$AGGREGATE_SCHEMA" "$tmp" >/dev/null 2>&1
    local rc=$?
    rm -f "$tmp"
    return "$rc"
  }

  Describe "schema file"
    It "exists at the expected path"
      When call test -f "$AGGREGATE_SCHEMA"
      The status should be success
    End

    It "is valid JSON"
      When call jq -e . "$AGGREGATE_SCHEMA"
      The status should be success
      The output should not be blank
    End

    It "declares draft 2020-12"
      When call jq -r '."$schema"' "$AGGREGATE_SCHEMA"
      The output should equal "https://json-schema.org/draft/2020-12/schema"
      The status should be success
    End

    It "pins schema_version as const 1.0"
      When call jq -r '.properties.schema_version.const' "$AGGREGATE_SCHEMA"
      The output should equal "1.0"
      The status should be success
    End

    It "references the fragment schema for stages array items"
      When call jq -r '.properties.stages.items."$ref"' "$AGGREGATE_SCHEMA"
      The output should include "fragment.schema.json"
      The status should be success
    End
  End

  Describe "minimal valid aggregate"
    minimal_payload='{
      "schema_version": "1.0",
      "pipeline": {
        "id": "42",
        "platform": "local",
        "project": "demo",
        "started_at": "2026-04-21T14:00:00+0000",
        "finished_at": "2026-04-21T14:15:00+0000",
        "status": "success"
      },
      "stages": [],
      "summary": {
        "stages": { "total": 0, "passed": 0, "failed": 0, "skipped": 0 }
      }
    }'

    It "validates with no stages and minimal summary"
      Skip if "jv not installed" jv_missing
      When call validate_aggregate "$minimal_payload"
      The status should be success
    End
  End

  Describe "fully populated aggregate (chantier brief example)"
    full_payload='{
      "schema_version": "1.0",
      "pipeline": {
        "id": "42",
        "url": "https://gitlab.example.com/pipelines/42",
        "platform": "gitlab",
        "project": "my-app",
        "commit": {
          "sha": "abc123def456",
          "short_sha": "abc123d",
          "ref": "refs/heads/main",
          "branch": "main"
        },
        "started_at": "2026-04-21T14:00:00+0000",
        "finished_at": "2026-04-21T14:15:00+0000",
        "duration_ms": 900000,
        "status": "success",
        "triggered_by": "user@example.com"
      },
      "stages": [
        {
          "schema_version": "1.0",
          "stage": "init",
          "timestamp": "2026-04-21T14:00:00+0000",
          "rc": 0,
          "status": "success",
          "runner": { "platform": "gitlab" }
        }
      ],
      "summary": {
        "stages": { "total": 11, "passed": 7, "failed": 0, "skipped": 4 },
        "security": {
          "critical_findings": { "sast": 0, "scan_deps": 0, "container_scan": 0 },
          "total_vulnerabilities": 5
        },
        "test": {
          "total": 142,
          "passed": 140,
          "failed": 0,
          "skipped": 2,
          "coverage_line_pct": 87.3
        },
        "artifacts": {
          "image": "ghcr.io/org/app:1.2.0@sha256:abc",
          "version": "1.2.0",
          "deployed_to": "production"
        }
      },
      "proof": {
        "report_sha256": "sha256:xyz123",
        "artifact_urls": {
          "gitlab": "https://gitlab.example.com/jobs/99/artifacts/browse/brik-artifacts/",
          "jenkins": "https://jenkins.example.com/job/my-app/42/artifact/brik-artifacts/"
        },
        "signed": false
      }
    }'

    It "validates"
      Skip if "jv not installed" jv_missing
      When call validate_aggregate "$full_payload"
      The status should be success
    End
  End

  Describe "invalid aggregates are rejected"
    It "rejects missing pipeline"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "stages": [],
        "summary": { "stages": { "total": 0, "passed": 0, "failed": 0, "skipped": 0 } }
      }'
      When call validate_aggregate "$payload"
      The status should not equal 0
    End

    It "rejects missing stages"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "pipeline": {
          "id": "42", "platform": "local", "project": "demo",
          "started_at": "2026-04-21T14:00:00+0000",
          "finished_at": "2026-04-21T14:15:00+0000",
          "status": "success"
        },
        "summary": { "stages": { "total": 0, "passed": 0, "failed": 0, "skipped": 0 } }
      }'
      When call validate_aggregate "$payload"
      The status should not equal 0
    End

    It "rejects schema_version 2.0"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "2.0",
        "pipeline": {
          "id": "42", "platform": "local", "project": "demo",
          "started_at": "2026-04-21T14:00:00+0000",
          "finished_at": "2026-04-21T14:15:00+0000",
          "status": "success"
        },
        "stages": [],
        "summary": { "stages": { "total": 0, "passed": 0, "failed": 0, "skipped": 0 } }
      }'
      When call validate_aggregate "$payload"
      The status should not equal 0
    End

    It "rejects unknown pipeline.status enum value"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "pipeline": {
          "id": "42", "platform": "local", "project": "demo",
          "started_at": "2026-04-21T14:00:00+0000",
          "finished_at": "2026-04-21T14:15:00+0000",
          "status": "in_progress"
        },
        "stages": [],
        "summary": { "stages": { "total": 0, "passed": 0, "failed": 0, "skipped": 0 } }
      }'
      When call validate_aggregate "$payload"
      The status should not equal 0
    End

    It "rejects an invalid stage fragment in stages[]"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "pipeline": {
          "id": "42", "platform": "local", "project": "demo",
          "started_at": "2026-04-21T14:00:00+0000",
          "finished_at": "2026-04-21T14:15:00+0000",
          "status": "success"
        },
        "stages": [ { "schema_version": "1.0", "stage": "init" } ],
        "summary": { "stages": { "total": 0, "passed": 0, "failed": 0, "skipped": 0 } }
      }'
      When call validate_aggregate "$payload"
      The status should not equal 0
    End
  End

  Describe "summary section is open under nested keys"
    It "accepts arbitrary additional fields under summary"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "pipeline": {
          "id": "42", "platform": "local", "project": "demo",
          "started_at": "2026-04-21T14:00:00+0000",
          "finished_at": "2026-04-21T14:15:00+0000",
          "status": "success"
        },
        "stages": [],
        "summary": {
          "stages": { "total": 0, "passed": 0, "failed": 0, "skipped": 0 },
          "future_metric": { "anything": [1, 2, 3] }
        }
      }'
      When call validate_aggregate "$payload"
      The status should be success
    End
  End

  Describe "failed pipeline status"
    It "validates when pipeline.status is failed"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "pipeline": {
          "id": "42", "platform": "jenkins", "project": "demo",
          "started_at": "2026-04-21T14:00:00+0000",
          "finished_at": "2026-04-21T14:05:00+0000",
          "status": "failed"
        },
        "stages": [
          {
            "schema_version": "1.0",
            "stage": "build",
            "timestamp": "2026-04-21T14:02:00+0000",
            "rc": 1,
            "status": "failed",
            "runner": { "platform": "jenkins" }
          }
        ],
        "summary": { "stages": { "total": 1, "passed": 0, "failed": 1, "skipped": 0 } }
      }'
      When call validate_aggregate "$payload"
      The status should be success
    End
  End
End

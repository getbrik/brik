Describe "schemas/report/v1/fragment.schema.json"
  # Path to the schema under test.
  FRAGMENT_SCHEMA="${BRIK_HOME}/schemas/report/v1/fragment.schema.json"

  # jv on PATH gates these specs because the validation is what we are testing.
  # When jv is absent we Skip - the schema file existence is asserted separately.
  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  # Helper: write a fragment payload to a temp file, validate, return rc.
  # jv prints "schema ...: ok" / "instance ...: ok" diagnostics to stdout on
  # both success and failure; suppress them so ShellSpec does not flag the
  # examples as WARNED (we only assert on the exit status).
  validate_fragment() {
    local payload="$1"
    local tmp
    tmp="$(mktemp).json"
    printf '%s\n' "$payload" > "$tmp"
    jv "$FRAGMENT_SCHEMA" "$tmp" >/dev/null 2>&1
    local rc=$?
    rm -f "$tmp"
    return "$rc"
  }

  Describe "schema file"
    It "exists at the expected path"
      When call test -f "$FRAGMENT_SCHEMA"
      The status should be success
    End

    It "is valid JSON"
      When call jq -e . "$FRAGMENT_SCHEMA"
      The status should be success
      The output should not be blank
    End

    It "declares draft 2020-12"
      check_draft() {
        jq -r '."$schema"' "$FRAGMENT_SCHEMA"
      }
      When call check_draft
      The output should equal "https://json-schema.org/draft/2020-12/schema"
      The status should be success
    End

    It "pins schema_version as const 1.0"
      check_const() {
        jq -r '.properties.schema_version.const' "$FRAGMENT_SCHEMA"
      }
      When call check_const
      The output should equal "1.0"
      The status should be success
    End
  End

  Describe "minimal valid fragment"
    minimal_payload='{
      "schema_version": "1.0",
      "stage": "init",
      "timestamp": "2026-04-21T14:00:00+0000",
      "rc": 0,
      "status": "success",
      "runner": { "platform": "local" }
    }'

    It "validates"
      Skip if "jv not installed" jv_missing
      When call validate_fragment "$minimal_payload"
      The status should be success
    End
  End

  Describe "fully populated fragment"
    full_payload='{
      "schema_version": "1.0",
      "stage": "build",
      "timestamp": "2026-04-21T14:05:00+0000",
      "duration_ms": 2340,
      "rc": 0,
      "status": "success",
      "runner": {
        "platform": "gitlab",
        "image": "ghcr.io/getbrik/brik-runner-java:21",
        "job_url": "https://gitlab.example.com/jobs/123"
      },
      "tech": { "stack": "java", "tool": "maven" },
      "business": { "artifact": { "type": "jar", "name": "app-1.2.0.jar" } }
    }'

    It "validates with all optional fields"
      Skip if "jv not installed" jv_missing
      When call validate_fragment "$full_payload"
      The status should be success
    End
  End

  Describe "invalid fragments are rejected"
    It "rejects schema_version 2.0"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "2.0",
        "stage": "init",
        "timestamp": "2026-04-21T14:00:00+0000",
        "rc": 0,
        "status": "success",
        "runner": { "platform": "local" }
      }'
      When call validate_fragment "$payload"
      The status should not equal 0
    End

    It "rejects unknown status enum value"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "stage": "init",
        "timestamp": "2026-04-21T14:00:00+0000",
        "rc": 0,
        "status": "in_progress",
        "runner": { "platform": "local" }
      }'
      When call validate_fragment "$payload"
      The status should not equal 0
    End

    It "rejects missing required field stage"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "timestamp": "2026-04-21T14:00:00+0000",
        "rc": 0,
        "status": "success",
        "runner": { "platform": "local" }
      }'
      When call validate_fragment "$payload"
      The status should not equal 0
    End

    It "rejects missing required field runner"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "stage": "init",
        "timestamp": "2026-04-21T14:00:00+0000",
        "rc": 0,
        "status": "success"
      }'
      When call validate_fragment "$payload"
      The status should not equal 0
    End

    It "rejects unknown runner.platform value"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "stage": "init",
        "timestamp": "2026-04-21T14:00:00+0000",
        "rc": 0,
        "status": "success",
        "runner": { "platform": "circleci" }
      }'
      When call validate_fragment "$payload"
      The status should not equal 0
    End

    It "rejects negative rc"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "stage": "init",
        "timestamp": "2026-04-21T14:00:00+0000",
        "rc": -1,
        "status": "success",
        "runner": { "platform": "local" }
      }'
      When call validate_fragment "$payload"
      The status should not equal 0
    End
  End

  Describe "tech and business are open"
    It "accepts arbitrary nested fields under tech"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "stage": "test",
        "timestamp": "2026-04-21T14:00:00+0000",
        "rc": 0,
        "status": "success",
        "runner": { "platform": "gitlab" },
        "tech": { "framework": "junit", "deeply": { "nested": { "any": "value" } } }
      }'
      When call validate_fragment "$payload"
      The status should be success
    End

    It "accepts arbitrary nested fields under business"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "stage": "test",
        "timestamp": "2026-04-21T14:00:00+0000",
        "rc": 0,
        "status": "success",
        "runner": { "platform": "gitlab" },
        "business": { "tests": { "total": 142, "passed": 140, "by_tag": ["smoke", "unit"] } }
      }'
      When call validate_fragment "$payload"
      The status should be success
    End
  End

  Describe "skipped status"
    It "validates when stage is skipped"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "stage": "release",
        "timestamp": "2026-04-21T14:00:00+0000",
        "rc": 0,
        "status": "skipped",
        "runner": { "platform": "gitlab" }
      }'
      When call validate_fragment "$payload"
      The status should be success
    End
  End

  Describe "failed status"
    It "validates when rc is non-zero and status is failed"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "stage": "test",
        "timestamp": "2026-04-21T14:00:00+0000",
        "rc": 1,
        "status": "failed",
        "runner": { "platform": "jenkins" }
      }'
      When call validate_fragment "$payload"
      The status should be success
    End
  End

  # ----------------------------------------------------------------------
  # Additive v1.1 fields recognised under v1.0 (forward-compat)
  #
  # Sub-chantier 1 ships v1.1 schemas alongside v1.0 and lets producers
  # that still claim schema_version=1.0 opt-in to the new typed shapes
  # (business.status enum, business.reason, tech.kind enum). The fields
  # remain optional under v1.0; legacy producers that omit them still
  # validate. Producers that emit them with an out-of-enum value are
  # rejected so consumers can rely on the contract during the transition
  # to v1.1.
  # ----------------------------------------------------------------------
  Describe "additive v1.1 fields under v1.0 (forward-compat)"
    It "accepts a v1.0 fragment that emits business.status=success"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "stage": "build",
        "timestamp": "2026-05-10T10:00:00+0000",
        "rc": 0,
        "status": "success",
        "runner": { "platform": "gitlab" },
        "business": { "status": "success" }
      }'
      When call validate_fragment "$payload"
      The status should be success
    End

    It "accepts a v1.0 fragment that emits business.status=warning with reason"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "stage": "container-scan",
        "timestamp": "2026-05-10T10:00:00+0000",
        "rc": 0,
        "status": "success",
        "runner": { "platform": "gitlab" },
        "business": {
          "status": "warning",
          "reason": "14 findings ignored by policy"
        }
      }'
      When call validate_fragment "$payload"
      The status should be success
    End

    It "rejects a v1.0 fragment whose business.status is outside the enum"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "stage": "lint",
        "timestamp": "2026-05-10T10:00:00+0000",
        "rc": 0,
        "status": "success",
        "runner": { "platform": "gitlab" },
        "business": { "status": "tolerated" }
      }'
      When call validate_fragment "$payload"
      The status should not equal 0
    End

    It "accepts a v1.0 fragment that emits tech.kind=timeout"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "stage": "scan",
        "timestamp": "2026-05-10T10:00:00+0000",
        "rc": 8,
        "status": "failed",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "timeout" }
      }'
      When call validate_fragment "$payload"
      The status should be success
    End

    It "rejects a v1.0 fragment whose tech.kind is outside the enum"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "stage": "scan",
        "timestamp": "2026-05-10T10:00:00+0000",
        "rc": 8,
        "status": "failed",
        "runner": { "platform": "gitlab" },
        "tech": { "kind": "panic-attack" }
      }'
      When call validate_fragment "$payload"
      The status should not equal 0
    End

    It "still accepts a legacy v1.0 fragment that omits business and tech.kind"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "stage": "init",
        "timestamp": "2026-05-10T10:00:00+0000",
        "rc": 0,
        "status": "success",
        "runner": { "platform": "local" }
      }'
      When call validate_fragment "$payload"
      The status should be success
    End

    It "preserves backward compat for legacy tech.warning"
      Skip if "jv not installed" jv_missing
      payload='{
        "schema_version": "1.0",
        "stage": "lint",
        "timestamp": "2026-05-10T10:00:00+0000",
        "rc": 0,
        "status": "skipped",
        "runner": { "platform": "gitlab" },
        "tech": { "warning": true, "warning_reason": "lint disabled by config" }
      }'
      When call validate_fragment "$payload"
      The status should be success
    End
  End
End

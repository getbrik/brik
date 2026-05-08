Describe "schemas/policy/v1/brik-policy.schema.json"
  POLICY_SCHEMA="${BRIK_HOME}/schemas/policy/v1/brik-policy.schema.json"

  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  # Validate a JSON payload against the brik-policy schema. Writes the
  # payload to a tmp file (jv reads from disk to detect format by
  # extension) and discards stdout/stderr -- only the exit code matters.
  validate_policy() {
    local payload="$1"
    local tmp
    tmp="$(mktemp).json"
    printf '%s\n' "$payload" > "$tmp"
    jv "$POLICY_SCHEMA" "$tmp" >/dev/null 2>&1
    local rc=$?
    rm -f "$tmp"
    return "$rc"
  }

  Describe "schema file"
    It "exists at the expected path"
      When call test -f "$POLICY_SCHEMA"
      The status should be success
    End

    It "is valid JSON"
      When call jq -e . "$POLICY_SCHEMA"
      The status should be success
      The output should not be blank
    End

    It "declares draft 2020-12"
      When call jq -r '."$schema"' "$POLICY_SCHEMA"
      The output should equal "https://json-schema.org/draft/2020-12/schema"
      The status should be success
    End

    It "rejects unknown top-level keys (additionalProperties false)"
      When call jq -r '.additionalProperties' "$POLICY_SCHEMA"
      The output should equal "false"
      The status should be success
    End
  End

  Describe "minimal valid policy"
    It "validates an empty object"
      Skip if "jv not installed" jv_missing
      When call validate_policy '{}'
      The status should be success
    End

    It "validates a preset-only policy"
      Skip if "jv not installed" jv_missing
      When call validate_policy '{"preset": "strict"}'
      The status should be success
    End
  End

  Describe "preset enum"
    It "accepts pragmatic"
      Skip if "jv not installed" jv_missing
      When call validate_policy '{"preset": "pragmatic"}'
      The status should be success
    End

    It "accepts strict"
      Skip if "jv not installed" jv_missing
      When call validate_policy '{"preset": "strict"}'
      The status should be success
    End

    It "accepts permissive"
      Skip if "jv not installed" jv_missing
      When call validate_policy '{"preset": "permissive"}'
      The status should be success
    End

    It "rejects unknown preset values"
      Skip if "jv not installed" jv_missing
      When call validate_policy '{"preset": "aggressive"}'
      The status should be failure
    End
  End

  Describe "allow.cve entries"
    cve_full='{
      "allow": {
        "cve": [
          {
            "id": "CVE-2026-6100",
            "reason": "Python 3.14 binary CVE, no upstream fix; ARCHI-2026-042",
            "expires": "2026-08-01"
          }
        ]
      }
    }'

    cve_with_projects='{
      "allow": {
        "cve": [
          {
            "id": "CVE-2025-15366",
            "reason": "bandit dev-only, projet python-complete uniquement",
            "expires": "2026-12-31",
            "projects": ["python-complete"]
          }
        ]
      }
    }'

    cve_missing_reason='{
      "allow": {
        "cve": [
          { "id": "CVE-2026-1234", "expires": "2026-12-31" }
        ]
      }
    }'

    cve_missing_expires='{
      "allow": {
        "cve": [
          { "id": "CVE-2026-1234", "reason": "no fix" }
        ]
      }
    }'

    cve_unknown_field='{
      "allow": {
        "cve": [
          {
            "id": "CVE-2026-1234",
            "reason": "test",
            "expires": "2026-12-31",
            "extra_knob": "bogus"
          }
        ]
      }
    }'

    cve_expired='{
      "allow": {
        "cve": [
          { "id": "CVE-2024-0001", "reason": "stale", "expires": "2024-04-01" }
        ]
      }
    }'

    cve_bad_id='{
      "allow": {
        "cve": [
          { "id": "GHSA-abcd", "reason": "wrong format", "expires": "2026-12-31" }
        ]
      }
    }'

    It "validates a full CVE entry (id + reason + expires)"
      Skip if "jv not installed" jv_missing
      When call validate_policy "$cve_full"
      The status should be success
    End

    It "validates a CVE entry scoped to specific projects"
      Skip if "jv not installed" jv_missing
      When call validate_policy "$cve_with_projects"
      The status should be success
    End

    It "rejects a CVE entry missing reason (governance requirement)"
      Skip if "jv not installed" jv_missing
      When call validate_policy "$cve_missing_reason"
      The status should be failure
    End

    It "rejects a CVE entry missing expires (governance requirement)"
      Skip if "jv not installed" jv_missing
      When call validate_policy "$cve_missing_expires"
      The status should be failure
    End

    It "rejects unknown fields in CVE entries"
      Skip if "jv not installed" jv_missing
      When call validate_policy "$cve_unknown_field"
      The status should be failure
    End

    It "accepts expired entries at the schema level (runtime filters by date)"
      Skip if "jv not installed" jv_missing
      When call validate_policy "$cve_expired"
      The status should be success
    End

    It "rejects ids that do not match the CVE-YYYY-NNNN pattern"
      Skip if "jv not installed" jv_missing
      When call validate_policy "$cve_bad_id"
      The status should be failure
    End
  End

  Describe "allow.paths entries"
    path_full='{
      "allow": {
        "paths": [
          {
            "glob": "vendor/**",
            "reason": "Third-party, audit cycle separe",
            "expires": "2027-12-31"
          }
        ]
      }
    }'

    path_missing_glob='{
      "allow": {
        "paths": [
          { "reason": "no glob", "expires": "2026-12-31" }
        ]
      }
    }'

    path_with_projects='{
      "allow": {
        "paths": [
          {
            "glob": "legacy/**",
            "reason": "Legacy code en cours de retrait",
            "expires": "2026-12-31",
            "projects": ["legacy-app"]
          }
        ]
      }
    }'

    It "validates a full path entry"
      Skip if "jv not installed" jv_missing
      When call validate_policy "$path_full"
      The status should be success
    End

    It "validates a path entry scoped to specific projects"
      Skip if "jv not installed" jv_missing
      When call validate_policy "$path_with_projects"
      The status should be success
    End

    It "rejects a path entry missing glob"
      Skip if "jv not installed" jv_missing
      When call validate_policy "$path_missing_glob"
      The status should be failure
    End
  End

  Describe "full policy (preset + cve + paths)"
    full='{
      "preset": "pragmatic",
      "allow": {
        "cve": [
          {
            "id": "CVE-2026-6100",
            "reason": "Python 3.14 binary CVE, no upstream fix",
            "expires": "2026-08-01"
          }
        ],
        "paths": [
          {
            "glob": "vendor/**",
            "reason": "Third-party",
            "expires": "2027-12-31"
          }
        ]
      }
    }'

    It "validates the combined policy"
      Skip if "jv not installed" jv_missing
      When call validate_policy "$full"
      The status should be success
    End
  End
End

#shellcheck shell=bash
# Validation contract for the v1 stage-summary schema.
#
# Sprint  of 
# (docs/chantiers/20260528_e2e-tests-par-notion.md). This is the first L0
# spec of the new test architecture: it pins the I/O contract of the
# `stages` notion -- specifically the per-stage <stage>-summary.json file
# emitted by each non-meta stage of the fixed flow.
#
# v1 captures the format currently observed (10 mandatory fields, no
# tech/business enrichment). The future v2 will absorb the master #1
# enrichment currently described in schemas/report/v1.1/fragment.schema.json.
#
# Mirror pattern: spec/_legacy/schemas/report_fragment_v11_schema_spec.sh.

Describe "schemas/stages/v1/stage-summary.schema.json"
  STAGE_SUMMARY_V1_SCHEMA="${BRIK_HOME}/schemas/stages/v1/stage-summary.schema.json"
  SAMPLES_DIR="${BRIK_HOME}/spec/contracts/samples"

  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  validate_sample() {
    local payload_file="$1"
    jv "$STAGE_SUMMARY_V1_SCHEMA" "$payload_file" >/dev/null 2>&1
  }

  Describe "schema file"
    It "exists at the expected path"
      When call test -f "$STAGE_SUMMARY_V1_SCHEMA"
      The status should be success
    End

    It "is valid JSON"
      When call jq -e . "$STAGE_SUMMARY_V1_SCHEMA"
      The status should be success
      The output should not be blank
    End

    It "declares draft 2020-12"
      check_draft() { jq -r '."$schema"' "$STAGE_SUMMARY_V1_SCHEMA"; }
      When call check_draft
      The output should equal "https://json-schema.org/draft/2020-12/schema"
      The status should be success
    End

    It "has additionalProperties: false (strict v1 contract)"
      check_strict() { jq -r '.additionalProperties' "$STAGE_SUMMARY_V1_SCHEMA"; }
      When call check_strict
      The output should equal "false"
      The status should be success
    End

    It "requires the 10 v1 fields"
      check_required() {
        jq -r '.required | sort | join(",")' "$STAGE_SUMMARY_V1_SCHEMA"
      }
      When call check_required
      The output should equal "artifacts,duration_ms,errors,exit_code,finished_at,log_file,stage_name,started_at,status,warnings"
      The status should be success
    End
  End

  Describe "stage_name enum"
    It "lists the 12 canonical brik stages excluding 'plan'"
      check_stages() {
        jq -r '.properties.stage_name.enum | sort | join(",")' "$STAGE_SUMMARY_V1_SCHEMA"
      }
      When call check_stages
      The output should equal "build,container-scan,deploy,init,lint,notify,package,promote,release,sast,scan,test"
      The status should be success
    End
  End

  Describe "status enum"
    It "lists exactly SUCCESS and FAILED (v0.6.0 observed values)"
      check_status() {
        jq -r '.properties.status.enum | sort | join(",")' "$STAGE_SUMMARY_V1_SCHEMA"
      }
      When call check_status
      The output should equal "FAILED,SUCCESS"
      The status should be success
    End
  End

  Describe "valid samples (extracted from campaign the test campaign)"
    It "accepts init-success.json (init stage SUCCESS, real sample)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/valid/init-success.json"
      The status should be success
    End

    It "accepts deploy-success.json (deploy stage SUCCESS, real sample)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/valid/deploy-success.json"
      The status should be success
    End

    It "accepts scan-failed.json (scan stage FAILED with non-empty errors, real sample)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/valid/scan-failed.json"
      The status should be success
    End
  End

  Describe "invalid samples (synthetic, contract violations)"
    It "rejects 01-unknown-stage-name.json (stage_name='bogus-stage' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/invalid/01-unknown-stage-name.json"
      The status should not equal 0
    End

    It "rejects 02-invalid-status-value.json (status='success' lowercase, not in enum)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/invalid/02-invalid-status-value.json"
      The status should not equal 0
    End

    It "rejects 03-missing-log-file.json (required field absent)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/invalid/03-missing-log-file.json"
      The status should not equal 0
    End

    It "rejects 04-extra-property.json (additionalProperties: false enforced, no tech.* in v1)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/invalid/04-extra-property.json"
      The status should not equal 0
    End

    It "rejects 05-bad-timestamp.json (started_at does not match ISO 8601 with offset pattern)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/invalid/05-bad-timestamp.json"
      The status should not equal 0
    End

    It "rejects 06-negative-duration.json (duration_ms minimum: 0)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/invalid/06-negative-duration.json"
      The status should not equal 0
    End

    It "rejects 07-negative-exit-code.json (exit_code minimum: 0)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/invalid/07-negative-exit-code.json"
      The status should not equal 0
    End

    It "rejects 08-plan-not-in-enum.json (the 'plan' stage does not produce a summary -- it owns plan.json instead, planning notion)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/invalid/08-plan-not-in-enum.json"
      The status should not equal 0
    End
  End

  Describe "campaign-wide validation (regression guard)"
    # This block validates the schema against ALL 60 <stage>-summary.json
    # files captured during the test campaign. A future
    # contract update (v1 -> v2) that breaks any of these samples will
    # surface here, forcing an explicit decision (migrate samples or bump
    # schema version).

    campaign_dir() {
      local d="${BRIK_HOME}/../docs/chantiers/e2e-cross-platform-v0.6.0/logs"
      [[ -d "$d" ]] && cd "$d" 2>/dev/null && pwd
    }

    campaign_missing() {
      local d
      d="$(campaign_dir)"
      [[ -z "$d" ]]
    }

    validate_all_campaign_summaries() {
      local d
      d="$(campaign_dir)"
      [[ -z "$d" ]] && return 1
      local fail=0
      while IFS= read -r -d '' f; do
        if ! jv "$STAGE_SUMMARY_V1_SCHEMA" "$f" >/dev/null 2>&1; then
          fail=$((fail + 1))
          printf 'FAIL: %s\n' "$f" >&2
        fi
      done < <(find "$d" -name "*-summary.json" -path "*/.brik-logs/*" -print0 2>/dev/null)
      return "$fail"
    }

    It "all 60 campaign <stage>-summary.json files validate against v1"
      Skip if "jv not installed" jv_missing
      Skip if "campaign workspace not available" campaign_missing
      When call validate_all_campaign_summaries
      The status should be success
    End
  End
End

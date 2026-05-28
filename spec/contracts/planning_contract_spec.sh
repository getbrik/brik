#shellcheck shell=bash
# Validation contract for the v1 plan.json schema.
#
# The plan.json file is the output contract of lib/planning/: produced by
# `brik plan` and consumed by every stage via `brik plan gate <stage>`.
# It carries the planner's stage-selection decisions (run/skip with
# reason), the DAG, the release context, and a byte-reproducible
# fingerprint.
#
# This spec pins the v1 contract: 8 required fields, additionalProperties
# strict, schemaVersion const "v1", context/mode/decision/runner_class as
# typed enums, release.version as semver-like pattern.
#
# Mirror pattern: stages_contract_spec.sh (sibling in this directory).

Describe "schemas/plan/v1/plan.schema.json"
  PLAN_V1_SCHEMA="${BRIK_HOME}/schemas/plan/v1/plan.schema.json"
  SAMPLES_DIR="${BRIK_HOME}/spec/contracts/samples"

  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  validate_sample() {
    local payload_file="$1"
    jv "$PLAN_V1_SCHEMA" "$payload_file" >/dev/null 2>&1
  }

  Describe "schema file"
    It "exists at the expected path"
      When call test -f "$PLAN_V1_SCHEMA"
      The status should be success
    End

    It "is valid JSON"
      When call jq -e . "$PLAN_V1_SCHEMA"
      The status should be success
      The output should not be blank
    End

    It "declares draft 2020-12"
      check_draft() { jq -r '."$schema"' "$PLAN_V1_SCHEMA"; }
      When call check_draft
      The output should equal "https://json-schema.org/draft/2020-12/schema"
      The status should be success
    End

    It "has additionalProperties: false at top-level (strict v1 contract)"
      check_strict() { jq -r '.additionalProperties' "$PLAN_V1_SCHEMA"; }
      When call check_strict
      The output should equal "false"
      The status should be success
    End

    It "requires the 8 v1 top-level fields"
      check_required() {
        jq -r '.required | sort | join(",")' "$PLAN_V1_SCHEMA"
      }
      When call check_required
      The output should equal "brikVersion,context,dag,fingerprint,mode,release,schemaVersion,stages"
      The status should be success
    End
  End

  Describe "schemaVersion pinning"
    It "is pinned as const 'v1'"
      check_const() { jq -r '.properties.schemaVersion.const' "$PLAN_V1_SCHEMA"; }
      When call check_const
      The output should equal "v1"
      The status should be success
    End
  End

  Describe "context enum"
    It "lists exactly 'snapshot' and 'release'"
      check_context() {
        jq -r '.properties.context.enum | sort | join(",")' "$PLAN_V1_SCHEMA"
      }
      When call check_context
      The output should equal "release,snapshot"
      The status should be success
    End
  End

  Describe "mode enum"
    It "lists the 3 planner modes (safe, balanced, aggressive)"
      check_mode() {
        jq -r '.properties.mode.enum | sort | join(",")' "$PLAN_V1_SCHEMA"
      }
      When call check_mode
      The output should equal "aggressive,balanced,safe"
      The status should be success
    End
  End

  Describe "stages[].decision enum"
    It "lists exactly 'run' and 'skip'"
      check_decision() {
        jq -r '.properties.stages.items.properties.decision.enum | sort | join(",")' "$PLAN_V1_SCHEMA"
      }
      When call check_decision
      The output should equal "run,skip"
      The status should be success
    End
  End

  Describe "stages[].runner_class enum"
    It "lists the 5 runner classes (base, stack, scanner, analysis, deploy)"
      check_runner() {
        jq -r '.properties.stages.items.properties.runner_class.enum | sort | join(",")' "$PLAN_V1_SCHEMA"
      }
      When call check_runner
      The output should equal "analysis,base,deploy,scanner,stack"
      The status should be success
    End
  End

  Describe "valid samples (extracted from campaign the test campaign)"
    It "accepts plan-snapshot-context.json (branch push, no release, real sample)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/valid/plan-snapshot-context.json"
      The status should be success
    End

    It "accepts plan-release-context.json (tag push, release+deploy, real sample)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/valid/plan-release-context.json"
      The status should be success
    End
  End

  Describe "invalid samples (synthetic, contract violations)"
    It "rejects plan-01-wrong-schema-version.json (schemaVersion='v2' violates const)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/invalid/plan-01-wrong-schema-version.json"
      The status should not equal 0
    End

    It "rejects plan-02-unknown-context.json (context='hotfix' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/invalid/plan-02-unknown-context.json"
      The status should not equal 0
    End

    It "rejects plan-03-unknown-mode.json (mode='yolo' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/invalid/plan-03-unknown-mode.json"
      The status should not equal 0
    End

    It "rejects plan-04-missing-fingerprint.json (required field absent)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/invalid/plan-04-missing-fingerprint.json"
      The status should not equal 0
    End

    It "rejects plan-05-extra-top-level-property.json (additionalProperties: false enforced)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/invalid/plan-05-extra-top-level-property.json"
      The status should not equal 0
    End

    It "rejects plan-06-stages-decision-invalid.json (decision='maybe' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/invalid/plan-06-stages-decision-invalid.json"
      The status should not equal 0
    End

    It "rejects plan-07-stages-runner-class-invalid.json (runner_class='exotic-runner' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/invalid/plan-07-stages-runner-class-invalid.json"
      The status should not equal 0
    End

    It "rejects plan-08-release-version-not-semver.json (release.version does not match semver pattern)"
      Skip if "jv not installed" jv_missing
      When call validate_sample "${SAMPLES_DIR}/invalid/plan-08-release-version-not-semver.json"
      The status should not equal 0
    End
  End

  Describe "campaign-wide validation (regression guard)"
    # Mirror block from stages_contract_spec.sh: validate the schema against
    # all 7 plan.json files captured during the test campaign
    # campaign. A future contract update (v1 -> v2) that breaks any sample
    # will surface here, forcing an explicit decision.

    campaign_dir() {
      local d="${BRIK_HOME}/../docs/chantiers/e2e-cross-platform-v0.6.0/logs"
      [[ -d "$d" ]] && cd "$d" 2>/dev/null && pwd
    }

    campaign_missing() {
      local d
      d="$(campaign_dir)"
      [[ -z "$d" ]]
    }

    validate_all_campaign_plans() {
      local d
      d="$(campaign_dir)"
      [[ -z "$d" ]] && return 1
      local fail=0
      while IFS= read -r -d '' f; do
        if ! jv "$PLAN_V1_SCHEMA" "$f" >/dev/null 2>&1; then
          fail=$((fail + 1))
          printf 'FAIL: %s\n' "$f" >&2
        fi
      done < <(find "$d" -name "plan.json" -path "*/.brik-logs/*" -print0 2>/dev/null)
      return "$fail"
    }

    It "all 7 campaign plan.json files validate against v1"
      Skip if "jv not installed" jv_missing
      Skip if "campaign workspace not available" campaign_missing
      When call validate_all_campaign_plans
      The status should be success
    End
  End
End

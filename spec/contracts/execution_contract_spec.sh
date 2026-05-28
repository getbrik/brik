#shellcheck shell=bash
# Validation contracts for the execution notion (lib/pipeline/).
#
# Two outputs of the execution notion are pinned here:
#
#   1) .brik-logs/pipeline.env (dotenv key=value file)
#      schema: schemas/execution/v1/pipeline-env.schema.json (NEW v1)
#      consumer: every downstream stage via GitLab dotenv / Jenkins stash /
#      local sourcing
#
#   2) .brik-logs/aggregate-report.json
#      schema: schemas/report/v1.1/aggregate.schema.json (REUSED from design plan
#      20260510_tech-business-orthogonal-axes -- the v1.1 ontology covers
#      tech.kind + business.{status, reason} typed)
#      producer: notify stage (lib/pipeline/report.sh)
#
# Two real production bugs of the current release are documented at the bottom (campaign-
# wide regression block, currently Pending). They were detected during this
# the test architecture task and tracked as follow-up.
#
# Mirror pattern: stages_contract_spec.sh + planning_contract_spec.sh +
# registry_contract_spec.sh.

Describe "execution notion contracts (pipeline-env v1 + report aggregate v1.1)"
  PIPELINE_ENV_V1_SCHEMA="${BRIK_HOME}/schemas/execution/v1/pipeline-env.schema.json"
  AGGREGATE_V11_SCHEMA="${BRIK_HOME}/schemas/report/v1.1/aggregate.schema.json"
  SAMPLES_DIR="${BRIK_HOME}/spec/contracts/samples"
  SCHEMA_MAP="https://brik.dev/schemas/=${BRIK_HOME}/schemas/"

  jv_missing() { ! command -v jv >/dev/null 2>&1; }
  jq_missing() { ! command -v jq >/dev/null 2>&1; }
  awk_missing() { ! command -v awk >/dev/null 2>&1; }
  tools_missing() { jv_missing || jq_missing; }

  # Validates a JSON file against the pipeline-env v1 schema.
  validate_pipeline_env_json() {
    jv "$PIPELINE_ENV_V1_SCHEMA" "$1" >/dev/null 2>&1
  }

  # Converts a dotenv file (KEY=VALUE per line) to a JSON object and pipes
  # it through jv to validate against the pipeline-env v1 schema.
  validate_pipeline_env_file() {
    local env_file="$1"
    awk -F= '
    BEGIN { print "{" }
    /^[A-Z_]+=/ {
        if (n++ > 0) print ","
        key = $1
        sub(/^[^=]*=/, "", $0)
        val = $0
        gsub(/\\/, "\\\\", val)
        gsub(/"/, "\\\"", val)
        printf "\"%s\":\"%s\"", key, val
    }
    END { print "\n}" }
    ' "$env_file" | jv "$PIPELINE_ENV_V1_SCHEMA" /dev/stdin >/dev/null 2>&1
  }

  # Validates a JSON file against the aggregate-report v1.1 schema, with
  # the --map flag so jv resolves $ref to fragment.schema.json locally
  # instead of trying to fetch https://brik.dev/schemas/... over the web.
  validate_aggregate_v11() {
    jv --map "$SCHEMA_MAP" "$AGGREGATE_V11_SCHEMA" "$1" >/dev/null 2>&1
  }

  Describe "schema files"
    It "pipeline-env.schema.json exists at the expected path"
      When call test -f "$PIPELINE_ENV_V1_SCHEMA"
      The status should be success
    End

    It "aggregate.schema.json (report v1.1) exists at the expected path"
      When call test -f "$AGGREGATE_V11_SCHEMA"
      The status should be success
    End

    It "pipeline-env.schema.json is valid JSON"
      When call jq -e . "$PIPELINE_ENV_V1_SCHEMA"
      The status should be success
      The output should not be blank
    End

    It "aggregate.schema.json (report v1.1) is valid JSON"
      When call jq -e . "$AGGREGATE_V11_SCHEMA"
      The status should be success
      The output should not be blank
    End

    It "pipeline-env.schema.json declares draft 2020-12"
      check_draft() { jq -r '."$schema"' "$PIPELINE_ENV_V1_SCHEMA"; }
      When call check_draft
      The output should equal "https://json-schema.org/draft/2020-12/schema"
      The status should be success
    End

    It "aggregate v1.1 declares draft 2020-12"
      check_draft() { jq -r '."$schema"' "$AGGREGATE_V11_SCHEMA"; }
      When call check_draft
      The output should equal "https://json-schema.org/draft/2020-12/schema"
      The status should be success
    End
  End

  Describe "pipeline-env v1 contract pinning"
    It "has additionalProperties: false (no rogue BRIK_* keys past v1)"
      check_strict() { jq -r '.additionalProperties' "$PIPELINE_ENV_V1_SCHEMA"; }
      When call check_strict
      The output should equal "false"
      The status should be success
    End

    It "requires exactly the 20 v1 keys observed on the test campaign"
      check_required_count() { jq -r '.required | length' "$PIPELINE_ENV_V1_SCHEMA"; }
      When call check_required_count
      The output should equal "20"
      The status should be success
    End

    It "BRIK_BUILD_STACK enum lists the 6 builtin stacks"
      check_stack_enum() {
        jq -r '.properties.BRIK_BUILD_STACK.enum | sort | join(",")' "$PIPELINE_ENV_V1_SCHEMA"
      }
      When call check_stack_enum
      The output should equal "docker,dotnet,java,node,python,rust"
      The status should be success
    End

    It "BRIK_RELEASE_PROFILE enum mirrors the planning release.profile enum"
      check_profile_enum() {
        jq -r '.properties.BRIK_RELEASE_PROFILE.enum | sort | join(",")' "$PIPELINE_ENV_V1_SCHEMA"
      }
      When call check_profile_enum
      The output should equal "git-flow,github-flow,none,trunk-based"
      The status should be success
    End
  End

  Describe "aggregate-report v1.1 contract pinning"
    It "pins schema_version as const '1.1'"
      check_const() { jq -r '.properties.schema_version.const' "$AGGREGATE_V11_SCHEMA"; }
      When call check_const
      The output should equal "1.1"
      The status should be success
    End

    It "has additionalProperties: false at top-level"
      check_strict() { jq -r '.additionalProperties' "$AGGREGATE_V11_SCHEMA"; }
      When call check_strict
      The output should equal "false"
      The status should be success
    End

    It "requires the 4 top-level fields (schema_version, pipeline, stages, summary)"
      check_required() {
        jq -r '.required | sort | join(",")' "$AGGREGATE_V11_SCHEMA"
      }
      When call check_required
      The output should equal "pipeline,schema_version,stages,summary"
      The status should be success
    End
  End

  Describe "pipeline-env: valid samples (converted from campaign the test campaign)"
    It "accepts pipeline-env-deploy.json (deploy context, BRIK_DEPLOY_ENABLED=true, real sample)"
      Skip if "jv not installed" jv_missing
      When call validate_pipeline_env_json "${SAMPLES_DIR}/valid/pipeline-env-deploy.json"
      The status should be success
    End

    It "accepts pipeline-env-snapshot.json (branch push, BRIK_IS_CANDIDATE=0, real sample)"
      Skip if "jv not installed" jv_missing
      When call validate_pipeline_env_json "${SAMPLES_DIR}/valid/pipeline-env-snapshot.json"
      The status should be success
    End
  End

  Describe "pipeline-env: invalid samples (synthetic, contract violations)"
    It "rejects pipeline-env-01-stack-unknown.json (BRIK_BUILD_STACK='elixir' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_pipeline_env_json "${SAMPLES_DIR}/invalid/pipeline-env-01-stack-unknown.json"
      The status should not equal 0
    End

    It "rejects pipeline-env-02-profile-unknown.json (BRIK_RELEASE_PROFILE='weird-flow' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_pipeline_env_json "${SAMPLES_DIR}/invalid/pipeline-env-02-profile-unknown.json"
      The status should not equal 0
    End

    It "rejects pipeline-env-03-is-candidate-bool-text.json (BRIK_IS_CANDIDATE='yes' must be '0' or '1')"
      Skip if "jv not installed" jv_missing
      When call validate_pipeline_env_json "${SAMPLES_DIR}/invalid/pipeline-env-03-is-candidate-bool-text.json"
      The status should not equal 0
    End

    It "rejects pipeline-env-04-enabled-numeric.json (BRIK_PACKAGE_ENABLED='1' must be 'true' or 'false')"
      Skip if "jv not installed" jv_missing
      When call validate_pipeline_env_json "${SAMPLES_DIR}/invalid/pipeline-env-04-enabled-numeric.json"
      The status should not equal 0
    End

    It "rejects pipeline-env-05-missing-ci-image.json (BRIK_CI_IMAGE required)"
      Skip if "jv not installed" jv_missing
      When call validate_pipeline_env_json "${SAMPLES_DIR}/invalid/pipeline-env-05-missing-ci-image.json"
      The status should not equal 0
    End

    It "rejects pipeline-env-06-extra-key.json (additionalProperties: false enforced -- no BRIK_UNKNOWN_VAR in v1)"
      Skip if "jv not installed" jv_missing
      When call validate_pipeline_env_json "${SAMPLES_DIR}/invalid/pipeline-env-06-extra-key.json"
      The status should not equal 0
    End

    It "rejects pipeline-env-07-version-not-semver.json (BRIK_PROJECT_VERSION='v0.1' does not match semver)"
      Skip if "jv not installed" jv_missing
      When call validate_pipeline_env_json "${SAMPLES_DIR}/invalid/pipeline-env-07-version-not-semver.json"
      The status should not equal 0
    End

    It "rejects pipeline-env-08-image-bad-format.json (BRIK_CI_IMAGE='just-a-string' does not match registry/name:tag)"
      Skip if "jv not installed" jv_missing
      When call validate_pipeline_env_json "${SAMPLES_DIR}/invalid/pipeline-env-08-image-bad-format.json"
      The status should not equal 0
    End
  End

  Describe "aggregate-report v1.1: valid sample (minimal, derived from clean campaign data)"
    It "accepts aggregate-report-minimal.json (1 stage, no env field, tech.kind absent on success)"
      Skip if "jv not installed" jv_missing
      When call validate_aggregate_v11 "${SAMPLES_DIR}/valid/aggregate-report-minimal.json"
      The status should be success
    End
  End

  Describe "aggregate-report v1.1: invalid samples (synthetic, contract violations)"
    It "rejects aggregate-01-wrong-schema-version.json (schema_version='2.0' violates const)"
      Skip if "jv not installed" jv_missing
      When call validate_aggregate_v11 "${SAMPLES_DIR}/invalid/aggregate-01-wrong-schema-version.json"
      The status should not equal 0
    End

    It "rejects aggregate-02-missing-pipeline.json (pipeline required)"
      Skip if "jv not installed" jv_missing
      When call validate_aggregate_v11 "${SAMPLES_DIR}/invalid/aggregate-02-missing-pipeline.json"
      The status should not equal 0
    End

    It "rejects aggregate-03-missing-stages.json (stages required)"
      Skip if "jv not installed" jv_missing
      When call validate_aggregate_v11 "${SAMPLES_DIR}/invalid/aggregate-03-missing-stages.json"
      The status should not equal 0
    End

    It "rejects aggregate-04-missing-summary.json (summary required)"
      Skip if "jv not installed" jv_missing
      When call validate_aggregate_v11 "${SAMPLES_DIR}/invalid/aggregate-04-missing-summary.json"
      The status should not equal 0
    End

    It "rejects aggregate-05-extra-top-property.json (additionalProperties: false at top)"
      Skip if "jv not installed" jv_missing
      When call validate_aggregate_v11 "${SAMPLES_DIR}/invalid/aggregate-05-extra-top-property.json"
      The status should not equal 0
    End

    It "rejects aggregate-06-pipeline-platform-invalid.json (pipeline.platform='exotic-platform' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_aggregate_v11 "${SAMPLES_DIR}/invalid/aggregate-06-pipeline-platform-invalid.json"
      The status should not equal 0
    End

    It "rejects aggregate-07-fragment-tech-kind-invalid.json (stages[0].tech.kind='wormhole' outside enum)"
      # Reproduces the v0.6.0 production bug detected during S1: notify stage
      # writes tech.kind='in-flight' which is outside the 12-value enum.
      # Follow-up: see follow-up task created next to .
      Skip if "jv not installed" jv_missing
      When call validate_aggregate_v11 "${SAMPLES_DIR}/invalid/aggregate-07-fragment-tech-kind-invalid.json"
      The status should not equal 0
    End

    It "rejects aggregate-08-fragment-extra-env-field.json (stages[0].env not allowed by additionalProperties: false)"
      # Reproduces the v0.6.0 production bug detected during S1: init stage
      # serializes the full pipeline.env into stages[].env, which the
      # fragment v1.1 schema rejects as an additional property.
      # Follow-up: see follow-up task created next to .
      Skip if "jv not installed" jv_missing
      When call validate_aggregate_v11 "${SAMPLES_DIR}/invalid/aggregate-08-fragment-extra-env-field.json"
      The status should not equal 0
    End
  End

  Describe "pipeline-env: campaign-wide validation (regression guard)"
    # Validate the schema against all 7 pipeline.env files captured during
    # the test campaign. Conversion env -> JSON happens
    # on the fly via awk; no pre-staged JSON snapshots needed.

    campaign_dir() {
      local d="${BRIK_HOME}/../docs/chantiers/e2e-cross-platform-v0.6.0/logs"
      [[ -d "$d" ]] && cd "$d" 2>/dev/null && pwd
    }

    campaign_missing() {
      local d
      d="$(campaign_dir)"
      [[ -z "$d" ]]
    }

    validate_all_campaign_pipeline_envs() {
      local d
      d="$(campaign_dir)"
      [[ -z "$d" ]] && return 1
      local fail=0
      while IFS= read -r -d '' f; do
        if ! validate_pipeline_env_file "$f"; then
          fail=$((fail + 1))
          printf 'FAIL: %s\n' "$f" >&2
        fi
      done < <(find "$d" -name "pipeline.env" -path "*/.brik-logs/*" -print0 2>/dev/null)
      return "$fail"
    }

    It "all 7 campaign pipeline.env files validate against v1"
      Skip if "jv or awk not installed" tools_missing
      Skip if "awk not installed" awk_missing
      Skip if "campaign workspace not available" campaign_missing
      When call validate_all_campaign_pipeline_envs
      The status should be success
    End
  End

  Describe "aggregate-report v1.1: campaign-wide validation (KNOWN BUGS, pending fix)"
    # The 7 aggregate-report.json files produced by the current release declare
    # schema_version='1.1' but FAIL validation against the v1.1 schema due
    # to two real bugs in the producer (lib/pipeline/report.sh and friends):
    #
    #   Bug A: stages[init].env serialises the full pipeline.env as an
    #          object inside the stage fragment. The v1.1 fragment schema
    #          declares additionalProperties: false -- env is rejected.
    #          Detected on every campaign sample (7/7).
    #
    #   Bug B: stages[notify].tech.kind = "in-flight". The fragment v1.1
    #          schema enumerates 12 valid kinds (ok, failure, invalid-input,
    #          missing-dependency, invalid-environment,
    #          external-service-unavailable, io-failure,
    #          configuration-error, timeout, interrupted, check-failed,
    #          not-applicable). "in-flight" is not among them.
    #          Detected on every campaign sample (7/7).
    #
    # Pending until both bugs are fixed. The test is intentionally NOT
    # marked Skip -- it stays Pending so the fix shows up as a flip from
    # Pending to Pass in CI history.

    Pending "v0.6.0 producer emits stages[init].env (bug A) and stages[notify].tech.kind='in-flight' (bug B), incompatible with schema v1.1 -- see follow-up tasks tracked next to "
  End
End

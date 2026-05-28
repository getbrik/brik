#shellcheck shell=bash
# Validation contract for the v1 stack notion: per-stack build/test outputs +
# project.stack enum pinning.
#
# (lib/stacks/).
# The stack notion exposes 6 builtin stacks (node, python, java, rust, dotnet,
# docker) via 3 canonical functions per stack: install_deps, build, test.
# Two contracts apply at the L0 boundary:
#
#   1) project.stack ENUM in brik.yml schema
#      schema: schemas/config/v1/brik.schema.json
#      Pins the 5 user-facing stacks (docker is an infra-only stack, not
#      a project stack).
#
#   2) per-stage business artifact (brik-artifacts/<stage>/<stage>.json)
#      schema: schemas/report/v1.1/fragment.schema.json (REUSED)
#      Each stack's build / test produces a v1.1 fragment artifact under
#      brik-artifacts/, validated by the same fragment schema as the
#      stages[] entries of aggregate-report.json.
#
# Companion legacy specs:
#   - spec/_legacy/stacks/*_spec.sh test the BEHAVIOURAL contract of each
#     stacks.<id>.{install_deps,build,test} function (L1).
#   - spec/_legacy/registry/contract/stack_contract_spec.sh tests
#     the registry.stack.* API contract (L1/L2).
#
# This spec pins the orthogonal axis: STATIC OUTPUT contract of the
# per-stack fragments + brik.yml stack section (L0).
#
# Mirror pattern: stages_contract_spec.sh + planning_contract_spec.sh +
# registry_contract_spec.sh + execution_contract_spec.sh +
# findings_contract_spec.sh + rollout_contract_spec.sh +
# execution_environment_contract_spec.sh.

Describe "stack notion contracts (fragment v1.1 reuse + brik.yml stack enum)"
  FRAGMENT_V11_SCHEMA="${BRIK_HOME}/schemas/report/v1.1/fragment.schema.json"
  BRIK_YML_V1_SCHEMA="${BRIK_HOME}/schemas/config/v1/brik.schema.json"
  SAMPLES_DIR="${BRIK_HOME}/spec/contracts/samples"
  SCHEMA_MAP="https://brik.dev/schemas/=${BRIK_HOME}/schemas/"

  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  validate_fragment_v11() {
    jv --map "$SCHEMA_MAP" "$FRAGMENT_V11_SCHEMA" "$1" >/dev/null 2>&1
  }

  Describe "schema files"
    It "fragment v1.1 schema exists at the expected path"
      When call test -f "$FRAGMENT_V11_SCHEMA"
      The status should be success
    End

    It "brik.yml v1 schema (config) exists at the expected path"
      When call test -f "$BRIK_YML_V1_SCHEMA"
      The status should be success
    End

    It "fragment v1.1 is valid JSON"
      When call jq -e . "$FRAGMENT_V11_SCHEMA"
      The status should be success
      The output should not be blank
    End

    It "brik.yml v1 (config) is valid JSON"
      When call jq -e . "$BRIK_YML_V1_SCHEMA"
      The status should be success
      The output should not be blank
    End
  End

  Describe "brik.yml project.stack enum (v1 user-facing stacks)"
    It "lists exactly the 5 user-facing stacks (docker is infra-only, not project.stack)"
      check_stack_enum() {
        jq -r '.properties.project.properties.stack.enum | sort | join(",")' "$BRIK_YML_V1_SCHEMA"
      }
      When call check_stack_enum
      The output should equal "dotnet,java,node,python,rust"
      The status should be success
    End

    It "marks project.stack as optional (auto-detection from project files)"
      check_optional() {
        # project.stack must NOT be in the required list of project block
        jq -r '.properties.project.required | any(. == "stack")' "$BRIK_YML_V1_SCHEMA"
      }
      When call check_optional
      The output should equal "false"
      The status should be success
    End
  End

  Describe "per-stack output fragment v1.1 (valid samples, real campaign data)"
    It "accepts stack-build-fragment.json (build stage output, node stack, real sample)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/valid/stack-build-fragment.json"
      The status should be success
    End

    It "accepts stack-test-fragment.json (test stage output, real sample)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/valid/stack-test-fragment.json"
      The status should be success
    End
  End

  Describe "per-stack output fragment v1.1 (invalid synthetic, contract violations)"
    It "rejects stack-fragment-01-rc-negative.json (rc minimum: 0)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/invalid/stack-fragment-01-rc-negative.json"
      The status should not equal 0
    End

    It "rejects stack-fragment-02-status-out-of-enum.json (status='maybe' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/invalid/stack-fragment-02-status-out-of-enum.json"
      The status should not equal 0
    End

    It "rejects stack-fragment-03-missing-rc.json (rc required)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/invalid/stack-fragment-03-missing-rc.json"
      The status should not equal 0
    End

    It "rejects stack-fragment-04-business-status-out-of-enum.json (business.status='yolo' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/invalid/stack-fragment-04-business-status-out-of-enum.json"
      The status should not equal 0
    End

    It "rejects stack-fragment-05-tech-warning-banned.json (tech.warning explicitly banned in v1.1)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/invalid/stack-fragment-05-tech-warning-banned.json"
      The status should not equal 0
    End
  End

  Describe "campaign-wide validation (regression guard)"
    # Validate fragment v1.1 against ALL per-stack outputs captured during
    # the test campaign (7 build.json + 13 test.json).
    # These are the per-stage business artifacts under brik-artifacts/.

    campaign_dir() {
      local d="${BRIK_HOME}/../docs/chantiers/e2e-cross-platform-v0.6.0/logs"
      [[ -d "$d" ]] && cd "$d" 2>/dev/null && pwd
    }

    campaign_missing() {
      local d
      d="$(campaign_dir)"
      [[ -z "$d" ]]
    }

    validate_all_campaign_build_fragments() {
      local d
      d="$(campaign_dir)"
      [[ -z "$d" ]] && return 1
      local fail=0
      while IFS= read -r -d '' f; do
        if ! jv --map "$SCHEMA_MAP" "$FRAGMENT_V11_SCHEMA" "$f" >/dev/null 2>&1; then
          fail=$((fail + 1))
          printf 'FAIL build fragment: %s\n' "$f" >&2
        fi
      done < <(find "$d" -name "build.json" -path "*/brik-artifacts/build/*" -print0 2>/dev/null)
      return "$fail"
    }

    validate_all_campaign_test_fragments() {
      local d
      d="$(campaign_dir)"
      [[ -z "$d" ]] && return 1
      local fail=0
      while IFS= read -r -d '' f; do
        if ! jv --map "$SCHEMA_MAP" "$FRAGMENT_V11_SCHEMA" "$f" >/dev/null 2>&1; then
          fail=$((fail + 1))
          printf 'FAIL test fragment: %s\n' "$f" >&2
        fi
      done < <(find "$d" -name "test.json" -path "*/brik-artifacts/test/*" -print0 2>/dev/null)
      return "$fail"
    }

    It "all 7 campaign build.json fragments validate against v1.1"
      Skip if "jv not installed" jv_missing
      Skip if "campaign workspace not available" campaign_missing
      When call validate_all_campaign_build_fragments
      The status should be success
    End

    It "all 13 campaign test.json fragments validate against v1.1"
      Skip if "jv not installed" jv_missing
      Skip if "campaign workspace not available" campaign_missing
      When call validate_all_campaign_test_fragments
      The status should be success
    End
  End
End

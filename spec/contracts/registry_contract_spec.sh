#shellcheck shell=bash
# Validation contract for the v1 registry manifest schemas (stage + stack).
#
# The registry notion owns the manifests under lib/registry/manifests/:
#   - stages/<stage>.yml : 12 builtin stage manifests
#   - stacks/<stack>.yml : 6 builtin stack manifests
#
# Two v1 schemas are bundled (pre-existing):
#   - schemas/registry/v1/stage.schema.json
#   - schemas/registry/v1/stack.schema.json
#
# This spec pins the input contracts: apiVersion const "brik.dev/v1",
# kind const "Stage" / "Stack", required metadata/spec blocks, typed
# enums for runner.class and gate.mode.
#
# Manifests are YAML; samples stay in their native YAML form and are
# converted on the fly via `yq -o=json` before validation with `jv`.
#
# Companion legacy spec spec/_legacy/registry/contract/stage_contract_spec.sh
# tests the BEHAVIOURAL contract of registry.stage.* API (L1/L2). The
# present spec covers the orthogonal axis: STATIC INPUT contract of the
# manifest YAML format (L0).
#
# Mirror pattern: stages_contract_spec.sh + planning_contract_spec.sh
# (sibling files in this directory).

Describe "schemas/registry/v1/{stage,stack}.schema.json"
  STAGE_V1_SCHEMA="${BRIK_HOME}/schemas/registry/v1/stage.schema.json"
  STACK_V1_SCHEMA="${BRIK_HOME}/schemas/registry/v1/stack.schema.json"
  SAMPLES_DIR="${BRIK_HOME}/spec/contracts/samples"

  jv_missing() { ! command -v jv >/dev/null 2>&1; }
  yq_missing() { ! command -v yq >/dev/null 2>&1; }
  tools_missing() { jv_missing || yq_missing; }

  validate_yaml_sample() {
    local schema="$1" yaml_file="$2"
    yq -o=json . "$yaml_file" 2>/dev/null | jv "$schema" /dev/stdin >/dev/null 2>&1
  }

  Describe "schema files"
    It "stage.schema.json exists at the expected path"
      When call test -f "$STAGE_V1_SCHEMA"
      The status should be success
    End

    It "stack.schema.json exists at the expected path"
      When call test -f "$STACK_V1_SCHEMA"
      The status should be success
    End

    It "stage.schema.json is valid JSON"
      When call jq -e . "$STAGE_V1_SCHEMA"
      The status should be success
      The output should not be blank
    End

    It "stack.schema.json is valid JSON"
      When call jq -e . "$STACK_V1_SCHEMA"
      The status should be success
      The output should not be blank
    End

    It "both schemas declare draft 2020-12"
      check_drafts() {
        local s1 s2
        s1="$(jq -r '."$schema"' "$STAGE_V1_SCHEMA")"
        s2="$(jq -r '."$schema"' "$STACK_V1_SCHEMA")"
        [[ "$s1" == "$s2" ]] || return 1
        [[ "$s1" == "https://json-schema.org/draft/2020-12/schema" ]] || return 1
      }
      When call check_drafts
      The status should be success
    End

    It "both schemas top-level additionalProperties: false"
      check_strict() {
        local s1 s2
        s1="$(jq -r '.additionalProperties' "$STAGE_V1_SCHEMA")"
        s2="$(jq -r '.additionalProperties' "$STACK_V1_SCHEMA")"
        [[ "$s1" == "false" && "$s2" == "false" ]]
      }
      When call check_strict
      The status should be success
    End

    It "both schemas require the same 4 top-level fields (apiVersion, kind, metadata, spec)"
      check_required() {
        local r1 r2
        r1="$(jq -r '.required | sort | join(",")' "$STAGE_V1_SCHEMA")"
        r2="$(jq -r '.required | sort | join(",")' "$STACK_V1_SCHEMA")"
        [[ "$r1" == "$r2" ]] || return 1
        [[ "$r1" == "apiVersion,kind,metadata,spec" ]] || return 1
      }
      When call check_required
      The status should be success
    End
  End

  Describe "apiVersion pinning"
    It "stage.schema.json pins apiVersion as const 'brik.dev/v1'"
      check_const() { jq -r '.properties.apiVersion.const' "$STAGE_V1_SCHEMA"; }
      When call check_const
      The output should equal "brik.dev/v1"
      The status should be success
    End

    It "stack.schema.json pins apiVersion as const 'brik.dev/v1'"
      check_const() { jq -r '.properties.apiVersion.const' "$STACK_V1_SCHEMA"; }
      When call check_const
      The output should equal "brik.dev/v1"
      The status should be success
    End
  End

  Describe "kind discrimination"
    It "stage.schema.json pins kind as const 'Stage'"
      check_const() { jq -r '.properties.kind.const' "$STAGE_V1_SCHEMA"; }
      When call check_const
      The output should equal "Stage"
      The status should be success
    End

    It "stack.schema.json pins kind as const 'Stack'"
      check_const() { jq -r '.properties.kind.const' "$STACK_V1_SCHEMA"; }
      When call check_const
      The output should equal "Stack"
      The status should be success
    End
  End

  Describe "stage spec.runner.class enum"
    It "lists the 5 runner classes (base, stack, scanner, analysis, deploy)"
      check_runner() {
        jq -r '.properties.spec.properties.runner.properties.class.enum | sort | join(",")' "$STAGE_V1_SCHEMA"
      }
      When call check_runner
      The output should equal "analysis,base,deploy,scanner,stack"
      The status should be success
    End
  End

  Describe "stage spec.gate.mode enum"
    It "lists exactly 'blocking' and 'opt_in'"
      check_gate() {
        jq -r '.properties.spec.properties.gate.properties.mode.enum | sort | join(",")' "$STAGE_V1_SCHEMA"
      }
      When call check_gate
      The output should equal "blocking,opt_in"
      The status should be success
    End
  End

  Describe "valid samples (extracted from lib/registry/manifests/ builtins)"
    It "accepts registry-stage-init.yml (blocking gate, base runner)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "$STAGE_V1_SCHEMA" "${SAMPLES_DIR}/valid/registry-stage-init.yml"
      The status should be success
    End

    It "accepts registry-stage-deploy.yml (opt_in gate)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "$STAGE_V1_SCHEMA" "${SAMPLES_DIR}/valid/registry-stage-deploy.yml"
      The status should be success
    End

    It "accepts registry-stack-node.yml (Node.js stack with markers + runner)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "$STACK_V1_SCHEMA" "${SAMPLES_DIR}/valid/registry-stack-node.yml"
      The status should be success
    End

    It "accepts registry-stack-rust.yml (Rust stack)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "$STACK_V1_SCHEMA" "${SAMPLES_DIR}/valid/registry-stack-rust.yml"
      The status should be success
    End
  End

  Describe "invalid samples -- stage manifest violations (synthetic)"
    It "rejects registry-01-stage-wrong-api-version.yml (apiVersion='brik.dev/v2' violates const)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "$STAGE_V1_SCHEMA" "${SAMPLES_DIR}/invalid/registry-01-stage-wrong-api-version.yml"
      The status should not equal 0
    End

    It "rejects registry-02-stage-wrong-kind.yml (kind='Workflow' violates const 'Stage')"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "$STAGE_V1_SCHEMA" "${SAMPLES_DIR}/invalid/registry-02-stage-wrong-kind.yml"
      The status should not equal 0
    End

    It "rejects registry-03-stage-missing-display.yml (metadata.displayName required)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "$STAGE_V1_SCHEMA" "${SAMPLES_DIR}/invalid/registry-03-stage-missing-display.yml"
      The status should not equal 0
    End

    It "rejects registry-04-stage-runner-class-invalid.yml (runner.class='exotic-runner' outside enum)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "$STAGE_V1_SCHEMA" "${SAMPLES_DIR}/invalid/registry-04-stage-runner-class-invalid.yml"
      The status should not equal 0
    End

    It "rejects registry-05-stage-gate-mode-invalid.yml (gate.mode='optional' outside enum)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "$STAGE_V1_SCHEMA" "${SAMPLES_DIR}/invalid/registry-05-stage-gate-mode-invalid.yml"
      The status should not equal 0
    End

    It "rejects registry-06-stage-extra-spec-property.yml (additionalProperties: false in spec)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "$STAGE_V1_SCHEMA" "${SAMPLES_DIR}/invalid/registry-06-stage-extra-spec-property.yml"
      The status should not equal 0
    End
  End

  Describe "invalid samples -- stack manifest violations (synthetic)"
    It "rejects registry-07-stack-missing-detect.yml (spec.detect required for stacks)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "$STACK_V1_SCHEMA" "${SAMPLES_DIR}/invalid/registry-07-stack-missing-detect.yml"
      The status should not equal 0
    End

    It "rejects registry-08-stack-runner-missing-default-version.yml (runner.defaultVersion required)"
      Skip if "jv or yq not installed" tools_missing
      When call validate_yaml_sample "$STACK_V1_SCHEMA" "${SAMPLES_DIR}/invalid/registry-08-stack-runner-missing-default-version.yml"
      The status should not equal 0
    End
  End

  Describe "registry-wide validation (regression guard)"
    # Mirror block from stages_contract_spec.sh + planning_contract_spec.sh:
    # validate the schemas against ALL builtin manifests
    # (12 stages + 6 stacks). A future contract update that breaks any
    # builtin manifest will surface here, forcing an explicit decision.

    validate_all_builtin_stages() {
      local fail=0
      while IFS= read -r -d '' f; do
        if ! yq -o=json . "$f" 2>/dev/null | jv "$STAGE_V1_SCHEMA" /dev/stdin >/dev/null 2>&1; then
          fail=$((fail + 1))
          printf 'FAIL stage: %s\n' "$f" >&2
        fi
      done < <(find "${BRIK_HOME}/lib/registry/manifests/stages" -name "*.yml" -print0 2>/dev/null)
      return "$fail"
    }

    validate_all_builtin_stacks() {
      local fail=0
      while IFS= read -r -d '' f; do
        if ! yq -o=json . "$f" 2>/dev/null | jv "$STACK_V1_SCHEMA" /dev/stdin >/dev/null 2>&1; then
          fail=$((fail + 1))
          printf 'FAIL stack: %s\n' "$f" >&2
        fi
      done < <(find "${BRIK_HOME}/lib/registry/manifests/stacks" -name "*.yml" -print0 2>/dev/null)
      return "$fail"
    }

    It "all 12 builtin stage manifests validate against stage.schema.json"
      Skip if "jv or yq not installed" tools_missing
      When call validate_all_builtin_stages
      The status should be success
    End

    It "all 6 builtin stack manifests validate against stack.schema.json"
      Skip if "jv or yq not installed" tools_missing
      When call validate_all_builtin_stacks
      The status should be success
    End
  End
End

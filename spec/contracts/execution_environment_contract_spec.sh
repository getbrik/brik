#shellcheck shell=bash
# Validation contract for the v1 execution-environment notion: wrapper context.
#
# Sprint  of 
# (docs/chantiers/20260528_e2e-tests-par-notion.md), notion:
# execution-environment (shared-libs/).
#
# The execution-environment notion owns the wrappers that map a CI
# orchestrator (GitLab, Jenkins, local shell, GitHub planned) into the
# canonical BRIK_* environment consumed by lib/pipeline/. The wrapper
# is the boundary that decouples brik from any specific CI:
#
#   - shared-libs/common/scripts/base-wrapper.sh  (BRIK_HOME, BRIK_WORKSPACE, ...)
#   - shared-libs/gitlab/scripts/gitlab-wrapper.sh (CI_COMMIT_SHA  -> BRIK_COMMIT_SHA ...)
#   - shared-libs/jenkins/scripts/jenkins-wrapper.sh (GIT_COMMIT   -> BRIK_COMMIT_SHA ...)
#   - shared-libs/local/scripts/local-wrapper.sh (synthesises locally)
#
# This spec pins the v1 cross-platform contract: 14 mandatory BRIK_* keys,
# additionalProperties strict, BRIK_PLATFORM enum (gitlab|jenkins|local|github),
# BRIK_PIPELINE_SOURCE enum (push|merge_request_event|schedule|web|api),
# BRIK_COMMIT_SHA / BRIK_COMMIT_SHORT_SHA pattern-typed.
#
# Companion legacy specs:
#   - shared-libs/{gitlab,jenkins,local,common}/spec/*_wrapper_spec.sh
#     test the BEHAVIOURAL contract of each wrapper (L1/L2). The present
#     spec covers the orthogonal axis: STATIC INPUT/OUTPUT contract of the
#     BRIK_* environment shape (L0).
#
# Mirror pattern: stages_contract_spec.sh + planning_contract_spec.sh +
# registry_contract_spec.sh + execution_contract_spec.sh +
# findings_contract_spec.sh + rollout_contract_spec.sh.

Describe "schemas/execution-environment/v1/wrapper-context.schema.json"
  WRAPPER_CTX_V1_SCHEMA="${BRIK_HOME}/schemas/execution-environment/v1/wrapper-context.schema.json"
  SAMPLES_DIR="${BRIK_HOME}/spec/contracts/samples"

  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  validate_wrapper_context() {
    jv "$WRAPPER_CTX_V1_SCHEMA" "$1" >/dev/null 2>&1
  }

  Describe "schema file"
    It "exists at the expected path"
      When call test -f "$WRAPPER_CTX_V1_SCHEMA"
      The status should be success
    End

    It "is valid JSON"
      When call jq -e . "$WRAPPER_CTX_V1_SCHEMA"
      The status should be success
      The output should not be blank
    End

    It "declares draft 2020-12"
      check_draft() { jq -r '."$schema"' "$WRAPPER_CTX_V1_SCHEMA"; }
      When call check_draft
      The output should equal "https://json-schema.org/draft/2020-12/schema"
      The status should be success
    End

    It "has additionalProperties: false (no rogue BRIK_* keys past v1)"
      check_strict() { jq -r '.additionalProperties' "$WRAPPER_CTX_V1_SCHEMA"; }
      When call check_strict
      The output should equal "false"
      The status should be success
    End
  End

  Describe "v1 contract pinning"
    It "requires exactly the 14 v1 BRIK_* keys"
      check_required_count() {
        jq -r '.required | length' "$WRAPPER_CTX_V1_SCHEMA"
      }
      When call check_required_count
      The output should equal "14"
      The status should be success
    End

    It "BRIK_PLATFORM enum lists the 4 supported orchestrators"
      check_platform_enum() {
        jq -r '.properties.BRIK_PLATFORM.enum | sort | join(",")' "$WRAPPER_CTX_V1_SCHEMA"
      }
      When call check_platform_enum
      The output should equal "github,gitlab,jenkins,local"
      The status should be success
    End

    It "BRIK_PIPELINE_SOURCE enum lists the 5 v1 trigger sources"
      check_pipeline_source_enum() {
        jq -r '.properties.BRIK_PIPELINE_SOURCE.enum | sort | join(",")' "$WRAPPER_CTX_V1_SCHEMA"
      }
      When call check_pipeline_source_enum
      The output should equal "api,merge_request_event,push,schedule,web"
      The status should be success
    End

    It "BRIK_COMMIT_SHA pattern is sha40 (40 hex chars lower-case)"
      check_sha_pattern() {
        jq -r '.properties.BRIK_COMMIT_SHA.pattern' "$WRAPPER_CTX_V1_SCHEMA"
      }
      When call check_sha_pattern
      The output should equal "^[a-f0-9]{40}$"
      The status should be success
    End

    It "BRIK_COMMIT_SHORT_SHA pattern is sha7 (first 7 hex chars)"
      check_short_sha_pattern() {
        jq -r '.properties.BRIK_COMMIT_SHORT_SHA.pattern' "$WRAPPER_CTX_V1_SCHEMA"
      }
      When call check_short_sha_pattern
      The output should equal "^[a-f0-9]{7}$"
      The status should be success
    End
  End

  Describe "valid samples (synthetic, derived from observed v0.6.0 wrapper behavior)"
    It "accepts wrapper-context-gitlab-branch.json (GitLab branch push, BRIK_TAG empty)"
      Skip if "jv not installed" jv_missing
      When call validate_wrapper_context "${SAMPLES_DIR}/valid/wrapper-context-gitlab-branch.json"
      The status should be success
    End

    It "accepts wrapper-context-jenkins-tag.json (Jenkins tag push, BRIK_BRANCH empty)"
      Skip if "jv not installed" jv_missing
      When call validate_wrapper_context "${SAMPLES_DIR}/valid/wrapper-context-jenkins-tag.json"
      The status should be success
    End
  End

  Describe "invalid samples (synthetic, contract violations)"
    It "rejects wrapper-context-01-platform-unknown.json (BRIK_PLATFORM='circleci' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_wrapper_context "${SAMPLES_DIR}/invalid/wrapper-context-01-platform-unknown.json"
      The status should not equal 0
    End

    It "rejects wrapper-context-02-sha-bad-format.json (BRIK_COMMIT_SHA='not-a-sha' violates pattern)"
      Skip if "jv not installed" jv_missing
      When call validate_wrapper_context "${SAMPLES_DIR}/invalid/wrapper-context-02-sha-bad-format.json"
      The status should not equal 0
    End

    It "rejects wrapper-context-03-short-sha-too-short.json (BRIK_COMMIT_SHORT_SHA='12345' must be exactly 7 chars)"
      Skip if "jv not installed" jv_missing
      When call validate_wrapper_context "${SAMPLES_DIR}/invalid/wrapper-context-03-short-sha-too-short.json"
      The status should not equal 0
    End

    It "rejects wrapper-context-04-missing-home.json (BRIK_HOME required)"
      Skip if "jv not installed" jv_missing
      When call validate_wrapper_context "${SAMPLES_DIR}/invalid/wrapper-context-04-missing-home.json"
      The status should not equal 0
    End

    It "rejects wrapper-context-05-extra-key.json (additionalProperties: false enforced -- no BRIK_UNKNOWN in v1)"
      Skip if "jv not installed" jv_missing
      When call validate_wrapper_context "${SAMPLES_DIR}/invalid/wrapper-context-05-extra-key.json"
      The status should not equal 0
    End

    It "rejects wrapper-context-06-pipeline-source-unknown.json (BRIK_PIPELINE_SOURCE='trigger' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_wrapper_context "${SAMPLES_DIR}/invalid/wrapper-context-06-pipeline-source-unknown.json"
      The status should not equal 0
    End

    It "rejects wrapper-context-07-lib-extensions-relative.json (BRIK_LIB_EXTENSIONS must start with absolute path '/')"
      Skip if "jv not installed" jv_missing
      When call validate_wrapper_context "${SAMPLES_DIR}/invalid/wrapper-context-07-lib-extensions-relative.json"
      The status should not equal 0
    End
  End
End

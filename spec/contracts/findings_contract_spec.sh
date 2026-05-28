#shellcheck shell=bash
# Validation contract for the v1 findings notion: SARIF 2.1.0 + brik extensions.
#
# Sprint  of 
# (docs/chantiers/20260528_e2e-tests-par-notion.md), notion: findings
# (lib/transverse/findings*).
#
# The findings notion produces SARIF 2.1.0 documents (aggregate.sarif and
# per-stage *.sarif under brik-artifacts/). Two contracts apply:
#
#   1) SARIF 2.1.0 structural conformance
#      schema: schemas/external/sarif-2.1.0.json (vendored, OASIS standard)
#
#   2) Brik-specific extensions on top of SARIF
#      schema: schemas/findings/v1/brik-extensions.schema.json (NEW v1)
#      Constraints typed enums on properties.brikFixClassification,
#      properties.brikToolBlocking, and suppressions[].properties.brikSource.
#
# A producer SARIF file is considered conformant when it passes BOTH
# schemas. the test campaign: 7/7 aggregate.sarif + 43/43 per-stage *.sarif
# pass SARIF 2.1.0; brik extensions when present pass v1 enums (only
# brikFixClassification='unknown' and brikSource='policy.org.path-allowlist'
# observed in this campaign, but the v1 enums also cover has_fix/no_fix
# and policy.built-in.* paths declared in lib/transverse/findings.sh).
#
# Mirror pattern: stages_contract_spec.sh + planning_contract_spec.sh +
# registry_contract_spec.sh + execution_contract_spec.sh.

Describe "findings notion contracts (SARIF 2.1.0 + brik extensions v1)"
  SARIF_SCHEMA="${BRIK_HOME}/schemas/external/sarif-2.1.0.json"
  BRIK_EXT_SCHEMA="${BRIK_HOME}/schemas/findings/v1/brik-extensions.schema.json"
  SAMPLES_DIR="${BRIK_HOME}/spec/contracts/samples"

  jv_missing() { ! command -v jv >/dev/null 2>&1; }
  jq_missing() { ! command -v jq >/dev/null 2>&1; }
  tools_missing() { jv_missing || jq_missing; }

  validate_sarif_2_1_0() {
    jv "$SARIF_SCHEMA" "$1" >/dev/null 2>&1
  }

  validate_brik_extensions() {
    jv "$BRIK_EXT_SCHEMA" "$1" >/dev/null 2>&1
  }

  Describe "schema files"
    It "SARIF 2.1.0 schema exists at the expected path"
      When call test -f "$SARIF_SCHEMA"
      The status should be success
    End

    It "brik-extensions v1 schema exists at the expected path"
      When call test -f "$BRIK_EXT_SCHEMA"
      The status should be success
    End

    It "SARIF 2.1.0 schema is valid JSON"
      When call jq -e . "$SARIF_SCHEMA"
      The status should be success
      The output should not be blank
    End

    It "brik-extensions v1 schema is valid JSON"
      When call jq -e . "$BRIK_EXT_SCHEMA"
      The status should be success
      The output should not be blank
    End

    It "brik-extensions v1 declares draft 2020-12"
      check_draft() { jq -r '."$schema"' "$BRIK_EXT_SCHEMA"; }
      When call check_draft
      The output should equal "https://json-schema.org/draft/2020-12/schema"
      The status should be success
    End
  End

  Describe "brik-extensions v1 contract pinning"
    It "brikFixClassification enum lists exactly has_fix, no_fix, unknown"
      check_fix_class() {
        jq -r '.properties.runs.items.properties.results.items.properties.properties.properties.brikFixClassification.enum | sort | join(",")' "$BRIK_EXT_SCHEMA"
      }
      When call check_fix_class
      The output should equal "has_fix,no_fix,unknown"
      The status should be success
    End

    It "brikToolBlocking is typed boolean"
      check_tool_blocking() {
        jq -r '.properties.runs.items.properties.results.items.properties.properties.properties.brikToolBlocking.type' "$BRIK_EXT_SCHEMA"
      }
      When call check_tool_blocking
      The output should equal "boolean"
      The status should be success
    End

    It "brikSource accepts tool_native const OR policy.{org,built-in}.<reason> pattern"
      check_brik_source() {
        jq -r '.properties.runs.items.properties.results.items.properties.suppressions.items.properties.properties.properties.brikSource.anyOf | length' "$BRIK_EXT_SCHEMA"
      }
      When call check_brik_source
      The output should equal "2"
      The status should be success
    End
  End

  Describe "valid SARIF sample (extracted from campaign the test campaign)"
    It "findings-aggregate-minimal.sarif passes SARIF 2.1.0 structural validation"
      Skip if "jv not installed" jv_missing
      When call validate_sarif_2_1_0 "${SAMPLES_DIR}/valid/findings-aggregate-minimal.sarif"
      The status should be success
    End

    It "findings-aggregate-minimal.sarif passes brik-extensions v1 validation"
      Skip if "jv not installed" jv_missing
      When call validate_brik_extensions "${SAMPLES_DIR}/valid/findings-aggregate-minimal.sarif"
      The status should be success
    End
  End

  Describe "invalid samples vs brik-extensions v1 (synthetic, contract violations)"
    It "rejects findings-01-fix-class-out-of-enum.sarif (brikFixClassification='maybe' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_brik_extensions "${SAMPLES_DIR}/invalid/findings-01-fix-class-out-of-enum.sarif"
      The status should not equal 0
    End

    It "rejects findings-02-fix-class-wrong-type.sarif (brikFixClassification=42 must be string)"
      Skip if "jv not installed" jv_missing
      When call validate_brik_extensions "${SAMPLES_DIR}/invalid/findings-02-fix-class-wrong-type.sarif"
      The status should not equal 0
    End

    It "rejects findings-03-tool-blocking-not-bool.sarif (brikToolBlocking='yes' must be boolean)"
      Skip if "jv not installed" jv_missing
      When call validate_brik_extensions "${SAMPLES_DIR}/invalid/findings-03-tool-blocking-not-bool.sarif"
      The status should not equal 0
    End

    It "rejects findings-04-brik-source-bad-category.sarif (brikSource='policy.weird.unknown' not in {org, built-in})"
      Skip if "jv not installed" jv_missing
      When call validate_brik_extensions "${SAMPLES_DIR}/invalid/findings-04-brik-source-bad-category.sarif"
      The status should not equal 0
    End

    It "rejects findings-05-brik-source-case.sarif (brikSource='Policy.Org.Allowlist' must be lowercase)"
      Skip if "jv not installed" jv_missing
      When call validate_brik_extensions "${SAMPLES_DIR}/invalid/findings-05-brik-source-case.sarif"
      The status should not equal 0
    End

    It "rejects findings-06-brik-source-empty.sarif (brikSource='' violates non-empty pattern)"
      Skip if "jv not installed" jv_missing
      When call validate_brik_extensions "${SAMPLES_DIR}/invalid/findings-06-brik-source-empty.sarif"
      The status should not equal 0
    End
  End

  Describe "campaign-wide validation (regression guard)"
    # Validate BOTH schemas against ALL SARIF files captured during the
    # the test campaign (7 aggregate.sarif + 43 per-stage
    # *.sarif). A future contract update (v1 -> v2) that breaks any
    # campaign sample will surface here.

    campaign_dir() {
      local d="${BRIK_HOME}/../docs/chantiers/e2e-cross-platform-v0.6.0/logs"
      [[ -d "$d" ]] && cd "$d" 2>/dev/null && pwd
    }

    campaign_missing() {
      local d
      d="$(campaign_dir)"
      [[ -z "$d" ]]
    }

    validate_all_campaign_sarifs_2_1_0() {
      local d
      d="$(campaign_dir)"
      [[ -z "$d" ]] && return 1
      local fail=0
      while IFS= read -r -d '' f; do
        if ! jv "$SARIF_SCHEMA" "$f" >/dev/null 2>&1; then
          fail=$((fail + 1))
          printf 'FAIL SARIF 2.1.0: %s\n' "$f" >&2
        fi
      done < <(find "$d" -name "*.sarif" -print0 2>/dev/null)
      return "$fail"
    }

    validate_all_campaign_sarifs_brik_extensions() {
      local d
      d="$(campaign_dir)"
      [[ -z "$d" ]] && return 1
      local fail=0
      while IFS= read -r -d '' f; do
        if ! jv "$BRIK_EXT_SCHEMA" "$f" >/dev/null 2>&1; then
          fail=$((fail + 1))
          printf 'FAIL brik-extensions: %s\n' "$f" >&2
        fi
      done < <(find "$d" -name "*.sarif" -print0 2>/dev/null)
      return "$fail"
    }

    It "all 50 campaign SARIF files validate against SARIF 2.1.0"
      Skip if "jv not installed" jv_missing
      Skip if "campaign workspace not available" campaign_missing
      When call validate_all_campaign_sarifs_2_1_0
      The status should be success
    End

    It "all 50 campaign SARIF files validate against brik-extensions v1 (when extensions present)"
      Skip if "jv not installed" jv_missing
      Skip if "campaign workspace not available" campaign_missing
      When call validate_all_campaign_sarifs_brik_extensions
      The status should be success
    End
  End
End

#shellcheck shell=bash
# Validation contract for the v1 package-managers notion: publish output +
# brik.yml publish registries pinning.
#
# Sprint  of 
# (docs/chantiers/20260528_e2e-tests-par-notion.md), notion:
# package-managers (lib/package-managers/).
#
# The package-managers notion ships 6 builtin publishers (cargo, docker,
# maven, npm, nuget, pypi). Two contracts apply at the L0 boundary:
#
#   1) publish.<registry> ENUM in brik.yml schema
#      schema: schemas/config/v1/brik.schema.json ($defs.publish)
#      Pins the 6 user-facing registries.
#
#   2) brik-artifacts/package/package.json artifact
#      schema: schemas/report/v1.1/fragment.schema.json (REUSED)
#      The package stage emits a v1.1 fragment whose business.image and
#      business.registry sub-blocks carry the publish coordinates of the
#      built/pushed artifact (image name, tag, digest, registry host).
#
# Companion legacy specs:
#   - spec/_legacy/package-managers/*_spec.sh test the BEHAVIOURAL contract
#     of each publisher (L1).
#
# This spec pins the orthogonal axis: STATIC OUTPUT contract of the
# package fragment + brik.yml publish section (L0).
#
# Mirror pattern: stages/planning/registry/execution/findings/rollout/
# execution-environment/stack_contract_spec.sh.

Describe "package-managers notion contracts (fragment v1.1 reuse + brik.yml publish enum)"
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

    It "brik.yml v1 schema exists at the expected path"
      When call test -f "$BRIK_YML_V1_SCHEMA"
      The status should be success
    End

    It "fragment v1.1 is valid JSON"
      When call jq -e . "$FRAGMENT_V11_SCHEMA"
      The status should be success
      The output should not be blank
    End

    It "brik.yml v1 is valid JSON"
      When call jq -e . "$BRIK_YML_V1_SCHEMA"
      The status should be success
      The output should not be blank
    End
  End

  Describe "brik.yml publish.* registries (v1 supported publishers)"
    It "lists exactly the 6 supported registries (cargo, docker, maven, npm, nuget, pypi)"
      check_publish_registries() {
        jq -r '."$defs".publish.properties | keys | sort | join(",")' "$BRIK_YML_V1_SCHEMA"
      }
      When call check_publish_registries
      The output should equal "cargo,docker,maven,npm,nuget,pypi"
      The status should be success
    End
  End

  Describe "per-publisher output fragment v1.1 (valid sample, real campaign data)"
    It "accepts package-mgr-docker.json (docker packager, real sample with business.image + business.registry)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/valid/package-mgr-docker.json"
      The status should be success
    End
  End

  Describe "per-publisher output fragment v1.1 (invalid synthetic, contract violations)"
    It "rejects package-mgr-01-rc-negative.json (rc minimum: 0)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/invalid/package-mgr-01-rc-negative.json"
      The status should not equal 0
    End

    It "rejects package-mgr-02-status-out-of-enum.json (status='uploaded' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/invalid/package-mgr-02-status-out-of-enum.json"
      The status should not equal 0
    End

    It "rejects package-mgr-03-missing-status.json (status required)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/invalid/package-mgr-03-missing-status.json"
      The status should not equal 0
    End

    It "rejects package-mgr-04-business-status-out-of-enum.json (business.status='published-elsewhere' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/invalid/package-mgr-04-business-status-out-of-enum.json"
      The status should not equal 0
    End

    It "rejects package-mgr-05-missing-runner.json (runner required)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/invalid/package-mgr-05-missing-runner.json"
      The status should not equal 0
    End

    It "rejects package-mgr-06-runner-platform-out-of-enum.json (runner.platform='circleci' outside enum)"
      Skip if "jv not installed" jv_missing
      When call validate_fragment_v11 "${SAMPLES_DIR}/invalid/package-mgr-06-runner-platform-out-of-enum.json"
      The status should not equal 0
    End
  End

  Describe "campaign-wide validation (regression guard)"
    # Validate fragment v1.1 against ALL package.json artifacts captured
    # during the test campaign (5 samples).

    campaign_dir() {
      local d="${BRIK_HOME}/../docs/chantiers/e2e-cross-platform-v0.6.0/logs"
      [[ -d "$d" ]] && cd "$d" 2>/dev/null && pwd
    }

    campaign_missing() {
      local d
      d="$(campaign_dir)"
      [[ -z "$d" ]]
    }

    validate_all_campaign_package_fragments() {
      local d
      d="$(campaign_dir)"
      [[ -z "$d" ]] && return 1
      local fail=0
      while IFS= read -r -d '' f; do
        if ! jv --map "$SCHEMA_MAP" "$FRAGMENT_V11_SCHEMA" "$f" >/dev/null 2>&1; then
          fail=$((fail + 1))
          printf 'FAIL package fragment: %s\n' "$f" >&2
        fi
      done < <(find "$d" -name "package.json" -path "*/brik-artifacts/package/*" -print0 2>/dev/null)
      return "$fail"
    }

    It "all 5 campaign package.json fragments validate against v1.1"
      Skip if "jv not installed" jv_missing
      Skip if "campaign workspace not available" campaign_missing
      When call validate_all_campaign_package_fragments
      The status should be success
    End
  End
End

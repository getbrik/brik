Describe "shared-libs/gitlab templates - brik-artifacts paths"
  TEMPLATES_DIR="${BRIK_HOME}/shared-libs/gitlab/templates/jobs"
  BRIK_STAGE_TEMPLATE="${BRIK_HOME}/shared-libs/gitlab/templates/_brik-stage.yml"

  yq_missing() { ! command -v yq >/dev/null 2>&1; }

  artifact_has_brik_artifacts() {
    local file="$1" job_key="$2"
    yq -e ".${job_key}.artifacts.paths | contains([\"brik-artifacts/\"])" \
      "$file" >/dev/null 2>&1
  }

  artifact_when_always() {
    local file="$1" job_key="$2"
    [[ "$(yq -r ".${job_key}.artifacts.when" "$file")" == "always" ]]
  }

  artifact_expire_in() {
    local file="$1" job_key="$2"
    yq -r ".${job_key}.artifacts.expire_in" "$file"
  }

  job_extends_brik_stage() {
    local file="$1" job_key="$2"
    [[ "$(yq -r ".${job_key}.extends" "$file")" == ".brik-stage" ]]
  }

  # After Lot 3 of chantier 20260526, the artifacts contract
  # (brik-artifacts/ paths, when=always, expire_in 1 week) lives in the
  # hidden .brik-stage template. Each stage job either inherits it via
  # extends: .brik-stage (no local artifacts: override) OR overrides it
  # for a stage-specific reason (build, scan, test, package, notify).
  # The asserts here cover both paths so the parity contract still holds.

  Describe ".brik-stage hidden template carries the standard artifacts contract"
    It "lists brik-artifacts/ under .brik-stage.artifacts.paths"
      Skip if "yq not installed" yq_missing
      paths_includes() { yq -e '.[".brik-stage"].artifacts.paths | contains(["brik-artifacts/"])' "$BRIK_STAGE_TEMPLATE" >/dev/null 2>&1; }
      When call paths_includes
      The status should be success
    End

    It "uses artifacts.when: always"
      Skip if "yq not installed" yq_missing
      paths_when() { yq -r '.[".brik-stage"].artifacts.when' "$BRIK_STAGE_TEMPLATE"; }
      When call paths_when
      The output should equal "always"
    End

    It "uses artifacts.expire_in: 1 week"
      Skip if "yq not installed" yq_missing
      paths_expire() { yq -r '.[".brik-stage"].artifacts.expire_in' "$BRIK_STAGE_TEMPLATE"; }
      When call paths_expire
      The output should equal "1 week"
    End
  End

  # 7 jobs inherit the artifacts contract from .brik-stage (no override).
  # Verified by checking they extend .brik-stage AND don't redeclare artifacts.
  Describe "jobs that inherit artifacts from .brik-stage"
    Parameters
      "init"           "brik-init"
      "release"        "brik-release"
      "lint"           "brik-lint"
      "sast"           "brik-sast"
      "package"        "brik-package"
      "container-scan" "brik-container-scan"
      "promote"        "brik-promote"
      "deploy"         "brik-deploy"
    End

    It "$1.yml extends .brik-stage"
      Skip if "yq not installed" yq_missing
      When call job_extends_brik_stage "${TEMPLATES_DIR}/$1.yml" "$2"
      The status should be success
    End

    It "$1.yml does NOT redeclare artifacts (inheritance preserves contract)"
      Skip if "yq not installed" yq_missing
      artifacts_kind() { yq -r ".${2}.artifacts | type" "${TEMPLATES_DIR}/${1}.yml"; }
      When call artifacts_kind "$1" "$2"
      The output should equal "!!null"
    End
  End

  # 3 jobs override artifacts but must still ship brik-artifacts/ and use
  # when=always (parity-critical fields). expire_in may differ (notify).
  Describe "jobs that override artifacts (build/scan/test)"
    Parameters
      "build"   "brik-build"
      "scan"    "brik-scan"
      "test"    "brik-test"
    End

    It "$1.yml extends .brik-stage even with override"
      Skip if "yq not installed" yq_missing
      When call job_extends_brik_stage "${TEMPLATES_DIR}/$1.yml" "$2"
      The status should be success
    End

    It "$1.yml override still ships brik-artifacts/"
      Skip if "yq not installed" yq_missing
      When call artifact_has_brik_artifacts "${TEMPLATES_DIR}/$1.yml" "$2"
      The status should be success
    End

    It "$1.yml override still uses artifacts.when: always"
      Skip if "yq not installed" yq_missing
      When call artifact_when_always "${TEMPLATES_DIR}/$1.yml" "$2"
      The status should be success
    End
  End

  Describe "notify job (longer retention for the proof artefact)"
    It "notify.yml lists brik-artifacts/ under .brik-notify.artifacts.paths"
      Skip if "yq not installed" yq_missing
      When call artifact_has_brik_artifacts "${TEMPLATES_DIR}/notify.yml" "brik-notify"
      The status should be success
    End

    It "notify.yml uses artifacts.when: always"
      Skip if "yq not installed" yq_missing
      When call artifact_when_always "${TEMPLATES_DIR}/notify.yml" "brik-notify"
      The status should be success
    End

    It "notify.yml uses artifacts.expire_in: 1 month (longer retention for proof)"
      Skip if "yq not installed" yq_missing
      When call artifact_expire_in "${TEMPLATES_DIR}/notify.yml" "brik-notify"
      The output should equal "1 month"
    End
  End

  Describe "test.yml declares the new brik-artifacts/test/ paths"
    test_yml() { printf '%s' "${TEMPLATES_DIR}/test.yml"; }

    It "junit report points at brik-artifacts/test/junit.xml default"
      Skip if "yq not installed" yq_missing
      When call yq -r '.brik-test.artifacts.reports.junit' "$(test_yml)"
      The status should be success
      The output should include "brik-artifacts/test/junit.xml"
    End

    It "coverage_report.path is brik-artifacts/test/coverage/coverage.xml"
      Skip if "yq not installed" yq_missing
      When call yq -r '.brik-test.artifacts.reports.coverage_report.path' "$(test_yml)"
      The status should be success
      The output should equal "brik-artifacts/test/coverage/coverage.xml"
    End

    It "artifacts.paths carries brik-artifacts/ plus the cross-stage env file"
      Skip if "yq not installed" yq_missing
      When call yq -r '.brik-test.artifacts.paths | length' "$(test_yml)"
      The status should be success
      The output should equal "2"
    End

    It "artifacts.paths includes .brik-logs/ for cross-stage env propagation and forensic data"
      Skip if "yq not installed" yq_missing
      check_brik_logs_path() {
        yq -e '.brik-test.artifacts.paths | contains([".brik-logs/"])' \
          "$(test_yml)" >/dev/null 2>&1
      }
      When call check_brik_logs_path
      The status should be success
    End

    It "artifacts.exclude drops .lock and context-* churn from .brik-logs/"
      Skip if "yq not installed" yq_missing
      check_excludes() {
        yq -e '.brik-test.artifacts.exclude | contains([".brik-logs/*.lock", ".brik-logs/context-*"])' \
          "$(test_yml)" >/dev/null 2>&1
      }
      When call check_excludes
      The status should be success
    End
  End

  Describe "scan.yml + Ultimate overlays expose CycloneDX and SARIF for the Security tab"
    sarif_contains() {
      local file="$1" job_key="$2" path="$3"

      yq -e ".${job_key}.artifacts.reports.sarif | contains([\"${path}\"])" \
        "$file" >/dev/null 2>&1
    }

    cyclonedx_contains() {
      local file="$1" job_key="$2" path="$3"

      yq -e ".${job_key}.artifacts.reports.cyclonedx | contains([\"${path}\"])" \
        "$file" >/dev/null 2>&1
    }

    has_no_sarif() {
      local file="$1" job_key="$2"

      ! yq -e ".${job_key}.artifacts.reports.sarif" "$file" >/dev/null 2>&1
    }

    pipeline_yml() { printf '%s' "${TEMPLATES_DIR}/../pipeline.yml"; }

    It "scan.yml declares reports.cyclonedx pointing at the SBOM (free tier compatible)"
      Skip if "yq not installed" yq_missing
      When call cyclonedx_contains "${TEMPLATES_DIR}/scan.yml" "brik-scan" "brik-artifacts/scan/sbom.cdx.json"
      The status should be success
    End

    It "sast.yml does not embed reports.sarif (Ultimate-only, lives in overlay)"
      Skip if "yq not installed" yq_missing
      When call has_no_sarif "${TEMPLATES_DIR}/sast.yml" "brik-sast"
      The status should be success
    End

    It "scan.yml does not embed reports.sarif (Ultimate-only, lives in overlay)"
      Skip if "yq not installed" yq_missing
      When call has_no_sarif "${TEMPLATES_DIR}/scan.yml" "brik-scan"
      The status should be success
    End

    It "sast-reports.yml overlay declares reports.sarif on brik-sast"
      Skip if "yq not installed" yq_missing
      When call sarif_contains "${TEMPLATES_DIR}/sast-reports.yml" "brik-sast" "brik-artifacts/sast/sast.sarif"
      The status should be success
    End

    It "scan-reports.yml overlay declares reports.sarif for deps"
      Skip if "yq not installed" yq_missing
      When call sarif_contains "${TEMPLATES_DIR}/scan-reports.yml" "brik-scan" "brik-artifacts/scan/deps.sarif"
      The status should be success
    End

    It "scan-reports.yml overlay declares reports.sarif for secret"
      Skip if "yq not installed" yq_missing
      When call sarif_contains "${TEMPLATES_DIR}/scan-reports.yml" "brik-scan" "brik-artifacts/scan/secret.sarif"
      The status should be success
    End

    It "pipeline.yml references sast-reports overlay (conditional include)"
      When call grep -F "sast-reports.yml" "$(pipeline_yml)"
      The status should be success
      The output should be present
    End

    It "pipeline.yml references scan-reports overlay (conditional include)"
      When call grep -F "scan-reports.yml" "$(pipeline_yml)"
      The status should be success
      The output should be present
    End
  End
End

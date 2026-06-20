#shellcheck shell=bash
# Contract for the factored GitLab templates: the shared script and
# artifacts contract centralized into the hidden _brik-stage.yml template.
#
# Invariants:
#   I3 - image per stage is resolved from a single SoT (runner_classes.yml)
#        and propagated to downstream jobs via init's dotenv export. The
#        per-job YAML references ${BRIK_IMG_<CLASS>} instead of hardcoding
#        the OCI path.
#   I9 - the artifacts contract (paths/exclude/dotenv) is declared once in
#        the hidden template .brik-stage and inherited by every standard
#        job via `extends:`. Stage-specific overrides (notify's name +
#        sast report) are explicit, not duplicated.
#
# Note: plan.yml, sast-reports.yml, scan-reports.yml are OUT OF SCOPE
# (Brik CLI job + Ultimate overlays, not standard stage jobs).

Describe "shared-libs/gitlab/templates - factored Lot 3"
  TEMPLATES_DIR="${BRIK_HOME}/shared-libs/gitlab/templates"
  JOBS_DIR="${TEMPLATES_DIR}/jobs"
  BRIK_STAGE_TEMPLATE="${TEMPLATES_DIR}/_brik-stage.yml"

  yq_missing() { ! command -v yq >/dev/null 2>&1; }

  # -------------------------------------------------------------------------
  # _brik-stage.yml: hidden template carrying script + artifacts
  # -------------------------------------------------------------------------
  Describe "_brik-stage.yml template"
    It "exists at the expected path"
      When run test -f "$BRIK_STAGE_TEMPLATE"
      The status should be success
    End

    It "declares a hidden job named '.brik-stage'"
      Skip if "yq not installed" yq_missing
      When call yq -r 'keys | .[]' "$BRIK_STAGE_TEMPLATE"
      The output should equal ".brik-stage"
    End

    It "defines a script that sources the plan gate as its first step"
      Skip if "yq not installed" yq_missing
      gate_step() { yq -r '.[".brik-stage"].script[0]' "$BRIK_STAGE_TEMPLATE"; }
      When call gate_step
      The output should include "brik-plan-gate.sh"
    End

    It "defines a script that invokes brik.gitlab.run_stage as its second step"
      Skip if "yq not installed" yq_missing
      run_step() { yq -r '.[".brik-stage"].script[1]' "$BRIK_STAGE_TEMPLATE"; }
      When call run_step
      The output should include "brik.gitlab.run_stage"
    End

    It "declares artifacts.reports.dotenv pointing at pipeline.env"
      Skip if "yq not installed" yq_missing
      dotenv_path() { yq -r '.[".brik-stage"].artifacts.reports.dotenv' "$BRIK_STAGE_TEMPLATE"; }
      When call dotenv_path
      The output should equal ".brik-logs/pipeline.env"
    End

    It "declares artifacts.paths including .brik-logs/ and brik-artifacts/"
      Skip if "yq not installed" yq_missing
      paths() { yq -r '.[".brik-stage"].artifacts.paths | join(",")' "$BRIK_STAGE_TEMPLATE"; }
      When call paths
      The output should include ".brik-logs/"
      The output should include "brik-artifacts/"
    End

    It "declares artifacts.when=always so skipped/failed jobs ship their logs"
      Skip if "yq not installed" yq_missing
      when_clause() { yq -r '.[".brik-stage"].artifacts.when' "$BRIK_STAGE_TEMPLATE"; }
      When call when_clause
      The output should equal "always"
    End
  End

  # -------------------------------------------------------------------------
  # Standard stage jobs: extends .brik-stage, no inline script/artifacts
  # -------------------------------------------------------------------------
  Describe "standard stage jobs extend .brik-stage"
    # 7 jobs with NO artifacts or script override (inherit fully from
    # .brik-stage). 5 jobs override and have their own dedicated Describe
    # block below: build (artifacts paths for dist/target/*.whl), scan
    # (cyclonedx report), test (junit + coverage_report), package (script
    # adds Docker CLI install), notify (sast report + custom name).
    Parameters
      "init"
      "release"
      "lint"
      "sast"
      "container-scan"
      "promote"
      "deploy"
    End

    It "job brik-$1 extends .brik-stage"
      Skip if "yq not installed" yq_missing
      extends_value() { yq -r ".[\"brik-$1\"].extends" "${JOBS_DIR}/$1.yml"; }
      When call extends_value "$1"
      The output should equal ".brik-stage"
    End

    It "job brik-$1 does not declare a top-level script: block"
      Skip if "yq not installed" yq_missing
      script_kind() { yq -r ".[\"brik-$1\"].script | type" "${JOBS_DIR}/$1.yml"; }
      When call script_kind "$1"
      The output should equal "!!null"
    End

    It "job brik-$1 does not declare a top-level artifacts: block"
      Skip if "yq not installed" yq_missing
      artifacts_kind() { yq -r ".[\"brik-$1\"].artifacts | type" "${JOBS_DIR}/$1.yml"; }
      When call artifacts_kind "$1"
      The output should equal "!!null"
    End

    It "job brik-$1 declares BRIK_STAGE_ID variable matching its id"
      Skip if "yq not installed" yq_missing
      stage_id_var() { yq -r ".[\"brik-$1\"].variables.BRIK_STAGE_ID" "${JOBS_DIR}/$1.yml"; }
      When call stage_id_var "$1"
      The output should equal "$1"
    End

    It "job brik-$1 declares stage assignment"
      Skip if "yq not installed" yq_missing
      stage_assignment() { yq -r ".[\"brik-$1\"].stage" "${JOBS_DIR}/$1.yml"; }
      When call stage_assignment "$1"
      The output should not equal "null"
    End

    It "job brik-$1 declares image from the init dotenv contract"
      Skip if "yq not installed" yq_missing
      # Two valid forms:
      #   ${BRIK_IMG_<CLASS>} for static classes (base, analysis,
      #     scanner, deploy)
      #   ${BRIK_CI_IMAGE} for the dynamic stack class (legacy name,
      #     kept under the GitLab dotenv 20-var limit; brikDriver
      #     falls back to it for stack class)
      image_ref_ok() {
        local img
        img="$(yq -r ".[\"brik-$1\"].image" "${JOBS_DIR}/$1.yml")"
        case "$img" in
          *BRIK_IMG_*|*BRIK_CI_IMAGE*) return 0 ;;
          *) printf 'unexpected image: %s\n' "$img" >&2; return 1 ;;
        esac
      }
      When call image_ref_ok "$1"
      The status should be success
    End
  End

  # -------------------------------------------------------------------------
  # build: extends .brik-stage with artifacts override (ship build outputs)
  # -------------------------------------------------------------------------
  Describe "build.yml (special: artifacts override for build outputs)"
    BUILD="${JOBS_DIR}/build.yml"

    It "brik-build extends .brik-stage"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-build"].extends' "$BUILD"
      The output should equal ".brik-stage"
    End

    It "brik-build declares image as a BRIK_IMG_ reference"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-build"].image' "$BUILD"
      The output should include "BRIK_IMG_"
    End

    It "brik-build artifacts.paths still includes build outputs (dist/, target/, etc.)"
      Skip if "yq not installed" yq_missing
      paths_join() { yq -r '.["brik-build"].artifacts.paths | join(",")' "$BUILD"; }
      When call paths_join
      The output should include "dist/"
      The output should include "target/"
    End

    It "brik-build declares BRIK_STAGE_ID=build"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-build"].variables.BRIK_STAGE_ID' "$BUILD"
      The output should equal "build"
    End
  End

  # -------------------------------------------------------------------------
  # scan: extends .brik-stage with artifacts override (cyclonedx SBOM)
  # -------------------------------------------------------------------------
  Describe "scan.yml (special: cyclonedx report override)"
    SCAN="${JOBS_DIR}/scan.yml"

    It "brik-scan extends .brik-stage"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-scan"].extends' "$SCAN"
      The output should equal ".brik-stage"
    End

    It "brik-scan declares image as a BRIK_IMG_ reference"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-scan"].image' "$SCAN"
      The output should include "BRIK_IMG_"
    End

    It "brik-scan declares the cyclonedx SBOM report"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-scan"].artifacts.reports.cyclonedx | join(",")' "$SCAN"
      The output should include "sbom.cdx.json"
    End

    It "brik-scan declares BRIK_STAGE_ID=scan"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-scan"].variables.BRIK_STAGE_ID' "$SCAN"
      The output should equal "scan"
    End
  End

  # -------------------------------------------------------------------------
  # test: extends .brik-stage with artifacts override (junit + coverage)
  # -------------------------------------------------------------------------
  Describe "test.yml (special: junit + coverage_report override)"
    TEST="${JOBS_DIR}/test.yml"

    It "brik-test extends .brik-stage"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-test"].extends' "$TEST"
      The output should equal ".brik-stage"
    End

    It "brik-test declares image as a BRIK_IMG_ reference"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-test"].image' "$TEST"
      The output should include "BRIK_IMG_"
    End

    It "brik-test declares the junit report"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-test"].artifacts.reports.junit' "$TEST"
      The output should not equal "null"
    End

    It "brik-test declares cobertura coverage_report"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-test"].artifacts.reports.coverage_report.coverage_format' "$TEST"
      The output should equal "cobertura"
    End

    It "brik-test declares BRIK_STAGE_ID=test"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-test"].variables.BRIK_STAGE_ID' "$TEST"
      The output should equal "test"
    End
  End

  # -------------------------------------------------------------------------
  # package: extends .brik-stage with script override (Docker CLI install)
  # -------------------------------------------------------------------------
  Describe "package.yml (special: script override for Docker CLI install)"
    PACKAGE="${JOBS_DIR}/package.yml"

    It "brik-package extends .brik-stage"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-package"].extends' "$PACKAGE"
      The output should equal ".brik-stage"
    End

    It "brik-package declares image as a BRIK_IMG_ reference"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-package"].image' "$PACKAGE"
      The output should include "BRIK_IMG_"
    End

    It "brik-package script installs docker-cli when needed"
      When run grep -qF "docker-cli" "$PACKAGE"
      The status should be success
    End

    It "brik-package declares BRIK_STAGE_ID=package"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-package"].variables.BRIK_STAGE_ID' "$PACKAGE"
      The output should equal "package"
    End
  End

  # -------------------------------------------------------------------------
  # notify: extends .brik-stage with artifacts override (name + sast)
  # -------------------------------------------------------------------------
  Describe "notify.yml (special: artifacts override)"
    NOTIFY="${JOBS_DIR}/notify.yml"

    It "brik-notify extends .brik-stage"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-notify"].extends' "$NOTIFY"
      The output should equal ".brik-stage"
    End

    It "brik-notify overrides artifacts to add the SAST report"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-notify"].artifacts.reports.sast' "$NOTIFY"
      The output should include "gl-sast-report.json"
    End

    It "brik-notify uses when: always"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-notify"].when' "$NOTIFY"
      The output should equal "always"
    End

    It "brik-notify declares BRIK_STAGE_ID=notify"
      Skip if "yq not installed" yq_missing
      When call yq -r '.["brik-notify"].variables.BRIK_STAGE_ID' "$NOTIFY"
      The output should equal "notify"
    End
  End

  # -------------------------------------------------------------------------
  # brik-integrate.yml: includes _brik-stage.yml, drops redundant image variables
  # -------------------------------------------------------------------------
  Describe "brik-integrate.yml"
    PIPELINE="${TEMPLATES_DIR}/brik-integrate.yml"

    It "includes _brik-stage.yml in the local includes list"
      When run grep -qE "_brik-stage\.yml" "$PIPELINE"
      The status should be success
    End

    It "no longer declares BRIK_ANALYSIS_IMAGE at top level (subsumed by BRIK_IMG_ANALYSIS dotenv)"
      Skip if "yq not installed" yq_missing
      var_ana() { yq -r '.variables.BRIK_ANALYSIS_IMAGE // "absent"' "$PIPELINE"; }
      When call var_ana
      The output should equal "absent"
    End

    It "no longer declares BRIK_SCANNER_IMAGE at top level (subsumed by BRIK_IMG_SCANNER dotenv)"
      Skip if "yq not installed" yq_missing
      var_scan() { yq -r '.variables.BRIK_SCANNER_IMAGE // "absent"' "$PIPELINE"; }
      When call var_scan
      The output should equal "absent"
    End

    It "no longer declares BRIK_DEPLOY_IMAGE at top level (subsumed by BRIK_IMG_DEPLOY dotenv)"
      Skip if "yq not installed" yq_missing
      var_dep() { yq -r '.variables.BRIK_DEPLOY_IMAGE // "absent"' "$PIPELINE"; }
      When call var_dep
      The output should equal "absent"
    End
  End

  # -------------------------------------------------------------------------
  # init.sh exports BRIK_IMG_* via the report env section so downstream
  # jobs can substitute ${BRIK_IMG_<CLASS>} in their image: directive.
  # -------------------------------------------------------------------------
  Describe "lib/stages/init.sh exposes BRIK_IMG_* via dotenv"
    INIT="${BRIK_HOME}/lib/stages/init.sh"

    Parameters
      "BRIK_IMG_BASE"
      "BRIK_IMG_ANALYSIS"
      "BRIK_IMG_SCANNER"
      "BRIK_IMG_DEPLOY"
    End

    It "init records $1 as a dotenv key"
      When run grep -qE "_kv $1 " "$INIT"
      The status should be success
    End
  End
End

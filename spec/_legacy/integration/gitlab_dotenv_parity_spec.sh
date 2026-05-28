Describe "GitLab templates: reports.dotenv parity"
  # Every brik stage job must ship its pipeline.env via
  # `artifacts.reports.dotenv: .brik-logs/pipeline.env`. This is the
  # mechanism GitLab uses to promote pipeline.env keys to CI variables in
  # downstream jobs (cf. chantier 20260516_gitlab-pipeline-env-propagation).
  #
  # The promotion is required at YAML-parse time for downstream `image:`
  # directives that resolve ${BRIK_IMG_<CLASS>}.
  #
  # After Lot 3 of chantier 20260526 the contract is FACTORED into the
  # hidden template .brik-stage and inherited via `extends:`. Stages that
  # override artifacts (build/scan/test/notify) MUST still ship the dotenv
  # report explicitly because GitLab's extends replaces the whole artifacts
  # block (no merge). This spec accepts both inheritance and explicit
  # override paths.
  #
  # Overlay templates (*-reports.yml) are excluded: they extend an existing
  # job's artifacts.reports for Ultimate-tier features and never define
  # standalone jobs.

  TEMPLATES_DIR="$BRIK_HOME/shared-libs/gitlab/templates/jobs"
  BRIK_STAGE_TEMPLATE="$BRIK_HOME/shared-libs/gitlab/templates/_brik-stage.yml"
  EXPECTED_DOTENV=".brik-logs/pipeline.env"

  Describe ".brik-stage carries the canonical dotenv contract"
    It "_brik-stage.yml declares artifacts.reports.dotenv"
      check_brik_stage() {
        yq -r '.[".brik-stage"].artifacts.reports.dotenv' "$BRIK_STAGE_TEMPLATE"
      }
      When call check_brik_stage
      The output should equal "$EXPECTED_DOTENV"
    End
  End

  Describe "stages either inherit dotenv from .brik-stage or override explicitly"
    Parameters
      "init.yml"           "brik-init"
      "release.yml"        "brik-release"
      "build.yml"          "brik-build"
      "lint.yml"           "brik-lint"
      "sast.yml"           "brik-sast"
      "scan.yml"           "brik-scan"
      "test.yml"           "brik-test"
      "package.yml"        "brik-package"
      "container-scan.yml" "brik-container-scan"
      "deploy.yml"         "brik-deploy"
      "notify.yml"         "brik-notify"
    End

    It "$1 either inherits dotenv via extends or declares it explicitly"
      check_template() {
        local file="$TEMPLATES_DIR/$1"
        local job="$2"
        if [[ ! -f "$file" ]]; then
          echo "missing template: $file" >&2
          return 1
        fi
        local declared
        declared="$(yq -r ".\"${job}\".artifacts.reports.dotenv // \"\"" "$file" 2>/dev/null)"
        if [[ "$declared" == "$EXPECTED_DOTENV" ]]; then
          echo "ok"
          return 0
        fi
        local extends_value artifacts_kind
        extends_value="$(yq -r ".\"${job}\".extends // \"\"" "$file" 2>/dev/null)"
        artifacts_kind="$(yq -r ".\"${job}\".artifacts | type" "$file" 2>/dev/null)"
        if [[ "$extends_value" == ".brik-stage" && "$artifacts_kind" == "!!null" ]]; then
          echo "ok"
          return 0
        fi
        echo "drift: $1 dotenv=\"${declared:-<missing>}\" extends=\"${extends_value}\" artifacts=$artifacts_kind expected=\"$EXPECTED_DOTENV\"" >&2
        echo "drift"
      }
      When call check_template "$1" "$2"
      The output should equal "ok"
    End
  End

  Describe "overlay templates do not declare dotenv"
    # *-reports.yml overlays inject SARIF reports onto existing jobs;
    # they must not redeclare dotenv (or any other contract) on those
    # jobs. Negative parity: ensure no overlay carries an accidental
    # dotenv that would conflict with the base template.
    Parameters
      "sast-reports.yml"
      "scan-reports.yml"
    End

    It "$1 does not declare dotenv"
      check_overlay() {
        local file="$TEMPLATES_DIR/$1"
        if [[ ! -f "$file" ]]; then
          echo "missing overlay: $file" >&2
          return 1
        fi
        local actual
        actual="$(yq '[ to_entries[] | select(.value.artifacts.reports.dotenv) | .value.artifacts.reports.dotenv ][0] // ""' "$file" 2>/dev/null)"
        if [[ -z "$actual" ]]; then
          echo "ok"
        else
          echo "drift: overlay $1 should not declare dotenv (got \"$actual\")" >&2
          echo "drift"
        fi
      }
      When call check_overlay "$1"
      The output should equal "ok"
    End
  End
End

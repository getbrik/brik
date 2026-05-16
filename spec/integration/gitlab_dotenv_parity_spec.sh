Describe "GitLab templates: reports.dotenv parity"
  # Every standalone brik stage job template must declare
  # `artifacts.reports.dotenv: .brik-logs/pipeline.env`. This is the
  # mechanism GitLab uses to promote pipeline.env keys to CI variables in
  # downstream jobs (cf. chantier 20260516_gitlab-pipeline-env-propagation).
  #
  # The promotion is required at YAML-parse time for downstream `image:`
  # directives that resolve ${BRIK_*_IMAGE} (build/test/lint use
  # ${BRIK_CI_IMAGE}, scan and container-scan use ${BRIK_SCANNER_IMAGE},
  # sast uses ${BRIK_ANALYSIS_IMAGE}, deploy uses ${BRIK_DEPLOY_IMAGE}).
  #
  # GitLab merges reports.dotenv from multiple `needs` jobs in declaration
  # order, with later jobs overriding earlier ones on key collisions.
  # Declaring it uniformly on every brik stage ensures the cumulative
  # pipeline.env content (init -> release -> build -> ...) is what
  # downstream jobs see.
  #
  # Overlay templates (*-reports.yml) are excluded: they extend an existing
  # job's artifacts.reports for Ultimate-tier features (sast.sarif,
  # dependency_scanning.sarif) and never define standalone jobs.

  TEMPLATES_DIR="$BRIK_HOME/shared-libs/gitlab/templates/jobs"
  EXPECTED_DOTENV=".brik-logs/pipeline.env"

  Describe "every stage template declares reports.dotenv"
    Parameters
      "init.yml"
      "release.yml"
      "build.yml"
      "lint.yml"
      "sast.yml"
      "scan.yml"
      "test.yml"
      "package.yml"
      "container-scan.yml"
      "deploy.yml"
      "notify.yml"
    End

    It "$1 declares artifacts.reports.dotenv: .brik-logs/pipeline.env"
      check_template() {
        local file="$TEMPLATES_DIR/$1"
        if [[ ! -f "$file" ]]; then
          echo "missing template: $file" >&2
          return 1
        fi
        # The job name varies per file (brik-init, brik-release, ...), so
        # walk every map node looking for an artifacts.reports.dotenv.
        local actual
        actual="$(yq '[ to_entries[] | select(.value.artifacts.reports.dotenv) | .value.artifacts.reports.dotenv ][0] // ""' "$file" 2>/dev/null)"
        if [[ "$actual" == "$EXPECTED_DOTENV" ]]; then
          echo "ok"
        else
          echo "drift: $1 dotenv=\"${actual:-<missing>}\" expected=\"$EXPECTED_DOTENV\"" >&2
          echo "drift"
        fi
      }
      When call check_template "$1"
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

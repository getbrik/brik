Describe "GitLab CD pipeline template (brik-deploy.yml)"
  # Structural guards for the separate CD pipeline: it must trigger only on the
  # explicit CD inputs, expose the SoT CD params, and map them to `brik deploy`.
  # Runtime behaviour is validated by the briklab E2E suite.

  CD="$BRIK_HOME/shared-libs/gitlab/templates/brik-deploy.yml"

  It "is valid YAML"
    parse() { yq -e '.' "$CD" >/dev/null; }
    When call parse
    The status should be success
  End

  It "triggers only when both CD inputs are set"
    rule() { yq -r '.workflow.rules[0].if' "$CD"; }
    When call rule
    The output should include 'BRIK_DEPLOY_VERSION'
    The output should include 'BRIK_DEPLOY_ENVIRONMENT'
  End

  It "suppresses the pipeline otherwise (terminal never rule)"
    last_rule() { yq -r '.workflow.rules[-1].when' "$CD"; }
    When call last_rule
    The output should equal "never"
  End

  It "exposes the two CD params as long-form variables"
    params() {
      printf '%s|%s' \
        "$(yq -r '.variables.BRIK_DEPLOY_VERSION | has("value")' "$CD")" \
        "$(yq -r '.variables.BRIK_DEPLOY_ENVIRONMENT | has("value")' "$CD")"
    }
    When call params
    The output should equal "true|true"
  End

  It "maps the inputs to a brik deploy job in the deploy stage"
    deploy_job() {
      yq -r '.["brik-cd-deploy"].stage' "$CD"
    }
    When call deploy_job
    The output should equal "deploy"
  End

  It "invokes brik deploy with the version and environment inputs"
    deploy_script() {
      yq -r '.["brik-cd-deploy"].script | join("\n")' "$CD"
    }
    When call deploy_script
    The output should include "brik deploy"
    The output should include "BRIK_DEPLOY_VERSION"
    The output should include "BRIK_DEPLOY_ENVIRONMENT"
  End

  It "ships the pipeline.env dotenv report (propagation parity)"
    dotenv() {
      yq -r '.["brik-cd-deploy"].artifacts.reports.dotenv' "$CD"
    }
    When call dotenv
    The output should equal ".brik-logs/pipeline.env"
  End
End

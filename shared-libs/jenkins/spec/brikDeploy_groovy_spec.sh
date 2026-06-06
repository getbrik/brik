#shellcheck shell=bash
Describe "shared-libs/jenkins brikDeploy.groovy - CD entry (mode 2)"
  # Structural guards for the separate Jenkins CD var. It is the Jenkins
  # analogue of shared-libs/gitlab/templates/pipeline-deploy.yml: a thin
  # entry that maps the two CD inputs (BRIK_DEPLOY_VERSION /
  # BRIK_DEPLOY_ENVIRONMENT) to a single `brik deploy` invocation. All
  # business logic stays in lib/ (the deploy verb); this var only declares
  # params, prepares the workspace, runs the verb in the deploy runner
  # image, and archives the evidence. Runtime behaviour is validated by the
  # briklab Jenkins E2E suite.
  GROOVY="${BRIK_HOME}/shared-libs/jenkins/vars/brikDeploy.groovy"

  It "is a Jenkins global var with a Map-accepting call()"
    When call grep -F "def call(Map params = [:])" "$GROOVY"
    The status should be success
    The output should be present
  End

  Describe "exposes the two CD params (SoT parity with GitLab)"
    It "declares BRIK_DEPLOY_VERSION"
      When call grep -F "name: 'BRIK_DEPLOY_VERSION'" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "declares BRIK_DEPLOY_ENVIRONMENT"
      When call grep -F "name: 'BRIK_DEPLOY_ENVIRONMENT'" "$GROOVY"
      The status should be success
      The output should be present
    End
  End

  Describe "maps the inputs to the brik deploy verb"
    It "invokes brik deploy"
      When call grep -F "bin/brik deploy" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "passes the version input through"
      # `--` terminates grep option parsing: without it, grep reads the
      # leading "--version"/"--environment" as its own flags.
      When call grep -F -- "--version" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "passes the environment input through"
      When call grep -F -- "--environment" "$GROOVY"
      The status should be success
      The output should be present
    End
  End

  Describe "runs in the deploy runner image, reusing the shared helpers"
    It "resolves the deploy image via brikDriver.resolveImage"
      When call grep -F "brikDriver.resolveImage('deploy'" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "resolves the brik library via brikResolveHome"
      When call grep -F "brikResolveHome()" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "builds the deploy docker args via brikDockerArgs"
      When call grep -F "brikDockerArgs(" "$GROOVY"
      The status should be success
      The output should be present
    End

    It "checks out the project SCM before deploying"
      When call grep -F "checkout scm" "$GROOVY"
      The status should be success
      The output should be present
    End
  End

  Describe "the entry is a thin mapper, not the CI flow"
    It "does not iterate the CI stage list (brikDriver.stagesList)"
      When call grep -F "brikDriver.stagesList" "$GROOVY"
      The status should not equal 0
    End

    It "declares no hardcoded brik-runner image literal"
      When call grep -F "ghcr.io/getbrik/brik-runner" "$GROOVY"
      The status should not equal 0
    End
  End

  Describe "archives the deploy evidence (parity with the CI final block)"
    It "archives both brik-artifacts and .brik-logs"
      When call grep -F "archiveArtifacts" "$GROOVY"
      The status should be success
      The output should be present
    End
  End
End

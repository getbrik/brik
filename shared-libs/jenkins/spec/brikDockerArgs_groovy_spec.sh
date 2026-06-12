#shellcheck shell=bash
# Contract for shared-libs/jenkins/vars/brikDockerArgs.groovy.
#
# brikDockerArgs builds the docker.image().inside() argument strings shared
# by every stage container. It writes three temporary env-files scoping the
# Brik-relevant env vars by phase: CI stages, the deploy stage, and the
# signing stage (container-scan).

Describe "shared-libs/jenkins/vars/brikDockerArgs.groovy"
  GROOVY="${BRIK_HOME}/shared-libs/jenkins/vars/brikDockerArgs.groovy"

  It "file exists"
    When run test -f "$GROOVY"
    The status should be success
  End

  It "scopes the CI env-file to build and publish prefixes (no deploy or signing creds)"
    When run grep -qF "grep -E '^(NEXUS_|BRIK_|REGISTRY_|CARGO_)'" "$GROOVY"
    The status should be success
  End

  It "scopes the deploy env-file to deploy prefixes (no package-publish creds)"
    When run grep -qF "grep -E '^(NEXUS_|BRIK_|REGISTRY_|ARGOCD_|SSH_)'" "$GROOVY"
    The status should be success
  End

  It "does not leak deploy creds (ARGOCD_/SSH_) into the CI env-file"
    leaks_ci() { grep -F "grep -E '^(NEXUS_|BRIK_|REGISTRY_|ARGOCD_|CARGO_|SSH_)'" "$GROOVY"; }
    When run leaks_ci
    The status should be failure
    The output should equal ""
  End

  It "builds a separate deploy env-file"
    When run grep -qF "brik-deploy-env-" "$GROOVY"
    The status should be success
  End

  # Signing material (the OpenBAO token, COSIGN_ key refs) must reach only
  # the container-scan container, where attestations are signed: user-defined
  # commands run in the other CI containers, and isolating the signing
  # credential from them is the credential leg of the SLSA L2 posture.
  It "builds a separate signing env-file (BRIK_SIGNING_/COSIGN_)"
    When run grep -qF "grep -E '^(BRIK_SIGNING_|COSIGN_)'" "$GROOVY"
    The status should be success
  End

  It "does not put COSIGN_ signing material in the CI env-file"
    leaks_cosign() { grep -F "grep -E '^(NEXUS_|BRIK_|REGISTRY_|CARGO_|COSIGN_)'" "$GROOVY"; }
    When run leaks_cosign
    The status should be failure
    The output should equal ""
  End

  It "excludes BRIK_SIGNING_ from the CI and deploy env-files"
    count_exclusions() {
      grep -cF "grep -vE '^(BRIK_RUNNER_CLASSES_FILE=|BRIK_SIGNING_)'" "$GROOVY"
    }
    When call count_exclusions
    The output should equal 2
  End

  It "returns signingDockerArgs composed on top of the CI args"
    When run grep -qF 'def signingDockerArgs = "${dockerArgs} ${signingEnvFileArg}"' "$GROOVY"
    The status should be success
  End

  # The env-file is appended AFTER brikRunStage's explicit
  # -e BRIK_RUNNER_CLASSES_FILE=<absolute>, so a raw (relative) param value
  # captured here would clobber the resolved absolute path and the registry
  # override would silently fall back to the bundled default.
  It "excludes BRIK_RUNNER_CLASSES_FILE from the env-file so the explicit -e wins"
    When run grep -qE "grep -vE? '\^\(?BRIK_RUNNER_CLASSES_FILE=" "$GROOVY"
    The status should be success
  End
End

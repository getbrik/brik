#shellcheck shell=bash
# Contract for shared-libs/jenkins/vars/brikDockerArgs.groovy.
#
# brikDockerArgs builds the docker.image().inside() argument strings shared
# by every stage container. It writes a temporary env-file propagating the
# Brik-relevant env vars into the runner.

Describe "shared-libs/jenkins/vars/brikDockerArgs.groovy"
  GROOVY="${BRIK_HOME}/shared-libs/jenkins/vars/brikDockerArgs.groovy"

  It "file exists"
    When run test -f "$GROOVY"
    The status should be success
  End

  It "scopes the CI env-file to build and publish prefixes (no deploy creds)"
    # COSIGN_ carries the signing-key passphrase the container-scan stage
    # needs to decrypt the referential's cosign key.
    When run grep -qF "grep -E '^(NEXUS_|BRIK_|REGISTRY_|CARGO_|COSIGN_)'" "$GROOVY"
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

  # The env-file is appended AFTER brikRunStage's explicit
  # -e BRIK_RUNNER_CLASSES_FILE=<absolute>, so a raw (relative) param value
  # captured here would clobber the resolved absolute path and the registry
  # override would silently fall back to the bundled default.
  It "excludes BRIK_RUNNER_CLASSES_FILE from the env-file so the explicit -e wins"
    When run grep -qF "grep -v '^BRIK_RUNNER_CLASSES_FILE='" "$GROOVY"
    The status should be success
  End
End

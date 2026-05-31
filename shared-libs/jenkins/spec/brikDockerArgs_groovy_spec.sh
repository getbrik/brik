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

  It "filters env vars by Brik-relevant prefixes"
    When run grep -qF "grep -E '^(NEXUS_|BRIK_|REGISTRY_|ARGOCD_|CARGO_|SSH_)'" "$GROOVY"
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

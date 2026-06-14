#!/usr/bin/env bash
# local_default_infra_spec.sh - the host-side default-referential fallback.
# On a bare host with no referential configured, the CI flow (integrate/stage)
# falls back to the bundled default (profile `local`). An explicit referential
# always wins, and a non-local host (orchestrated CI) never falls back. The CD
# verbs do NOT use this resolver - they stay strict.

Describe "cli/local_runner.sh - default referential fallback"
  Include "$BRIK_HOME/lib/cli/helpers.sh"
  Include "$BRIK_HOME/lib/cli/local_runner.sh"

  # Run the resolver in a clean env shaped by the args, then echo the result.
  # Usage: probe [preset_dir] [preset_repo] [orchestrator_signal]
  probe() {
    unset BRIK_INFRA_DIR BRIK_INFRA_REPO GITLAB_CI JENKINS_URL BRIK_LOCAL_CONTAINER
    [[ -n "${1:-}" ]] && export BRIK_INFRA_DIR="$1"
    [[ -n "${2:-}" ]] && export BRIK_INFRA_REPO="$2"
    [[ -n "${3:-}" ]] && export GITLAB_CI="$3"
    cli.local_runner.default_infra
    printf '%s' "${BRIK_INFRA_DIR:-<empty>}"
  }

  It "falls back to the bundled default on a bare host with no referential"
    When call probe
    The output should equal "$BRIK_HOME/share/infra/p-local"
  End

  It "leaves an explicit BRIK_INFRA_DIR untouched"
    When call probe "/custom/infra"
    The output should equal "/custom/infra"
  End

  It "does not set a dir when BRIK_INFRA_REPO is configured"
    When call probe "" "git@example.com:infra.git"
    The output should equal "<empty>"
  End

  It "does not fall back inside orchestrated CI (GITLAB_CI set)"
    When call probe "" "" "true"
    The output should equal "<empty>"
  End
End

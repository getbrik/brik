Describe "planning/plan.sh"
  Include "$BRIK_HOME/lib/pipeline/logging.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/planning/plan.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  Describe "plan.stages.ordered"
    It "echoes the canonical registry order"
      When call plan.stages.ordered
      The status should be success
      The line 1 of output should equal "init"
      The line 2 of output should equal "release"
      The line 3 of output should equal "build"
    End
  End

  Describe "plan.dag.edges"
    It "emits sorted from-to pairs"
      When call plan.dag.edges
      The status should be success
      The line 1 of output should equal "build	lint"
      The output should include "init	build"
      The output should include "container-scan	deploy"
    End
  End

  Describe "plan.decide"
    It "skips release in snapshot context (gate.contexts mismatch)"
      tmp=$(mktemp)
      When call plan.decide release safe snapshot false false false node "$tmp"
      The status should be success
      The output should equal $'skip\tcontext-mismatch'
      rm -f "$tmp"
    End

    It "runs release in release context with --with-release"
      tmp=$(mktemp)
      When call plan.decide release safe release true false false node "$tmp"
      The status should be success
      The output should equal $'run\tcontext-match'
      rm -f "$tmp"
    End

    It "skips package when --with-package is absent"
      tmp=$(mktemp)
      When call plan.decide package safe snapshot false false false node "$tmp"
      The status should be success
      The output should equal $'skip\topt-in-flag-missing'
      rm -f "$tmp"
    End

    It "runs lint in safe mode with context-match"
      tmp=$(mktemp)
      When call plan.decide lint safe snapshot false false false node "$tmp"
      The status should be success
      The output should equal $'run\tcontext-match'
      rm -f "$tmp"
    End

    It "skips lint in balanced mode when no .ts file changed"
      tmp=$(mktemp)
      printf 'docs/manual.adoc\0' > "$tmp"
      When call plan.decide lint balanced snapshot false false false node "$tmp"
      The status should be success
      The output should equal $'skip\tno-impact'
      rm -f "$tmp"
    End

    It "runs lint in balanced mode when a .ts file changed"
      tmp=$(mktemp)
      printf 'src/index.ts\0' > "$tmp"
      When call plan.decide lint balanced snapshot false false false node "$tmp"
      The status should be success
      The output should equal $'run\timpacted'
      rm -f "$tmp"
    End

    It "runs in balanced mode on cold start (empty changes file)"
      tmp=$(mktemp)
      When call plan.decide lint balanced snapshot false false false node "$tmp"
      The status should be success
      The output should equal $'run\tno-diff'
      rm -f "$tmp"
    End
  End

  Describe "plan.compute"
    It "errors on aggressive mode"
      When call plan.compute --mode aggressive
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "aggressive is not implemented"
    End

    It "rejects unknown arguments"
      When call plan.compute --bogus 1
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "unknown argument"
    End

    It "rejects invalid mode"
      When call plan.compute --mode chaotic
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "invalid mode"
    End

    Describe "with a configured referential"
      Before 'mock.infra.setup'
      After 'mock.infra.teardown'

      It "emits header lines and stage records in safe mode"
        When call plan.compute --workspace /tmp --mode safe
        The status should be success
        The output should include "# mode=safe"
        The output should include "# changes_source=none"
        The output should include $'init\trun\tcontext-match'
      End

      It "stamps the referential fingerprint into the stream"
        When call plan.compute --workspace /tmp --mode safe
        The status should be success
        The output should match pattern "*# infra_fingerprint=*"
        The output should include "# infra_fingerprint=$(infra.fingerprint "$BRIK_INFRA_DIR")"
      End
    End

    It "fails closed when no referential is configured"
      unset BRIK_INFRA_DIR BRIK_INFRA_REPO
      When call plan.compute --workspace /tmp --mode safe
      The status should equal "$BRIK_EXIT_INVALID_ENV"
      The stderr should include "no infrastructure referential configured"
    End
  End
End

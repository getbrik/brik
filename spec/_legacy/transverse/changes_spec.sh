Describe "transverse/changes.sh"
  Include "$BRIK_HOME/lib/transverse/changes.sh"

  setup_clean_env() {
    unset CI_COMMIT_SHA CI_COMMIT_BEFORE_SHA CI_MERGE_REQUEST_DIFF_BASE_SHA
    unset GIT_COMMIT GIT_PREVIOUS_COMMIT GIT_PREVIOUS_SUCCESSFUL_COMMIT
    unset BRIK_CHANGES_FROM BRIK_CHANGES_TO
  }
  Before 'setup_clean_env'

  Describe "_changes._resolve_range"
    It "returns 'none' when no CI env, no override, and no main branch reachable"
      When call _changes._resolve_range "$(mktemp -d)"
      The status should be success
      The output should equal "none"
    End

    It "detects GitLab from CI_COMMIT_SHA + CI_COMMIT_BEFORE_SHA"
      export CI_COMMIT_SHA="abc"
      export CI_COMMIT_BEFORE_SHA="def"
      When call _changes._resolve_range
      The status should be success
      The output should equal "gitlab def abc"
    End

    It "ignores GitLab when CI_COMMIT_BEFORE_SHA is all-zero (new branch)"
      export CI_COMMIT_SHA="abc"
      export CI_COMMIT_BEFORE_SHA="0000000000000000000000000000000000000000"
      When call _changes._resolve_range "$(mktemp -d)"
      The status should be success
      The output should equal "none"
    End

    It "prefers MR diff base over CI_COMMIT_BEFORE_SHA"
      export CI_COMMIT_SHA="abc"
      export CI_COMMIT_BEFORE_SHA="def"
      export CI_MERGE_REQUEST_DIFF_BASE_SHA="mrbase"
      When call _changes._resolve_range
      The output should equal "gitlab mrbase abc"
    End

    It "detects Jenkins from GIT_COMMIT + GIT_PREVIOUS_SUCCESSFUL_COMMIT"
      export GIT_COMMIT="head"
      export GIT_PREVIOUS_SUCCESSFUL_COMMIT="prev"
      When call _changes._resolve_range
      The output should equal "jenkins prev head"
    End

    It "uses BRIK_CHANGES_FROM/TO when set locally"
      export BRIK_CHANGES_FROM="main"
      export BRIK_CHANGES_TO="HEAD"
      When call _changes._resolve_range
      The output should equal "local main HEAD"
    End
  End

  Describe "changes.metadata"
    It "outputs tab-separated 'none' record when no diff basis"
      When call changes.metadata "$(mktemp -d)"
      The status should be success
      The output should equal $'none\t\t'
    End
  End

  Describe "changes.diff"
    It "exports BRIK_CHANGES_SOURCE=none on a cold start"
      changes.diff "$(mktemp -d)" >/dev/null
      When call test "$BRIK_CHANGES_SOURCE" = "none"
      The status should be success
    End
  End
End

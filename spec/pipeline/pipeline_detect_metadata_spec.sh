Describe "_pipeline.detect_metadata"
  Include "$BRIK_PIPELINE_LIB/pipeline.sh"

  # _pipeline.detect_metadata reads CI_*/BUILD_*/GIT_* environment variables
  # and exports BRIK_PIPELINE_*/BRIK_COMMIT_*/BRIK_TRIGGERED_BY so the
  # aggregator (and any other consumer) reads a single, normalized source.
  # Pre-set BRIK_* wins (wrappers can override before detection).

  reset_env() {
    unset BRIK_PIPELINE_ID BRIK_PIPELINE_URL
    unset BRIK_COMMIT_SHA BRIK_COMMIT_SHORT_SHA BRIK_COMMIT_REF
    unset BRIK_COMMIT_BRANCH BRIK_COMMIT_TAG
    unset BRIK_TRIGGERED_BY
    unset CI_PIPELINE_ID CI_PIPELINE_URL CI_COMMIT_SHA CI_COMMIT_SHORT_SHA
    unset CI_COMMIT_REF_NAME CI_COMMIT_BRANCH CI_COMMIT_TAG
    unset GITLAB_USER_LOGIN CI_PIPELINE_SOURCE
    unset BUILD_TAG BUILD_NUMBER BUILD_URL
    unset GIT_COMMIT GIT_BRANCH GIT_TAG
    unset BUILD_USER_ID BUILD_CAUSE
  }

  Describe "GitLab platform"
    Before 'reset_env'
    After 'reset_env'

    setup_gitlab() {
      export CI_PIPELINE_ID="42"
      export CI_PIPELINE_URL="https://gitlab.example.com/group/project/-/pipelines/42"
      export CI_COMMIT_SHA="abcdef0123456789abcdef0123456789abcdef01"
      export CI_COMMIT_SHORT_SHA="abcdef01"
      export CI_COMMIT_REF_NAME="feature/x"
      export CI_COMMIT_BRANCH="feature/x"
      export GITLAB_USER_LOGIN="alice"
    }

    It "exports BRIK_PIPELINE_ID from CI_PIPELINE_ID"
      check() { setup_gitlab; _pipeline.detect_metadata; printf '%s' "$BRIK_PIPELINE_ID"; }
      When call check
      The output should equal "42"
    End

    It "exports BRIK_PIPELINE_URL from CI_PIPELINE_URL"
      check() { setup_gitlab; _pipeline.detect_metadata; printf '%s' "$BRIK_PIPELINE_URL"; }
      When call check
      The output should equal "https://gitlab.example.com/group/project/-/pipelines/42"
    End

    It "exports BRIK_COMMIT_SHA from CI_COMMIT_SHA"
      check() { setup_gitlab; _pipeline.detect_metadata; printf '%s' "$BRIK_COMMIT_SHA"; }
      When call check
      The output should equal "abcdef0123456789abcdef0123456789abcdef01"
    End

    It "exports BRIK_COMMIT_SHORT_SHA from CI_COMMIT_SHORT_SHA"
      check() { setup_gitlab; _pipeline.detect_metadata; printf '%s' "$BRIK_COMMIT_SHORT_SHA"; }
      When call check
      The output should equal "abcdef01"
    End

    It "exports BRIK_COMMIT_REF from CI_COMMIT_REF_NAME"
      check() { setup_gitlab; _pipeline.detect_metadata; printf '%s' "$BRIK_COMMIT_REF"; }
      When call check
      The output should equal "feature/x"
    End

    It "exports BRIK_COMMIT_BRANCH from CI_COMMIT_BRANCH"
      check() { setup_gitlab; _pipeline.detect_metadata; printf '%s' "$BRIK_COMMIT_BRANCH"; }
      When call check
      The output should equal "feature/x"
    End

    It "exports BRIK_TRIGGERED_BY from GITLAB_USER_LOGIN"
      check() { setup_gitlab; _pipeline.detect_metadata; printf '%s' "$BRIK_TRIGGERED_BY"; }
      When call check
      The output should equal "alice"
    End

    It "falls back to CI_PIPELINE_SOURCE when GITLAB_USER_LOGIN is unset"
      check() {
        setup_gitlab
        unset GITLAB_USER_LOGIN
        export CI_PIPELINE_SOURCE="schedule"
        _pipeline.detect_metadata
        printf '%s' "$BRIK_TRIGGERED_BY"
      }
      When call check
      The output should equal "schedule"
    End

    It "exports BRIK_COMMIT_TAG from CI_COMMIT_TAG when set"
      check() {
        setup_gitlab
        export CI_COMMIT_TAG="v1.2.3"
        _pipeline.detect_metadata
        printf '%s' "$BRIK_COMMIT_TAG"
      }
      When call check
      The output should equal "v1.2.3"
    End

    It "leaves BRIK_COMMIT_TAG unset when CI_COMMIT_TAG is absent"
      check() {
        setup_gitlab
        _pipeline.detect_metadata
        printf '%s' "${BRIK_COMMIT_TAG:-<unset>}"
      }
      When call check
      The output should equal "<unset>"
    End
  End

  Describe "Jenkins platform"
    Before 'reset_env'
    After 'reset_env'

    setup_jenkins() {
      export BUILD_TAG="jenkins-my-job-17"
      export BUILD_NUMBER="17"
      export BUILD_URL="https://jenkins.example.com/job/my-job/17/"
      export GIT_COMMIT="0123456789abcdef0123456789abcdef01234567"
      export GIT_BRANCH="origin/main"
      export BUILD_USER_ID="bob"
    }

    It "exports BRIK_PIPELINE_ID from BUILD_TAG"
      check() { setup_jenkins; _pipeline.detect_metadata; printf '%s' "$BRIK_PIPELINE_ID"; }
      When call check
      The output should equal "jenkins-my-job-17"
    End

    It "falls back to BUILD_NUMBER for BRIK_PIPELINE_ID when BUILD_TAG is unset"
      check() {
        setup_jenkins
        unset BUILD_TAG
        _pipeline.detect_metadata
        printf '%s' "$BRIK_PIPELINE_ID"
      }
      When call check
      The output should equal "17"
    End

    It "exports BRIK_PIPELINE_URL from BUILD_URL"
      check() { setup_jenkins; _pipeline.detect_metadata; printf '%s' "$BRIK_PIPELINE_URL"; }
      When call check
      The output should equal "https://jenkins.example.com/job/my-job/17/"
    End

    It "exports BRIK_COMMIT_SHA from GIT_COMMIT"
      check() { setup_jenkins; _pipeline.detect_metadata; printf '%s' "$BRIK_COMMIT_SHA"; }
      When call check
      The output should equal "0123456789abcdef0123456789abcdef01234567"
    End

    It "derives BRIK_COMMIT_SHORT_SHA as first 8 chars of GIT_COMMIT when not provided"
      check() { setup_jenkins; _pipeline.detect_metadata; printf '%s' "$BRIK_COMMIT_SHORT_SHA"; }
      When call check
      The output should equal "01234567"
    End

    It "strips 'origin/' prefix when normalizing GIT_BRANCH to BRIK_COMMIT_BRANCH"
      check() { setup_jenkins; _pipeline.detect_metadata; printf '%s' "$BRIK_COMMIT_BRANCH"; }
      When call check
      The output should equal "main"
    End

    It "leaves BRIK_COMMIT_BRANCH unset when GIT_BRANCH is the bare 'origin/' prefix"
      check() {
        export GIT_BRANCH="origin/"
        _pipeline.detect_metadata
        printf '%s' "${BRIK_COMMIT_BRANCH:-<unset>}"
      }
      When call check
      The output should equal "<unset>"
    End

    It "exports BRIK_TRIGGERED_BY from BUILD_USER_ID"
      check() { setup_jenkins; _pipeline.detect_metadata; printf '%s' "$BRIK_TRIGGERED_BY"; }
      When call check
      The output should equal "bob"
    End

    It "falls back to BUILD_CAUSE when BUILD_USER_ID is unset"
      check() {
        setup_jenkins
        unset BUILD_USER_ID
        export BUILD_CAUSE="TimerTrigger"
        _pipeline.detect_metadata
        printf '%s' "$BRIK_TRIGGERED_BY"
      }
      When call check
      The output should equal "TimerTrigger"
    End
  End

  Describe "precedence: pre-set BRIK_* wins"
    Before 'reset_env'
    After 'reset_env'

    It "does not overwrite BRIK_PIPELINE_ID when already set"
      check() {
        export BRIK_PIPELINE_ID="custom-id"
        export CI_PIPELINE_ID="should-not-win"
        _pipeline.detect_metadata
        printf '%s' "$BRIK_PIPELINE_ID"
      }
      When call check
      The output should equal "custom-id"
    End

    It "does not overwrite BRIK_COMMIT_SHA when already set"
      check() {
        export BRIK_COMMIT_SHA="preset-sha"
        export CI_COMMIT_SHA="should-not-win"
        _pipeline.detect_metadata
        printf '%s' "$BRIK_COMMIT_SHA"
      }
      When call check
      The output should equal "preset-sha"
    End

    It "does not overwrite BRIK_TRIGGERED_BY when already set"
      check() {
        export BRIK_TRIGGERED_BY="preset-user"
        export GITLAB_USER_LOGIN="alice"
        _pipeline.detect_metadata
        printf '%s' "$BRIK_TRIGGERED_BY"
      }
      When call check
      The output should equal "preset-user"
    End
  End

  Describe "local fallback (no CI vars)"
    Before 'reset_env'
    After 'reset_env'

    It "leaves BRIK_PIPELINE_URL empty when no CI URL var is set"
      check() {
        _pipeline.detect_metadata
        printf '%s' "${BRIK_PIPELINE_URL:-<empty>}"
      }
      When call check
      The output should equal "<empty>"
    End

    It "leaves BRIK_TRIGGERED_BY empty when no CI user var is set"
      check() {
        _pipeline.detect_metadata
        printf '%s' "${BRIK_TRIGGERED_BY:-<empty>}"
      }
      When call check
      The output should equal "<empty>"
    End
  End
End

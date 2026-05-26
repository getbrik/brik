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
    unset BRIK_COMMIT_AUTHOR BRIK_COMMIT_AUTHOR_EMAIL
    unset BRIK_COMMIT_TIMESTAMP BRIK_COMMIT_MESSAGE_SUBJECT
    unset BRIK_COMMIT_REPO_URL
    unset BRIK_TRIGGERED_BY BRIK_WORKSPACE
    unset CI_PIPELINE_ID CI_PIPELINE_URL CI_COMMIT_SHA CI_COMMIT_SHORT_SHA
    unset CI_COMMIT_REF_NAME CI_COMMIT_BRANCH CI_COMMIT_TAG
    unset CI_COMMIT_AUTHOR CI_COMMIT_TIMESTAMP CI_COMMIT_TITLE
    unset CI_PROJECT_URL GIT_URL
    unset GITLAB_USER_LOGIN CI_PIPELINE_SOURCE
    unset BUILD_TAG BUILD_NUMBER BUILD_URL
    unset GIT_COMMIT GIT_BRANCH GIT_TAG
    unset BUILD_USER_ID BUILD_CAUSE
  }

  Describe "_normalize_remote_url helper"
    It "strips .git suffix from HTTPS URL"
      check() { _pipeline._normalize_remote_url "https://github.com/foo/bar.git"; }
      When call check
      The output should equal "https://github.com/foo/bar"
    End
    It "preserves HTTP scheme and port"
      check() { _pipeline._normalize_remote_url "http://gitea.briklab.test:3000/brik/node-complete.git"; }
      When call check
      The output should equal "http://gitea.briklab.test:3000/brik/node-complete"
    End
    It "strips embedded credentials"
      check() { _pipeline._normalize_remote_url "https://alice:t0k3n@gitlab.example.com/group/project.git"; }
      When call check
      The output should equal "https://gitlab.example.com/group/project"
    End
    It "converts SSH short form to HTTPS"
      check() { _pipeline._normalize_remote_url "git@github.com:foo/bar.git"; }
      When call check
      The output should equal "https://github.com/foo/bar"
    End
    It "converts ssh:// URL form to HTTPS"
      check() { _pipeline._normalize_remote_url "ssh://git@gitea.example.com/foo/bar.git"; }
      When call check
      The output should equal "https://gitea.example.com/foo/bar"
    End
    It "preserves deeply nested GitLab paths"
      check() { _pipeline._normalize_remote_url "git@gitlab.com:group/subgroup/project.git"; }
      When call check
      The output should equal "https://gitlab.com/group/subgroup/project"
    End
    It "returns empty string for empty input"
      check() { _pipeline._normalize_remote_url ""; }
      When call check
      The output should equal ""
    End
    It "passes unknown forms through unchanged"
      check() { _pipeline._normalize_remote_url "weird-not-a-url"; }
      When call check
      The output should equal "weird-not-a-url"
    End
  End

  Describe "BRIK_COMMIT_REPO_URL resolution"
    Before 'reset_env'
    After  'reset_env'

    It "is set from CI_PROJECT_URL when present"
      check() {
        export CI_PROJECT_URL="https://gitlab.com/group/project"
        _pipeline.detect_metadata
        printf '%s' "$BRIK_COMMIT_REPO_URL"
      }
      When call check
      The output should equal "https://gitlab.com/group/project"
    End
    It "is set from GIT_URL when CI_PROJECT_URL is absent"
      check() {
        export GIT_URL="https://github.com/foo/bar.git"
        _pipeline.detect_metadata
        printf '%s' "$BRIK_COMMIT_REPO_URL"
      }
      When call check
      The output should equal "https://github.com/foo/bar"
    End
    It "normalizes credentials out of GIT_URL"
      check() {
        export GIT_URL="https://alice:t0k3n@gitea.example.com/foo/bar.git"
        _pipeline.detect_metadata
        printf '%s' "$BRIK_COMMIT_REPO_URL"
      }
      When call check
      The output should equal "https://gitea.example.com/foo/bar"
    End
    It "prefers a preset BRIK_COMMIT_REPO_URL (wrappers can override)"
      check() {
        export BRIK_COMMIT_REPO_URL="https://override.example/project"
        export CI_PROJECT_URL="https://gitlab.com/group/project"
        _pipeline.detect_metadata
        printf '%s' "$BRIK_COMMIT_REPO_URL"
      }
      When call check
      The output should equal "https://override.example/project"
    End
  End

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

    It "exports BRIK_COMMIT_AUTHOR by parsing CI_COMMIT_AUTHOR Name <email>"
      check() {
        setup_gitlab
        export CI_COMMIT_AUTHOR="Alice Example <alice@example.com>"
        _pipeline.detect_metadata
        printf '%s' "$BRIK_COMMIT_AUTHOR"
      }
      When call check
      The output should equal "Alice Example"
    End

    It "exports BRIK_COMMIT_AUTHOR_EMAIL by parsing CI_COMMIT_AUTHOR Name <email>"
      check() {
        setup_gitlab
        export CI_COMMIT_AUTHOR="Alice Example <alice@example.com>"
        _pipeline.detect_metadata
        printf '%s' "$BRIK_COMMIT_AUTHOR_EMAIL"
      }
      When call check
      The output should equal "alice@example.com"
    End

    It "exports BRIK_COMMIT_TIMESTAMP from CI_COMMIT_TIMESTAMP (normalised offset)"
      # CI_COMMIT_TIMESTAMP arriving with ±HHMM (no colon) is normalised
      # to ±HH:MM so the aggregate report stays byte-identical across
      # platforms. See Normalisation block below for the matrix.
      check() {
        setup_gitlab
        export CI_COMMIT_TIMESTAMP="2026-05-03T18:38:10+0000"
        _pipeline.detect_metadata
        printf '%s' "$BRIK_COMMIT_TIMESTAMP"
      }
      When call check
      The output should equal "2026-05-03T18:38:10+00:00"
    End

    It "exports BRIK_COMMIT_MESSAGE_SUBJECT from CI_COMMIT_TITLE"
      check() {
        setup_gitlab
        export CI_COMMIT_TITLE="feat: add fragment surfacing"
        _pipeline.detect_metadata
        printf '%s' "$BRIK_COMMIT_MESSAGE_SUBJECT"
      }
      When call check
      The output should equal "feat: add fragment surfacing"
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

  Describe "git log fallback (no CI vars, BRIK_WORKSPACE points to a git repo)"
    Before 'reset_env'
    After 'cleanup_git_fixture'

    setup_git_fixture() {
      BRIK_WORKSPACE_FIXTURE="$(mktemp -d)"
      export BRIK_WORKSPACE="$BRIK_WORKSPACE_FIXTURE"
      git -C "$BRIK_WORKSPACE" init -q -b main 2>/dev/null
      git -C "$BRIK_WORKSPACE" config user.email "carol@example.com"
      git -C "$BRIK_WORKSPACE" config user.name "Carol Tester"
      git -C "$BRIK_WORKSPACE" config commit.gpgsign false
      printf 'hello\n' > "$BRIK_WORKSPACE/file.txt"
      git -C "$BRIK_WORKSPACE" add file.txt
      GIT_AUTHOR_DATE="2026-05-04T09:15:30+02:00" \
      GIT_COMMITTER_DATE="2026-05-04T09:15:30+02:00" \
        git -C "$BRIK_WORKSPACE" commit -q -m "fix: regression in detector"
    }

    cleanup_git_fixture() {
      [[ -n "${BRIK_WORKSPACE_FIXTURE:-}" ]] && rm -rf "$BRIK_WORKSPACE_FIXTURE"
      unset BRIK_WORKSPACE_FIXTURE
      reset_env
    }

    It "exports BRIK_COMMIT_AUTHOR from git log when no CI var is set"
      check() {
        setup_git_fixture
        _pipeline.detect_metadata
        printf '%s' "${BRIK_COMMIT_AUTHOR:-<empty>}"
      }
      When call check
      The output should equal "Carol Tester"
    End

    It "exports BRIK_COMMIT_AUTHOR_EMAIL from git log when no CI var is set"
      check() {
        setup_git_fixture
        _pipeline.detect_metadata
        printf '%s' "${BRIK_COMMIT_AUTHOR_EMAIL:-<empty>}"
      }
      When call check
      The output should equal "carol@example.com"
    End

    It "exports BRIK_COMMIT_TIMESTAMP from git log when no CI var is set"
      check() {
        setup_git_fixture
        _pipeline.detect_metadata
        printf '%s' "${BRIK_COMMIT_TIMESTAMP:-<empty>}"
      }
      When call check
      The output should equal "2026-05-04T09:15:30+02:00"
    End

    It "exports BRIK_COMMIT_MESSAGE_SUBJECT from git log subject when no CI var is set"
      check() {
        setup_git_fixture
        _pipeline.detect_metadata
        printf '%s' "${BRIK_COMMIT_MESSAGE_SUBJECT:-<empty>}"
      }
      When call check
      The output should equal "fix: regression in detector"
    End

    It "leaves BRIK_COMMIT_AUTHOR empty when BRIK_WORKSPACE is not a git repo"
      check() {
        BRIK_WORKSPACE_FIXTURE="$(mktemp -d)"
        export BRIK_WORKSPACE="$BRIK_WORKSPACE_FIXTURE"
        _pipeline.detect_metadata
        printf '%s' "${BRIK_COMMIT_AUTHOR:-<empty>}"
      }
      When call check
      The output should equal "<empty>"
    End
  End

  # ---------------------------------------------------------------------------
  # BRIK_COMMIT_TIMESTAMP normalisation (cross-platform parity)
  #
  # Git's --format=%aI prints "Z" in UTC under some versions (and ±HHMM
  # without colon under others); GitLab's CI_COMMIT_TIMESTAMP always uses
  # ±HH:MM. _pipeline.detect_metadata standardises on the colonised
  # numeric offset so the aggregate report is byte-identical on Jenkins,
  # GitLab, and local.
  # ---------------------------------------------------------------------------
  Describe "BRIK_COMMIT_TIMESTAMP normalisation"
    Before 'reset_env'
    After 'reset_env'

    It "rewrites a trailing Z to +00:00"
      check() {
        export BRIK_COMMIT_TIMESTAMP="2026-05-25T11:13:41Z"
        _pipeline.detect_metadata
        printf '%s' "$BRIK_COMMIT_TIMESTAMP"
      }
      When call check
      The output should equal "2026-05-25T11:13:41+00:00"
    End

    It "inserts a colon into a ±HHMM offset"
      check() {
        export BRIK_COMMIT_TIMESTAMP="2026-05-25T11:13:41+0000"
        _pipeline.detect_metadata
        printf '%s' "$BRIK_COMMIT_TIMESTAMP"
      }
      When call check
      The output should equal "2026-05-25T11:13:41+00:00"
    End

    It "inserts a colon into a negative ±HHMM offset"
      check() {
        export BRIK_COMMIT_TIMESTAMP="2026-05-25T11:13:41-0530"
        _pipeline.detect_metadata
        printf '%s' "$BRIK_COMMIT_TIMESTAMP"
      }
      When call check
      The output should equal "2026-05-25T11:13:41-05:30"
    End

    It "leaves a value already in ±HH:MM form untouched"
      check() {
        export BRIK_COMMIT_TIMESTAMP="2026-05-25T13:13:41+02:00"
        _pipeline.detect_metadata
        printf '%s' "$BRIK_COMMIT_TIMESTAMP"
      }
      When call check
      The output should equal "2026-05-25T13:13:41+02:00"
    End

    It "leaves an empty timestamp untouched"
      check() {
        unset BRIK_COMMIT_TIMESTAMP CI_COMMIT_TIMESTAMP
        # Do not point BRIK_WORKSPACE at a repo, so the git log fallback
        # produces nothing and the variable stays empty.
        export BRIK_WORKSPACE="$(mktemp -d)"
        _pipeline.detect_metadata
        printf '%s' "${BRIK_COMMIT_TIMESTAMP:-<empty>}"
      }
      When call check
      The output should equal "<empty>"
    End
  End
End

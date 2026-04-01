Describe "condition.sh (portable condition evaluator)"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"
  Include "$BRIK_HOME/runtime/bash/lib/core/condition.sh"

  # =========================================================================
  # condition.eval - branch conditions (using BRIK_BRANCH)
  # =========================================================================
  Describe "condition.eval"
    Describe "branch == exact match"
      setup_branch_main() { export BRIK_BRANCH="main"; }
      Before 'setup_branch_main'

      It "matches when branch equals value"
        When call condition.eval "branch == 'main'"
        The status should be success
      End

      It "does not match when branch differs"
        When call condition.eval "branch == 'develop'"
        The status should equal 1
      End

      It "matches with double quotes"
        When call condition.eval 'branch == "main"'
        The status should be success
      End
    End

    Describe "branch == with different branch"
      setup_branch_dev() { export BRIK_BRANCH="develop"; }
      Before 'setup_branch_dev'

      It "matches develop"
        When call condition.eval "branch == 'develop'"
        The status should be success
      End

      It "does not match main"
        When call condition.eval "branch == 'main'"
        The status should equal 1
      End
    End

    # =========================================================================
    # condition.eval - tag conditions (using BRIK_TAG)
    # =========================================================================
    Describe "tag == exact match"
      setup_tag_v1() { export BRIK_TAG="v1.0.0"; }
      Before 'setup_tag_v1'

      It "matches exact tag"
        When call condition.eval "tag == 'v1.0.0'"
        The status should be success
      End

      It "does not match different tag"
        When call condition.eval "tag == 'v2.0.0'"
        The status should equal 1
      End
    End

    Describe "tag =~ glob match"
      Describe "with tag v2.3.1"
        setup_tag_v2() { export BRIK_TAG="v2.3.1"; }
        Before 'setup_tag_v2'

        It "matches v* glob"
          When call condition.eval "tag =~ 'v*'"
          The status should be success
        End

        It "matches v2.* glob"
          When call condition.eval "tag =~ 'v2.*'"
          The status should be success
        End
      End

      Describe "with tag release-1.0"
        setup_tag_rel() { export BRIK_TAG="release-1.0"; }
        Before 'setup_tag_rel'

        It "does not match v* glob"
          When call condition.eval "tag =~ 'v*'"
          The status should equal 1
        End

        It "matches release-* glob"
          When call condition.eval "tag =~ 'release-*'"
          The status should be success
        End
      End

      Describe "with no tag set"
        setup_no_tag() { unset BRIK_TAG 2>/dev/null || true; }
        Before 'setup_no_tag'

        It "does not match any tag condition"
          When call condition.eval "tag == 'v1.0.0'"
          The status should equal 1
        End
      End
    End

    # =========================================================================
    # condition.eval - pipeline_source and custom vars
    # =========================================================================
    Describe "pipeline_source through full eval"
      setup_source() { export BRIK_PIPELINE_SOURCE="merge_request_event"; }
      Before 'setup_source'

      It "matches pipeline_source condition"
        When call condition.eval "pipeline_source == 'merge_request_event'"
        The status should be success
      End

      It "does not match different pipeline_source"
        When call condition.eval "pipeline_source == 'push'"
        The status should equal 1
      End
    End

    Describe "custom environment variable through full eval"
      setup_custom() { export MY_DEPLOY_TARGET="production"; }
      Before 'setup_custom'

      It "matches custom var condition"
        When call condition.eval "MY_DEPLOY_TARGET == 'production'"
        The status should be success
      End

      It "does not match different value"
        When call condition.eval "MY_DEPLOY_TARGET == 'staging'"
        The status should equal 1
      End
    End

    # =========================================================================
    # condition.eval - special keywords
    # =========================================================================
    Describe "special keywords"
      It "returns 1 for 'manual'"
        When call condition.eval "manual"
        The status should equal 1
      End
    End

    # =========================================================================
    # condition.eval - whitespace handling
    # =========================================================================
    Describe "whitespace handling"
      setup_branch() { export BRIK_BRANCH="main"; }
      Before 'setup_branch'

      It "trims leading whitespace"
        When call condition.eval "  branch == 'main'"
        The status should be success
      End

      It "trims trailing whitespace"
        When call condition.eval "branch == 'main'  "
        The status should be success
      End

      It "trims both leading and trailing whitespace"
        When call condition.eval "  branch == 'main'  "
        The status should be success
      End
    End

    # =========================================================================
    # condition.eval - error handling
    # =========================================================================
    Describe "error handling"
      It "returns 1 with error for empty expression"
        When call condition.eval ""
        The status should equal 1
        The error should include "empty condition expression"
      End

      It "returns 1 with error for invalid expression syntax"
        When call condition.eval "not a valid expression"
        The status should equal 1
        The error should include "invalid condition expression"
      End

      It "returns 1 with hint for malformed expression"
        When call condition.eval "branch main"
        The status should equal 1
        The error should include "expected format"
      End
    End

    # =========================================================================
    # Negative test: CI_* vars without BRIK_* should not match
    # =========================================================================
    Describe "platform isolation"
      setup_ci_only() {
        unset BRIK_BRANCH 2>/dev/null || true
        export CI_COMMIT_BRANCH="main"
      }
      Before 'setup_ci_only'

      It "does not match when CI_COMMIT_BRANCH is set but BRIK_BRANCH is not"
        When call condition.eval "branch == 'main'"
        The status should equal 1
      End
    End
  End

  # =========================================================================
  # _condition.resolve_subject (using BRIK_* variables)
  # =========================================================================
  Describe "_condition.resolve_subject"
    Describe "branch resolution from BRIK_BRANCH"
      setup_branch() { export BRIK_BRANCH="feature/test"; }
      Before 'setup_branch'

      It "resolves from BRIK_BRANCH"
        When call _condition.resolve_subject "branch"
        The output should equal "feature/test"
      End
    End

    Describe "tag resolution from BRIK_TAG"
      setup_tag() { export BRIK_TAG="v1.0.0"; }
      Before 'setup_tag'

      It "resolves from BRIK_TAG"
        When call _condition.resolve_subject "tag"
        The output should equal "v1.0.0"
      End
    End

    Describe "when all branch vars are unset"
      setup_none() { unset BRIK_BRANCH 2>/dev/null || true; }
      Before 'setup_none'

      It "returns empty when BRIK_BRANCH is unset"
        When call _condition.resolve_subject "branch"
        The output should equal ""
      End
    End

    Describe "pipeline_source"
      setup_source() { export BRIK_PIPELINE_SOURCE="push"; }
      Before 'setup_source'

      It "resolves from BRIK_PIPELINE_SOURCE"
        When call _condition.resolve_subject "pipeline_source"
        The output should equal "push"
      End
    End

    Describe "merge_request"
      setup_mr() { export BRIK_MERGE_REQUEST_ID="42"; }
      Before 'setup_mr'

      It "resolves from BRIK_MERGE_REQUEST_ID"
        When call _condition.resolve_subject "merge_request"
        The output should equal "42"
      End
    End

    Describe "arbitrary env var"
      setup_custom() { export MY_CUSTOM_VAR="hello"; }
      Before 'setup_custom'

      It "resolves via indirect expansion"
        When call _condition.resolve_subject "MY_CUSTOM_VAR"
        The output should equal "hello"
      End
    End

    Describe "unknown subject with no matching env var"
      setup_clean() { unset NONEXISTENT_VAR 2>/dev/null || true; }
      Before 'setup_clean'

      It "returns empty string"
        When call _condition.resolve_subject "NONEXISTENT_VAR"
        The output should equal ""
      End
    End
  End

  # =========================================================================
  # condition.eval_deploy_env
  # =========================================================================
  Describe "condition.eval_deploy_env"
    Describe "with matching deploy condition"
      setup_deploy() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
deploy:
  environments:
    production:
      when: "branch == 'main'"
      target: k8s
    staging:
      when: "tag =~ 'v*'"
      target: k8s
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        export BRIK_BRANCH="main"
        unset BRIK_TAG 2>/dev/null || true
      }
      cleanup() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_deploy'
      After 'cleanup'

      It "returns 0 when condition matches (production on main)"
        When call condition.eval_deploy_env "production"
        The status should be success
      End

      It "returns 1 when condition does not match (staging needs tag)"
        When call condition.eval_deploy_env "staging"
        The status should equal 1
      End
    End

    Describe "with no condition defined for environment"
      setup_no_when() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
deploy:
  environments:
    staging:
      target: k8s
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_no_when'
      After 'cleanup'

      It "returns 1 with warning when no 'when' key"
        When call condition.eval_deploy_env "staging"
        The status should equal 1
        The error should include "no condition defined"
      End
    End

    Describe "with nonexistent environment"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup'

      It "returns 1 for unknown environment"
        When call condition.eval_deploy_env "nonexistent"
        The status should equal 1
        The error should be present
      End
    End
  End
End

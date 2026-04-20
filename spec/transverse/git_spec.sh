Describe "git.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_TRANSVERSE_LIB/git.sh"

  Describe "git.tag"
    It "logs but does not execute in dry-run mode"
      When call git.tag "v1.0.0" --dry-run --message "release"
      The status should be success
      The stderr should include "[dry-run]"
    End

    It "logs push in dry-run mode"
      When call git.tag "v1.0.0" --dry-run --push
      The status should be success
      The stderr should include "[dry-run]"
      The stderr should include "push"
    End

    It "returns 2 for unknown option"
      When call git.tag "v1.0.0" --badopt
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "in a real git repo"
      setup_tag_repo() {
        GIT_DIR="$(mktemp -d)"
        cd "$GIT_DIR" || return 1
        git init -q
        git config user.name "test"
        git config user.email "test@test.com"
        printf 'hello\n' > file.txt
        git add file.txt
        git commit -q -m "initial commit"
        unset BRIK_DRY_RUN
      }
      cleanup_tag_repo() { rm -rf "$GIT_DIR"; cd /tmp || true; }
      Before 'setup_tag_repo'
      After 'cleanup_tag_repo'

      It "creates a lightweight tag"
        verify_tag() {
          git.tag "v2.0.0" 2>/dev/null
          git tag -l "v2.0.0" | grep -q "v2.0.0"
        }
        When call verify_tag
        The status should be success
      End

      It "creates an annotated tag with --message"
        verify_annotated() {
          git.tag "v3.0.0" --message "Release 3.0" 2>/dev/null
          git tag -l "v3.0.0" | grep -q "v3.0.0"
          # Verify it's annotated
          git cat-file -t "v3.0.0" | grep -q "tag"
        }
        When call verify_annotated
        The status should be success
      End

      It "logs success message"
        When call git.tag "v4.0.0"
        The status should be success
        The stderr should include "tag created: v4.0.0"
      End
    End
  End

End

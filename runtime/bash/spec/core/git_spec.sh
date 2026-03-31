Describe "git.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/git.sh"

  Describe "git.configure"
    It "returns 0 in dry-run mode"
      export BRIK_DRY_RUN=true
      When call git.configure --name "Test User" --email "test@test.com"
      The status should be success
      The stderr should include "[dry-run]"
      unset BRIK_DRY_RUN
    End

    It "returns 2 for unknown option"
      When call git.configure --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "non-dry-run in real git repo"
      setup_repo() {
        GIT_DIR="$(mktemp -d)"
        cd "$GIT_DIR" || return 1
        git init -q
        git config user.name "original"
        git config user.email "original@test.com"
        unset BRIK_DRY_RUN
      }
      cleanup_repo() { rm -rf "$GIT_DIR"; cd /tmp || true; }
      Before 'setup_repo'
      After 'cleanup_repo'

      It "sets git user.name"
        verify_name() {
          git.configure --name "Brik CI" 2>/dev/null
          local actual
          actual="$(git config user.name)"
          [[ "$actual" == "Brik CI" ]]
        }
        When call verify_name
        The status should be success
      End

      It "sets git user.email"
        verify_email() {
          git.configure --email "ci@brik.dev" 2>/dev/null
          local actual
          actual="$(git config user.email)"
          [[ "$actual" == "ci@brik.dev" ]]
        }
        When call verify_email
        The status should be success
      End

      It "is idempotent (second call succeeds)"
        verify_idempotent() {
          git.configure --name "Brik CI" --email "ci@brik.dev" 2>/dev/null
          git.configure --name "Brik CI" --email "ci@brik.dev" 2>/dev/null
        }
        When call verify_idempotent
        The status should be success
      End
    End
  End

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

  Describe "git.info"
    Describe "in a git repo"
      setup_repo() {
        GIT_DIR="$(mktemp -d)"
        cd "$GIT_DIR" || return 1
        git init -q
        git config user.name "test"
        git config user.email "test@test.com"
        printf 'hello\n' > file.txt
        git add file.txt
        git commit -q -m "initial commit"
      }
      cleanup_repo() { rm -rf "$GIT_DIR"; cd /tmp || true; }
      Before 'setup_repo'
      After 'cleanup_repo'

      It "outputs valid JSON with correct author"
        verify_author() {
          local json
          json="$(git.info 2>/dev/null)"
          local author
          author="$(printf '%s' "$json" | jq -r '.author')"
          [[ "$author" == "test" ]]
        }
        When call verify_author
        The status should be success
      End

      It "outputs correct commit message"
        verify_message() {
          local json
          json="$(git.info 2>/dev/null)"
          local msg
          msg="$(printf '%s' "$json" | jq -r '.message')"
          [[ "$msg" == "initial commit" ]]
        }
        When call verify_message
        The status should be success
      End

      It "outputs a non-empty sha"
        verify_sha() {
          local json
          json="$(git.info 2>/dev/null)"
          local sha
          sha="$(printf '%s' "$json" | jq -r '.sha')"
          [[ -n "$sha" && ${#sha} -eq 40 ]]
        }
        When call verify_sha
        The status should be success
      End

      It "includes branch name"
        When call git.info
        The status should be success
        The output should include '"branch"'
      End

      It "includes timestamp field"
        When call git.info
        The output should include '"timestamp"'
      End
    End
  End
End

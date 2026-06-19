Describe "git.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_TRANSVERSE_LIB/git.sh"

  # Shared repo fixture for the enrich suite (commit_all / clone_shallow /
  # push_branch / latest_tag / current_branch / short_sha).
  setup_enrich_repo() {
    GIT_DIR="$(mktemp -d)"
    cd "$GIT_DIR" || return 1
    git init -q -b main
    git config user.name "test"
    git config user.email "test@test.com"
    printf 'hello\n' > file.txt
    git add file.txt
    git commit -q -m "initial commit"
    unset BRIK_DRY_RUN
  }
  cleanup_enrich_repo() { rm -rf "$GIT_DIR"; cd /tmp || true; }

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

      It "is idempotent when tag already exists at HEAD"
        verify_idempotent() {
          git.tag "v5.0.0" 2>/dev/null
          # Re-running on the same commit should succeed without error
          git.tag "v5.0.0"
        }
        When call verify_idempotent
        The status should be success
        The stderr should include "already at HEAD"
      End

      It "fails when tag exists on a different commit"
        verify_divergent() {
          git.tag "v6.0.0" 2>/dev/null
          # Create a new commit so HEAD diverges from the tagged commit
          printf 'second\n' > file2.txt
          git add file2.txt
          git commit -q -m "second commit"
          # Tag still points to the first commit -> must refuse
          git.tag "v6.0.0"
        }
        When call verify_divergent
        The status should equal "$BRIK_EXIT_EXTERNAL_FAIL"
        The stderr should include "different commit"
      End

      It "pushes existing tag idempotently when --push is given"
        verify_idempotent_push() {
          # Create a local bare repo as a fake origin
          remote_dir="$(mktemp -d)"
          (cd "$remote_dir" && git init -q --bare) >/dev/null
          git remote add origin "$remote_dir"
          git.tag "v7.0.0" 2>/dev/null
          # Run again with --push: tag already exists at HEAD, should push without re-creating
          git.tag "v7.0.0" --push
          rm -rf "$remote_dir"
        }
        When call verify_idempotent_push
        The status should be success
        The stderr should include "already at HEAD"
      End

      It "fails when pushing a newly created tag with no origin"
        # Exercises the new-tag push branch (68-70): tag is created but
        # 'git push origin' fails because no 'origin' remote exists.
        When call git.tag "v8.0.0" --push
        The status should equal "$BRIK_EXIT_EXTERNAL_FAIL"
        The stderr should include "failed to push tag"
      End

      It "fails when pushing an existing-at-HEAD tag with no origin"
        # Exercises the existing-tag push failure branch (44-46): tag already
        # at HEAD, --push given, but the push fails (no origin remote).
        verify_existing_push_fail() {
          git.tag "v9.0.0" 2>/dev/null
          git.tag "v9.0.0" --push
        }
        When call verify_existing_push_fail
        The status should equal "$BRIK_EXIT_EXTERNAL_FAIL"
        The stderr should include "failed to push existing tag"
      End
    End
  End

  Describe "transverse.git.config_identity"
    setup_identity_repo() {
      GIT_DIR="$(mktemp -d)"
      cd "$GIT_DIR" || return 1
      git init -q
      # Use a sandbox HOME so we never touch the host ~/.gitconfig.
      # spec_helper.sh sets GIT_CONFIG_GLOBAL=/dev/null globally to isolate
      # tests from the developer's gpgsign config, but this test exercises
      # 'git config --global' which must write to a real file -- restore
      # HOME-based discovery by unsetting the override.
      unset GIT_CONFIG_GLOBAL
      export HOME="$GIT_DIR"
      unset BRIK_GIT_USER_EMAIL BRIK_GIT_USER_NAME
    }
    cleanup_identity_repo() {
      rm -rf "$GIT_DIR"
      cd /tmp || true
      unset HOME
      # Restore the spec_helper isolation default.
      export GIT_CONFIG_GLOBAL=/dev/null
    }
    Before 'setup_identity_repo'
    After 'cleanup_identity_repo'

    It "applies email and name from BRIK_GIT_USER_*"
      run_apply() {
        export BRIK_GIT_USER_EMAIL="release-bot@example.com"
        export BRIK_GIT_USER_NAME="Release Bot"
        transverse.git.config_identity
        git config --global --get user.email
        git config --global --get user.name
      }
      When call run_apply
      The status should be success
      The output should include "release-bot@example.com"
      The output should include "Release Bot"
    End

    It "warns and returns 0 when both env vars are empty"
      run_empty() {
        unset BRIK_GIT_USER_EMAIL BRIK_GIT_USER_NAME
        transverse.git.config_identity
      }
      When call run_empty
      The status should be success
      The stderr should include "no git identity configured"
    End

    It "applies email only when name is empty"
      run_email_only() {
        export BRIK_GIT_USER_EMAIL="ci@example.com"
        unset BRIK_GIT_USER_NAME
        transverse.git.config_identity
        git config --global --get user.email
        git config --global --get user.name 2>&1 || echo "name-not-set"
      }
      When call run_email_only
      The status should be success
      The output should include "ci@example.com"
      The output should include "name-not-set"
    End
  End

  Describe "transverse.git.commit_all"
    Before 'setup_enrich_repo'
    After 'cleanup_enrich_repo'

    It "stages all changes and commits with the given message"
      run_commit() {
        printf 'new\n' > added.txt
        transverse.git.commit_all "add new file" 2>/dev/null
        git log --oneline -1
      }
      When call run_commit
      The status should be success
      The output should include "add new file"
    End

    It "returns 0 and logs skip when there is nothing to commit"
      run_commit_empty() {
        transverse.git.commit_all "noop"
      }
      When call run_commit_empty
      The status should be success
      The stderr should include "no changes"
    End

    It "accepts -C <dir> to commit in a different directory"
      run_commit_dir() {
        local subrepo="$(mktemp -d)"
        git -C "$subrepo" init -q -b main
        git -C "$subrepo" config user.email "ci@brik.local"
        git -C "$subrepo" config user.name "brik ci"
        printf 'x\n' > "$subrepo/x.txt"
        transverse.git.commit_all "x added" -C "$subrepo" 2>/dev/null
        git -C "$subrepo" log --oneline -1
        rm -rf "$subrepo"
      }
      When call run_commit_dir
      The status should be success
      The output should include "x added"
    End

    It "accepts --email and --name for committer identity"
      run_commit_identity() {
        local subrepo="$(mktemp -d)"
        git -C "$subrepo" init -q -b main
        printf 'y\n' > "$subrepo/y.txt"
        transverse.git.commit_all "id-test" -C "$subrepo" \
          --email "ci@noreply" --name "CI Bot" 2>/dev/null
        git -C "$subrepo" log -1 --format='%an <%ae>'
        rm -rf "$subrepo"
      }
      When call run_commit_identity
      The status should be success
      The output should include "CI Bot <ci@noreply>"
    End

    It "returns 2 for an unknown option"
      # Exercises the unknown-option branch (130-131).
      When call transverse.git.commit_all "msg" --badopt
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "unknown option"
    End

    It "fails on a clean tree with --fail-if-empty"
      # Exercises the fail-if-empty branch (145-146): clean tree + flag.
      When call transverse.git.commit_all "noop" --fail-if-empty
      The status should equal "$BRIK_EXIT_EXTERNAL_FAIL"
      The stderr should include "no changes"
    End
  End

  Describe "transverse.git.clone_shallow"
    It "clones with depth 1 by default"
      run_clone_default() {
        local origin="$(mktemp -d)"
        git -C "$origin" init -q -b main
        git -C "$origin" config user.email ci@brik.local
        git -C "$origin" config user.name ci
        printf 'x\n' > "$origin/a.txt"
        git -C "$origin" add a.txt
        git -C "$origin" commit -q -m "a"
        printf 'y\n' > "$origin/a.txt"
        git -C "$origin" add a.txt
        git -C "$origin" commit -q -m "b"
        local dest="$(mktemp -d)"
        rm -rf "$dest"
        transverse.git.clone_shallow "file://$origin" "$dest" --branch main 2>/dev/null
        git -C "$dest" log --oneline | wc -l | tr -d '[:space:]'
        rm -rf "$origin" "$dest"
      }
      When call run_clone_default
      The status should be success
      The output should equal "1"
    End

    It "clones with --depth N when specified"
      run_clone_depth() {
        local origin="$(mktemp -d)"
        git -C "$origin" init -q -b main
        git -C "$origin" config user.email ci@brik.local
        git -C "$origin" config user.name ci
        for i in 1 2 3; do
          printf '%s\n' "$i" > "$origin/a.txt"
          git -C "$origin" add a.txt
          git -C "$origin" commit -q -m "c$i"
        done
        local dest="$(mktemp -d)"
        rm -rf "$dest"
        transverse.git.clone_shallow "file://$origin" "$dest" --branch main --depth 2 2>/dev/null
        git -C "$dest" log --oneline | wc -l | tr -d '[:space:]'
        rm -rf "$origin" "$dest"
      }
      When call run_clone_depth
      The status should be success
      The output should equal "2"
    End

    It "returns non-zero on clone failure"
      When call transverse.git.clone_shallow "/nonexistent/path" "/tmp/brik-csh-$$" --branch main
      The status should not be success
      The stderr should include "git clone failed"
    End

    It "returns 2 for an unknown option"
      # Exercises the unknown-option branch (178).
      When call transverse.git.clone_shallow "file:///x" "/tmp/brik-csh2-$$" --badopt
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "unknown option"
    End
  End

  Describe "transverse.git.push_branch"
    setup_push_repo() {
      REMOTE_DIR="$(mktemp -d)"
      git -C "$REMOTE_DIR" init -q --bare -b main
      setup_enrich_repo
      git remote add origin "$REMOTE_DIR"
      git push -q -u origin main
    }
    cleanup_push_repo() { rm -rf "$REMOTE_DIR"; cleanup_enrich_repo; }
    Before 'setup_push_repo'
    After 'cleanup_push_repo'

    It "pushes current branch to origin"
      run_push() {
        printf 'more\n' >> file.txt
        git add file.txt
        git commit -q -m "more"
        transverse.git.push_branch 2>/dev/null
        git -C "$REMOTE_DIR" log --oneline -1
      }
      When call run_push
      The status should be success
      The output should include "more"
    End

    It "accepts -C <dir> to push from another directory"
      run_push_dir() {
        printf 'z\n' >> file.txt
        git add file.txt
        git commit -q -m "z added"
        ( cd /tmp && transverse.git.push_branch -C "$GIT_DIR" 2>/dev/null )
        git -C "$REMOTE_DIR" log --oneline -1
      }
      When call run_push_dir
      The status should be success
      The output should include "z added"
    End

    It "logs and does not push in --dry-run mode"
      When call transverse.git.push_branch --dry-run
      The status should be success
      The stderr should include "[dry-run]"
    End

    It "pushes an explicitly named branch to origin"
      # Exercises the explicit-branch branch (222): push_cmd += origin <branch>.
      run_push_named() {
        printf 'named\n' >> file.txt
        git add file.txt
        git commit -q -m "named change"
        transverse.git.push_branch main 2>/dev/null
        git -C "$REMOTE_DIR" log --oneline -1
      }
      When call run_push_named
      The status should be success
      The output should include "named change"
    End
  End

  Describe "transverse.git.push_branch (error and arg paths)"
    Before 'setup_enrich_repo'
    After 'cleanup_enrich_repo'

    It "returns 2 for an unknown dashed option"
      # Exercises the -* unknown-option branch (206-207).
      When call transverse.git.push_branch --badopt
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "unknown option"
    End

    It "redacts credentials and fails when push fails"
      # Exercises the failure branch (229-232) including the sed credential
      # redaction: there is no 'origin' remote so the push fails.
      run_push_fail() {
        git remote add origin "https://user:secret@example.invalid/repo.git"
        transverse.git.push_branch
      }
      When call run_push_fail
      The status should equal "$BRIK_EXIT_EXTERNAL_FAIL"
      The stderr should include "git push failed"
      The stderr should not include "secret"
    End

    It "stops option parsing at -- and treats the rest as a branch"
      # Exercises the '--' terminator branch (205): after '--', 'main' is
      # consumed as the positional branch name.
      run_push_terminator() {
        REMOTE_DIR="$(mktemp -d)"
        git -C "$REMOTE_DIR" init -q --bare -b main
        git remote add origin "$REMOTE_DIR"
        git push -q -u origin main
        printf 'term\n' >> file.txt
        git add file.txt
        git commit -q -m "term change"
        transverse.git.push_branch -- main 2>/dev/null
        git -C "$REMOTE_DIR" log --oneline -1
        rm -rf "$REMOTE_DIR"
      }
      When call run_push_terminator
      The status should be success
      The output should include "term change"
    End
  End

  Describe "transverse.git.latest_tag"
    Before 'setup_enrich_repo'
    After 'cleanup_enrich_repo'

    It "returns the most recent annotated tag"
      run_latest() {
        git tag -a v1.0.0 -m "r1"
        printf 'a\n' >> file.txt
        git add file.txt
        git commit -q -m "b"
        git tag -a v2.0.0 -m "r2"
        transverse.git.latest_tag
      }
      When call run_latest
      The status should be success
      The output should equal "v2.0.0"
    End

    It "returns the most recent tag matching --pattern"
      run_latest_pattern() {
        git -c tag.gpgsign=false -c tag.forceSignAnnotated=false tag v1.0.0
        printf 'a\n' >> file.txt
        git add file.txt
        git commit -q -m "b"
        git -c tag.gpgsign=false -c tag.forceSignAnnotated=false tag rc-5
        printf 'b\n' >> file.txt
        git add file.txt
        git commit -q -m "c"
        git -c tag.gpgsign=false -c tag.forceSignAnnotated=false tag v1.1.0
        transverse.git.latest_tag --pattern "v*"
      }
      When call run_latest_pattern
      The status should be success
      The output should equal "v1.1.0"
    End

    It "returns non-zero when there are no tags"
      When call transverse.git.latest_tag
      The status should not be success
    End

    It "returns 2 for an unknown option"
      # Exercises the unknown-option branch (248).
      When call transverse.git.latest_tag --badopt
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "unknown option"
    End
  End

  Describe "transverse.git.worktree_at / worktree_remove"
    Before 'setup_enrich_repo'
    After 'cleanup_enrich_repo'

    It "materializes a ref into a detached worktree and removes it"
      # Exercises worktree_at success (289-290) + worktree_remove (300-304).
      run_worktree() {
        local wt
        wt="$(transverse.git.worktree_at "$GIT_DIR" HEAD)"
        # The worktree path must exist and contain the committed file.
        [[ -f "$wt/file.txt" ]] && printf 'present\n'
        transverse.git.worktree_remove "$GIT_DIR" "$wt"
        # After removal the parent temp dir must be gone.
        [[ ! -d "$wt" ]] && printf 'removed\n'
      }
      When call run_worktree
      The status should be success
      The output should include "present"
      The output should include "removed"
    End

    It "worktree_remove is a no-op for an empty path"
      # Exercises the empty-path early return (301).
      When call transverse.git.worktree_remove "$GIT_DIR" ""
      The status should be success
    End

    It "worktree_at returns non-zero for an invalid ref"
      # Exercises the failure path (292-293): rm -rf parent + external-fail.
      When call transverse.git.worktree_at "$GIT_DIR" "does-not-exist-ref"
      The status should equal "$BRIK_EXIT_EXTERNAL_FAIL"
    End
  End

  Describe "transverse.git.current_branch"
    Before 'setup_enrich_repo'
    After 'cleanup_enrich_repo'

    It "returns the current branch name"
      When call transverse.git.current_branch
      The status should be success
      The output should equal "main"
    End

    It "returns the new name after a checkout -b"
      run_current() {
        git checkout -q -b feature/x
        transverse.git.current_branch
      }
      When call run_current
      The status should be success
      The output should equal "feature/x"
    End
  End

  Describe "transverse.git.short_sha"
    Before 'setup_enrich_repo'
    After 'cleanup_enrich_repo'

    It "returns the short SHA of HEAD by default"
      run_short() {
        transverse.git.short_sha
      }
      When call run_short
      The status should be success
      The length of output should equal 7
    End

    It "returns the short SHA of a given ref"
      run_short_ref() {
        local full_sha
        full_sha="$(git rev-parse HEAD)"
        transverse.git.short_sha "$full_sha"
      }
      When call run_short_ref
      The status should be success
      The length of output should equal 7
    End
  End

End

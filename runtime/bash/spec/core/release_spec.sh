Describe "release.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/version.sh"
  Include "$BRIK_CORE_LIB/git.sh"
  Include "$BRIK_CORE_LIB/changelog.sh"
  Include "$BRIK_CORE_LIB/release.sh"

  Describe "release.prepare"
    It "returns 2 when version is empty"
      When call release.prepare ""
      The status should equal 2
      The stderr should include "version is required"
    End

    It "returns 2 for invalid semver"
      When call release.prepare "not-a-version"
      The status should equal 2
      The stderr should include "invalid semver"
    End

    It "returns 2 for unknown option"
      When call release.prepare "1.0.0" --badopt
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "dry-run mode"
      setup_dryrun() {
        TEST_REPO="$(mktemp -d)"
        ORIG_DIR="$(pwd)"
        cd "$TEST_REPO" || return 1
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        printf '{"name":"test","version":"0.9.0"}\n' > package.json
        git add package.json && git commit -q -m "chore: init"
      }
      cleanup_dryrun() {
        cd "$ORIG_DIR" || true
        rm -rf "$TEST_REPO"
      }
      Before 'setup_dryrun'
      After 'cleanup_dryrun'

      It "does not modify files in dry-run"
        invoke_dryrun() {
          release.prepare "1.0.0" --dry-run 2>/dev/null || return 1
          # package.json should still have old version
          grep -q '"0.9.0"' package.json
        }
        When call invoke_dryrun
        The status should be success
      End

      It "logs dry-run messages"
        When call release.prepare "1.0.0" --dry-run
        The status should be success
        The stderr should include "[dry-run]"
      End

      It "logs dry-run changelog message when --changelog"
        When call release.prepare "1.0.0" --changelog --dry-run
        The status should be success
        The stderr should include "[dry-run] changelog.generate"
      End
    End

    Describe "with real git repo"
      setup_repo() {
        TEST_REPO="$(mktemp -d)"
        ORIG_DIR="$(pwd)"
        cd "$TEST_REPO" || return 1
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        printf '{"name":"test","version":"0.9.0"}\n' > package.json
        git add package.json && git commit -q -m "chore: init"
      }
      cleanup_repo() {
        cd "$ORIG_DIR" || true
        rm -rf "$TEST_REPO"
      }
      Before 'setup_repo'
      After 'cleanup_repo'

      It "writes version and creates commit"
        invoke_prepare() {
          release.prepare "1.0.0" 2>/dev/null || return 1
          # Check version was written
          grep -q '"1.0.0"' package.json || return 1
          # Check commit was created
          git log -1 --format='%s' | grep -q "release: 1.0.0"
        }
        When call invoke_prepare
        The status should be success
      End
    End

    Describe "with changelog generation"
      setup_changelog() {
        TEST_REPO="$(mktemp -d)"
        ORIG_DIR="$(pwd)"
        cd "$TEST_REPO" || return 1
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        printf '{"name":"test","version":"0.9.0"}\n' > package.json
        git add package.json && git commit -q -m "chore: init"
        git tag v0.9.0
        printf 'feature\n' > feature.txt
        git add feature.txt && git commit -q -m "feat: add feature"
      }
      cleanup_changelog() {
        cd "$ORIG_DIR" || true
        rm -rf "$TEST_REPO"
      }
      Before 'setup_changelog'
      After 'cleanup_changelog'

      It "creates CHANGELOG.md when --changelog is set"
        invoke_changelog() {
          release.prepare "1.0.0" --changelog 2>/dev/null || return 1
          [[ -f "CHANGELOG.md" ]] && grep -q "Features" CHANGELOG.md
        }
        When call invoke_changelog
        The status should be success
      End

      It "uses custom changelog file"
        invoke_custom_file() {
          release.prepare "1.0.0" --changelog --changelog-file "CHANGES.md" 2>/dev/null || return 1
          [[ -f "CHANGES.md" ]] && grep -q "Features" CHANGES.md
        }
        When call invoke_custom_file
        The status should be success
      End
    End
  End

  Describe "release.finalize"
    It "returns 2 when version is empty"
      When call release.finalize ""
      The status should equal 2
      The stderr should include "version is required"
    End

    Describe "with real git repo"
      setup_repo() {
        TEST_REPO="$(mktemp -d)"
        ORIG_DIR="$(pwd)"
        cd "$TEST_REPO" || return 1
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        printf 'init\n' > README.md
        git add README.md && git commit -q -m "chore: init"
      }
      cleanup_repo() {
        cd "$ORIG_DIR" || true
        rm -rf "$TEST_REPO"
      }
      Before 'setup_repo'
      After 'cleanup_repo'

      It "creates an annotated tag"
        invoke_finalize() {
          release.finalize "1.0.0" 2>/dev/null || return 1
          git tag -l | grep -q "v1.0.0"
        }
        When call invoke_finalize
        The status should be success
      End

      It "uses custom tag prefix"
        invoke_prefix() {
          release.finalize "2.0.0" --tag-prefix "release-" 2>/dev/null || return 1
          git tag -l | grep -q "release-2.0.0"
        }
        When call invoke_prefix
        The status should be success
      End

      It "uses dry-run mode"
        invoke_dryrun() {
          release.finalize "3.0.0" --dry-run 2>/dev/null || return 1
          # Tag should NOT exist
          ! git tag -l | grep -q "v3.0.0"
        }
        When call invoke_dryrun
        The status should be success
      End
    End
  End
End

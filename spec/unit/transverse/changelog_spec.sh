Describe "changelog.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_TRANSVERSE_LIB/git.sh"
  Include "$BRIK_TRANSVERSE_LIB/changelog.sh"

  # Stub brik.use: transverse.git is already Included above, so the runtime
  # loader call from changelog.generate becomes a no-op.
  brik.use() { :; }

  Describe "changelog.generate"
    It "returns 2 for unknown option"
      When call changelog.generate --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "with git repo"
      setup_repo() {
        TEST_REPO="$(mktemp -d)"
        ORIG_DIR="$(pwd)"
        cd "$TEST_REPO" || return 1
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        printf 'init\n' > README.md
        git add README.md && git commit -q -m "chore: initial commit"
        git -c tag.gpgsign=false -c tag.forceSignAnnotated=false tag v0.1.0
        printf 'feature\n' >> README.md
        git add README.md && git commit -q -m "feat: add login page"
        printf 'fix\n' >> README.md
        git add README.md && git commit -q -m "fix: correct typo in header"
        printf 'refactor\n' >> README.md
        git add README.md && git commit -q -m "refactor: simplify auth flow"
      }
      cleanup_repo() {
        cd "$ORIG_DIR" || true
        rm -rf "$TEST_REPO"
      }
      Before 'setup_repo'
      After 'cleanup_repo'

      It "generates markdown with Features section"
        When call changelog.generate --from v0.1.0
        The status should be success
        The output should include "### Features"
        The output should include "add login page"
      End

      It "generates markdown with Bug Fixes section"
        When call changelog.generate --from v0.1.0
        The output should include "### Bug Fixes"
        The output should include "correct typo in header"
      End

      It "generates markdown with Refactoring section"
        When call changelog.generate --from v0.1.0
        The output should include "### Refactoring"
        The output should include "simplify auth flow"
      End

      It "includes short SHA in entries"
        When call changelog.generate --from v0.1.0
        The output should match pattern "*(*)*"
      End

      It "auto-detects from ref as latest tag"
        When call changelog.generate
        The status should be success
        The output should include "### Features"
      End
    End

    Describe "with non-conventional commits"
      setup_mixed() {
        TEST_REPO="$(mktemp -d)"
        ORIG_DIR="$(pwd)"
        cd "$TEST_REPO" || return 1
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        printf 'init\n' > README.md
        git add README.md && git commit -q -m "initial commit"
        git -c tag.gpgsign=false -c tag.forceSignAnnotated=false tag v0.0.1
        printf 'x\n' >> README.md
        git add README.md && git commit -q -m "update readme"
        printf 'y\n' >> README.md
        git add README.md && git commit -q -m "feat: add dashboard"
      }
      cleanup_mixed() {
        cd "$ORIG_DIR" || true
        rm -rf "$TEST_REPO"
      }
      Before 'setup_mixed'
      After 'cleanup_mixed'

      It "puts non-conforming commits in Other Changes"
        When call changelog.generate --from v0.0.1
        The output should include "### Other Changes"
        The output should include "update readme"
      End

      It "still includes conventional commits"
        When call changelog.generate --from v0.0.1
        The output should include "### Features"
        The output should include "add dashboard"
      End
    End

    Describe "with breaking changes"
      setup_breaking() {
        TEST_REPO="$(mktemp -d)"
        ORIG_DIR="$(pwd)"
        cd "$TEST_REPO" || return 1
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        printf 'init\n' > README.md
        git add README.md && git commit -q -m "chore: init"
        git -c tag.gpgsign=false -c tag.forceSignAnnotated=false tag v1.0.0
        printf 'x\n' >> README.md
        git add README.md && git commit -q -m "feat!: change API format"
      }
      cleanup_breaking() {
        cd "$ORIG_DIR" || true
        rm -rf "$TEST_REPO"
      }
      Before 'setup_breaking'
      After 'cleanup_breaking'

      It "includes BREAKING CHANGES section"
        When call changelog.generate --from v1.0.0
        The output should include "### BREAKING CHANGES"
        The output should include "change API format"
      End
    End

    Describe "with empty range"
      setup_empty() {
        TEST_REPO="$(mktemp -d)"
        ORIG_DIR="$(pwd)"
        cd "$TEST_REPO" || return 1
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        printf 'init\n' > README.md
        git add README.md && git commit -q -m "chore: init"
        git -c tag.gpgsign=false -c tag.forceSignAnnotated=false tag v1.0.0
      }
      cleanup_empty() {
        cd "$ORIG_DIR" || true
        rm -rf "$TEST_REPO"
      }
      Before 'setup_empty'
      After 'cleanup_empty'

      It "outputs 'No changes' message"
        invoke_empty() {
          changelog.generate --from v1.0.0 2>/dev/null
        }
        When call invoke_empty
        The status should be success
        The output should include "No changes"
      End
    End

    Describe "no tags in repo"
      setup_notags() {
        TEST_REPO="$(mktemp -d)"
        ORIG_DIR="$(pwd)"
        cd "$TEST_REPO" || return 1
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        printf 'init\n' > README.md
        git add README.md && git commit -q -m "feat: initial feature"
      }
      cleanup_notags() {
        cd "$ORIG_DIR" || true
        rm -rf "$TEST_REPO"
      }
      Before 'setup_notags'
      After 'cleanup_notags'

      It "falls back to initial commit when no tags"
        invoke_notags() {
          changelog.generate 2>/dev/null
        }
        When call invoke_notags
        The status should be success
        The output should include "## Changes"
      End
    End

    Describe "with all commit types"
      setup_all_types() {
        TEST_REPO="$(mktemp -d)"
        ORIG_DIR="$(pwd)"
        cd "$TEST_REPO" || return 1
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        printf 'init\n' > README.md
        git add README.md && git commit -q -m "chore: init"
        git -c tag.gpgsign=false -c tag.forceSignAnnotated=false tag v0.0.1
        for type in perf ci style build revert docs test chore; do
          printf '%s\n' "$type" >> README.md
          git add README.md && git commit -q -m "${type}: ${type} change"
        done
      }
      cleanup_all_types() {
        cd "$ORIG_DIR" || true
        rm -rf "$TEST_REPO"
      }
      Before 'setup_all_types'
      After 'cleanup_all_types'

      It "groups perf commits"
        When call changelog.generate --from v0.0.1
        The output should include "### Performance"
      End

      It "groups ci commits"
        When call changelog.generate --from v0.0.1
        The output should include "### CI"
      End

      It "groups style commits"
        When call changelog.generate --from v0.0.1
        The output should include "### Style"
      End

      It "groups build commits"
        When call changelog.generate --from v0.0.1
        The output should include "### Build"
      End

      It "groups revert commits"
        When call changelog.generate --from v0.0.1
        The output should include "### Reverts"
      End

      It "groups docs commits"
        When call changelog.generate --from v0.0.1
        The output should include "### Documentation"
      End

      It "groups test commits"
        When call changelog.generate --from v0.0.1
        The output should include "### Tests"
      End

      It "groups chore commits"
        When call changelog.generate --from v0.0.1
        The output should include "### Chores"
      End
    End

    Describe "with --to parameter"
      setup_to() {
        TEST_REPO="$(mktemp -d)"
        ORIG_DIR="$(pwd)"
        cd "$TEST_REPO" || return 1
        git init -q
        git config user.email "test@test.com"
        git config user.name "Test"
        printf 'init\n' > README.md
        git add README.md && git commit -q -m "chore: init"
        git -c tag.gpgsign=false -c tag.forceSignAnnotated=false tag v1.0.0
        printf 'a\n' >> README.md
        git add README.md && git commit -q -m "feat: feature a"
        git -c tag.gpgsign=false -c tag.forceSignAnnotated=false tag v1.1.0
        printf 'b\n' >> README.md
        git add README.md && git commit -q -m "feat: feature b"
      }
      cleanup_to() {
        cd "$ORIG_DIR" || true
        rm -rf "$TEST_REPO"
      }
      Before 'setup_to'
      After 'cleanup_to'

      It "respects --to parameter"
        invoke_to() {
          changelog.generate --from v1.0.0 --to v1.1.0 2>/dev/null
        }
        When call invoke_to
        The output should include "feature a"
        The output should not include "feature b"
      End
    End
  End

  Describe "_changelog._type_label"
    It "returns Features for feat"
      When call _changelog._type_label feat
      The output should equal "Features"
    End

    It "returns Bug Fixes for fix"
      When call _changelog._type_label fix
      The output should equal "Bug Fixes"
    End

    It "returns Refactoring for refactor"
      When call _changelog._type_label refactor
      The output should equal "Refactoring"
    End

    It "returns Documentation for docs"
      When call _changelog._type_label docs
      The output should equal "Documentation"
    End

    It "returns Tests for test"
      When call _changelog._type_label test
      The output should equal "Tests"
    End

    It "returns Performance for perf"
      When call _changelog._type_label perf
      The output should equal "Performance"
    End

    It "returns CI for ci"
      When call _changelog._type_label ci
      The output should equal "CI"
    End

    It "returns Style for style"
      When call _changelog._type_label style
      The output should equal "Style"
    End

    It "returns Build for build"
      When call _changelog._type_label build
      The output should equal "Build"
    End

    It "returns Reverts for revert"
      When call _changelog._type_label revert
      The output should equal "Reverts"
    End

    It "returns Chores for chore"
      When call _changelog._type_label chore
      The output should equal "Chores"
    End

    It "returns Other Changes for other"
      When call _changelog._type_label other
      The output should equal "Other Changes"
    End

    It "returns Other Changes for unknown"
      When call _changelog._type_label unknown
      The output should equal "Other Changes"
    End
  End

  Describe "changelog.count_entries"
    It "counts list bullet lines in a single section"
      run_count() {
        local md
        md="$(printf '## Changes\n\n### Features\n\n- add login (abc1234)\n- add logout (def5678)\n')"
        changelog.count_entries "$md"
      }
      When call run_count
      The output should equal "2"
    End

    It "counts entries across multiple sections"
      run_count() {
        local md
        md="$(printf '## Changes\n\n### Features\n\n- a (1)\n- b (2)\n\n### Bug Fixes\n\n- c (3)\n')"
        changelog.count_entries "$md"
      }
      When call run_count
      The output should equal "3"
    End

    It "ignores nested bullets and counts only top-level entries"
      run_count() {
        local md
        md="$(printf '### Features\n\n- top entry (1)\n  - nested note\n- another top (2)\n')"
        changelog.count_entries "$md"
      }
      When call run_count
      The output should equal "2"
    End

    It "returns 0 for an empty changelog"
      run_count() {
        changelog.count_entries ""
      }
      When call run_count
      The output should equal "0"
    End

    It "returns 0 for a changelog with no list items"
      run_count() {
        local md
        md="$(printf '## Changes\n\nNo changes.\n')"
        changelog.count_entries "$md"
      }
      When call run_count
      The output should equal "0"
    End
  End
End

Describe "version.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/version.sh"

  Describe "version.validate"
    It "accepts a valid semver (1.2.3)"
      When call version.validate "1.2.3"
      The status should be success
    End

    It "accepts a semver with prerelease (1.2.3-rc.1)"
      When call version.validate "1.2.3-rc.1"
      The status should be success
    End

    It "accepts a semver with build metadata (1.2.3+build.123)"
      When call version.validate "1.2.3+build.123"
      The status should be success
    End

    It "rejects an invalid string"
      When call version.validate "not-a-version"
      The status should equal 2
      The stderr should include "invalid semver"
    End

    It "rejects empty string"
      When call version.validate ""
      The status should equal 2
      The stderr should include "invalid semver"
    End
  End

  Describe "version.bump"
    It "bumps major (1.2.3 -> 2.0.0)"
      When call version.bump "1.2.3" "major"
      The output should equal "2.0.0"
    End

    It "bumps minor (1.2.3 -> 1.3.0)"
      When call version.bump "1.2.3" "minor"
      The output should equal "1.3.0"
    End

    It "bumps patch (1.2.3 -> 1.2.4)"
      When call version.bump "1.2.3" "patch"
      The output should equal "1.2.4"
    End

    It "bumps prerelease (1.2.3 -> 1.2.4-rc.1)"
      When call version.bump "1.2.3" "prerelease"
      The output should equal "1.2.4-rc.1"
    End

    It "rejects invalid bump type"
      When call version.bump "1.2.3" "invalid"
      The status should equal 2
      The stderr should include "unknown bump type"
    End

    It "rejects invalid version"
      When call version.bump "bad" "patch"
      The status should equal 2
      The stderr should be present
    End
  End

  Describe "version.compare"
    It "returns 0 for equal versions"
      When call version.compare "1.2.3" "1.2.3"
      The output should equal "0"
    End

    It "returns 1 when first is greater"
      When call version.compare "2.0.0" "1.9.9"
      The output should equal "1"
    End

    It "returns -1 when first is lesser"
      When call version.compare "1.0.0" "1.0.1"
      The output should equal "-1"
    End

    It "compares minor versions"
      When call version.compare "1.3.0" "1.2.9"
      The output should equal "1"
    End
  End

  Describe "version.current"
    Describe "from file"
      setup() {
        PKG_DIR="$(mktemp -d)"
        printf '{"name":"test","version":"3.2.1"}\n' > "${PKG_DIR}/package.json"
      }
      cleanup() { rm -rf "$PKG_DIR"; }
      Before 'setup'
      After 'cleanup'

      It "reads from package.json"
        When call version.current --from-file "${PKG_DIR}/package.json"
        The output should equal "3.2.1"
      End
    End

    It "returns 6 for missing file"
      When call version.current --from-file "/nonexistent/package.json"
      The status should equal 6
      The stderr should include "file not found"
    End

    It "returns 2 for unknown option"
      When call version.current --badopt
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "from generic file (non-package.json)"
      setup() {
        VERSION_DIR="$(mktemp -d)"
        printf '4.5.6\n' > "${VERSION_DIR}/VERSION"
      }
      cleanup() { rm -rf "$VERSION_DIR"; }
      Before 'setup'
      After 'cleanup'

      It "reads first line of a generic file"
        When call version.current --from-file "${VERSION_DIR}/VERSION"
        The output should equal "4.5.6"
      End
    End

    Describe "from git tag"
      setup_git() {
        GIT_DIR="$(mktemp -d)"
        cd "$GIT_DIR" || return 1
        git init -q
        git config user.name "test"
        git config user.email "test@test.com"
        printf 'hello\n' > file.txt
        git add file.txt
        git commit -q -m "initial"
        git tag "v2.5.0"
      }
      cleanup_git() { rm -rf "$GIT_DIR"; cd /tmp || true; }
      Before 'setup_git'
      After 'cleanup_git'

      It "reads version from git tag (strips v prefix)"
        When call version.current --from-git-tag
        The output should equal "2.5.0"
      End
    End

    Describe "from git tag without v prefix"
      setup_git_nov() {
        GIT_DIR="$(mktemp -d)"
        cd "$GIT_DIR" || return 1
        git init -q
        git config user.name "test"
        git config user.email "test@test.com"
        printf 'hello\n' > file.txt
        git add file.txt
        git commit -q -m "initial"
        git tag "1.0.0"
      }
      cleanup_git_nov() { rm -rf "$GIT_DIR"; cd /tmp || true; }
      Before 'setup_git_nov'
      After 'cleanup_git_nov'

      It "reads version from git tag without v prefix"
        When call version.current --from-git-tag
        The output should equal "1.0.0"
      End
    End

    Describe "auto mode with package.json"
      setup_auto() {
        AUTO_DIR="$(mktemp -d)"
        printf '{"name":"auto","version":"7.8.9"}\n' > "${AUTO_DIR}/package.json"
        cd "$AUTO_DIR" || return 1
      }
      cleanup_auto() { rm -rf "$AUTO_DIR"; cd /tmp || true; }
      Before 'setup_auto'
      After 'cleanup_auto'

      It "detects version from package.json in current directory"
        When call version.current
        The output should equal "7.8.9"
      End
    End

    Describe "auto mode with git tag fallback"
      setup_auto_git() {
        AUTO_DIR="$(mktemp -d)"
        cd "$AUTO_DIR" || return 1
        git init -q
        git config user.name "test"
        git config user.email "test@test.com"
        printf 'hello\n' > file.txt
        git add file.txt
        git commit -q -m "initial"
        git tag "v3.0.0"
      }
      cleanup_auto_git() { rm -rf "$AUTO_DIR"; cd /tmp || true; }
      Before 'setup_auto_git'
      After 'cleanup_auto_git'

      It "falls back to git tag when no package.json"
        When call version.current
        The output should equal "3.0.0"
      End
    End
  End

  Describe "version.write"
    setup() { WRITE_DIR="$(mktemp -d)"; }
    cleanup() { rm -rf "$WRITE_DIR"; }
    Before 'setup'
    After 'cleanup'

    It "writes version to a file"
      When call version.write "2.0.0" --file "${WRITE_DIR}/VERSION"
      The status should be success
      The contents of file "${WRITE_DIR}/VERSION" should equal "2.0.0"
    End

    It "rejects invalid version"
      When call version.write "bad" --file "${WRITE_DIR}/VERSION"
      The status should equal 2
      The stderr should be present
    End

    It "returns 2 for unknown option"
      When call version.write "1.0.0" --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "without --file auto-detects package.json"
      setup_pkg() {
        PKG_WD="$(mktemp -d)"
        printf '{"name":"test","version":"1.0.0"}\n' > "${PKG_WD}/package.json"
        cd "$PKG_WD" || return 1
      }
      cleanup_pkg() { rm -rf "$PKG_WD"; cd /tmp || true; }
      Before 'setup_pkg'
      After 'cleanup_pkg'

      It "updates version in package.json"
        verify_pkg_write() {
          version.write "5.0.0" 2>/dev/null
          jq -r '.version' package.json 2>/dev/null
        }
        When call verify_pkg_write
        The output should equal "5.0.0"
      End
    End

    Describe "without --file and no package.json"
      setup_empty() {
        EMPTY_WD="$(mktemp -d)"
        cd "$EMPTY_WD" || return 1
      }
      cleanup_empty() { rm -rf "$EMPTY_WD"; cd /tmp || true; }
      Before 'setup_empty'
      After 'cleanup_empty'

      It "returns 2 when no file specified and no package.json"
        When call version.write "1.0.0"
        The status should equal 2
        The stderr should include "no target file"
      End
    End
  End
End

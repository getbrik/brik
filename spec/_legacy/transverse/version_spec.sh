Describe "version.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_TRANSVERSE_LIB/git.sh"
  Include "$BRIK_TRANSVERSE_LIB/version.sh"

  # Stub brik.use: transverse.git is already Included above, so the runtime
  # loader call from version.current becomes a no-op (function is in scope).
  brik.use() { :; }

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

    Describe "from git tag with custom prefix"
      setup_git_prefix() {
        GIT_DIR="$(mktemp -d)"
        cd "$GIT_DIR" || return 1
        git init -q
        git config user.name "test"
        git config user.email "test@test.com"
        printf 'hello\n' > file.txt
        git add file.txt
        git commit -q -m "initial"
        git tag "release-2.0.0"
      }
      cleanup_git_prefix() { rm -rf "$GIT_DIR"; cd /tmp || true; }
      Before 'setup_git_prefix'
      After 'cleanup_git_prefix'

      It "strips custom prefix from git tag"
        When call version.current --from-git-tag --prefix "release-"
        The output should equal "2.0.0"
      End
    End

    Describe "from git tag with --prefix v (explicit)"
      setup_git_vprefix() {
        GIT_DIR="$(mktemp -d)"
        cd "$GIT_DIR" || return 1
        git init -q
        git config user.name "test"
        git config user.email "test@test.com"
        printf 'hello\n' > file.txt
        git add file.txt
        git commit -q -m "initial"
        git tag "v3.1.0"
      }
      cleanup_git_vprefix() { rm -rf "$GIT_DIR"; cd /tmp || true; }
      Before 'setup_git_vprefix'
      After 'cleanup_git_vprefix'

      It "strips v prefix when explicitly passed"
        When call version.current --from-git-tag --prefix "v"
        The output should equal "3.1.0"
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

End

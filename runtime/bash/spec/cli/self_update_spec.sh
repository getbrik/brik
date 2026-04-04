#!/usr/bin/env bash
# self_update_spec.sh - ShellSpec tests for `brik self-update`

Describe "brik self-update"

  Describe "option parsing"
    It "rejects unknown options"
      When run script "${BRIK_BIN}" self-update --badopt
      The status should eq 2
      The stderr should include "unknown option"
    End

    It "rejects invalid channel"
      When run script "${BRIK_BIN}" self-update --channel invalid
      The status should eq 2
      The stderr should include "invalid channel"
    End

    It "requires a value for --channel"
      When run script "${BRIK_BIN}" self-update --channel
      The status should eq 2
      The stderr should include "requires a value"
    End

    It "requires a value for --version"
      When run script "${BRIK_BIN}" self-update --version
      The status should eq 2
      The stderr should include "requires a value"
    End
  End

  Describe "install method detection"
    setup_no_brew() {
      FAKE_BIN="$(mktemp -d)"
      printf '#!/usr/bin/env bash\nexit 1\n' > "${FAKE_BIN}/brew"
      chmod +x "${FAKE_BIN}/brew"
      ORIG_PATH="${PATH}"
      PATH="${FAKE_BIN}:${PATH}"
    }
    cleanup_no_brew() {
      PATH="${ORIG_PATH}"
      rm -rf "${FAKE_BIN}"
    }

    Before "setup_no_brew"
    After "cleanup_no_brew"

    It "reports source when BRIK_HOME is not ~/.brik"
      When run script "${BRIK_BIN}" version --verbose
      The status should eq 0
      The output should include "install: source"
    End
  End

  Describe "unknown install method"
    setup_unknown() {
      FAKE_HOME_UP="$(mktemp -d)"
      FAKE_HOME_UP="$(cd -P "${FAKE_HOME_UP}" && pwd)"
      mkdir -p "${FAKE_HOME_UP}/bin"
      cp "${BRIK_HOME}/bin/brik" "${FAKE_HOME_UP}/bin/brik"
      chmod +x "${FAKE_HOME_UP}/bin/brik"
      cp -R "${BRIK_HOME}/runtime" "${FAKE_HOME_UP}/runtime" 2>/dev/null || true
      cp -R "${BRIK_HOME}/schemas" "${FAKE_HOME_UP}/schemas" 2>/dev/null || true

      FAKE_BIN_UP="$(mktemp -d)"
      printf '#!/usr/bin/env bash\nexit 1\n' > "${FAKE_BIN_UP}/brew"
      chmod +x "${FAKE_BIN_UP}/brew"
      ORIG_PATH_UP="${PATH}"
      # No .git dir in FAKE_HOME_UP, so _brik_detect_install_method returns "unknown"
      export BRIK_HOME="${FAKE_HOME_UP}"
      export PATH="${FAKE_BIN_UP}:${ORIG_PATH_UP}"
    }
    cleanup_unknown() {
      PATH="${ORIG_PATH_UP}"
      rm -rf "${FAKE_HOME_UP}" "${FAKE_BIN_UP}"
    }

    Before "setup_unknown"
    After "cleanup_unknown"

    It "errors when install method is unknown"
      When run script "${FAKE_HOME_UP}/bin/brik" self-update
      The status should eq 2
      The stderr should include "cannot self-update"
    End
  End

  Describe "git dirty working tree"
    setup_dirty_git() {
      FAKE_GIT_HOME="$(mktemp -d)"
      FAKE_GIT_HOME="$(cd -P "${FAKE_GIT_HOME}" && pwd)"
      mkdir -p "${FAKE_GIT_HOME}/bin"
      cp "${BRIK_HOME}/bin/brik" "${FAKE_GIT_HOME}/bin/brik"
      chmod +x "${FAKE_GIT_HOME}/bin/brik"
      cp -R "${BRIK_HOME}/runtime" "${FAKE_GIT_HOME}/runtime" 2>/dev/null || true
      cp -R "${BRIK_HOME}/schemas" "${FAKE_GIT_HOME}/schemas" 2>/dev/null || true

      # Init a git repo and make it dirty
      git -C "${FAKE_GIT_HOME}" init -q
      git -C "${FAKE_GIT_HOME}" config user.email "test@test.com"
      git -C "${FAKE_GIT_HOME}" config user.name "Test"
      git -C "${FAKE_GIT_HOME}" add -A
      git -C "${FAKE_GIT_HOME}" commit -q -m "init"
      printf 'dirty\n' > "${FAKE_GIT_HOME}/dirty.txt"

      FAKE_BIN_DG="$(mktemp -d)"
      printf '#!/usr/bin/env bash\nexit 1\n' > "${FAKE_BIN_DG}/brew"
      chmod +x "${FAKE_BIN_DG}/brew"
      ORIG_PATH_DG="${PATH}"

      # Move to ~/.brik so _brik_detect_install_method returns "git"
      FAKE_USER_HOME_DG="$(dirname "${FAKE_GIT_HOME}")"
      mv "${FAKE_GIT_HOME}" "${FAKE_USER_HOME_DG}/.brik"
      FAKE_GIT_HOME="${FAKE_USER_HOME_DG}/.brik"

      export HOME="${FAKE_USER_HOME_DG}"
      export BRIK_HOME="${FAKE_GIT_HOME}"
      export PATH="${FAKE_BIN_DG}:${ORIG_PATH_DG}"
    }
    cleanup_dirty_git() {
      PATH="${ORIG_PATH_DG}"
      rm -rf "${FAKE_GIT_HOME}" "${FAKE_BIN_DG}"
    }

    Before "setup_dirty_git"
    After "cleanup_dirty_git"

    It "errors when git working tree is dirty"
      When run script "${FAKE_GIT_HOME}/bin/brik" self-update
      The status should eq 2
      The stderr should include "working tree is dirty"
    End
  End

  Describe "git update stable with no tags"
    setup_no_tags() {
      FAKE_NT_HOME="$(mktemp -d)"
      FAKE_NT_HOME="$(cd -P "${FAKE_NT_HOME}" && pwd)"
      mkdir -p "${FAKE_NT_HOME}/bin"
      cp "${BRIK_HOME}/bin/brik" "${FAKE_NT_HOME}/bin/brik"
      chmod +x "${FAKE_NT_HOME}/bin/brik"
      cp -R "${BRIK_HOME}/runtime" "${FAKE_NT_HOME}/runtime" 2>/dev/null || true
      cp -R "${BRIK_HOME}/schemas" "${FAKE_NT_HOME}/schemas" 2>/dev/null || true

      # Init a clean git repo with an origin remote but no tags
      git -C "${FAKE_NT_HOME}" init -q
      git -C "${FAKE_NT_HOME}" config user.email "test@test.com"
      git -C "${FAKE_NT_HOME}" config user.name "Test"
      git -C "${FAKE_NT_HOME}" add -A
      git -C "${FAKE_NT_HOME}" commit -q -m "init"
      BARE_REPO="$(mktemp -d)"
      BARE_REPO="$(cd -P "${BARE_REPO}" && pwd)"
      git clone --bare -q "${FAKE_NT_HOME}" "${BARE_REPO}/repo.git"
      git -C "${FAKE_NT_HOME}" remote remove origin 2>/dev/null || true
      git -C "${FAKE_NT_HOME}" remote add origin "${BARE_REPO}/repo.git"

      FAKE_BIN_NT="$(mktemp -d)"
      printf '#!/usr/bin/env bash\nexit 1\n' > "${FAKE_BIN_NT}/brew"
      chmod +x "${FAKE_BIN_NT}/brew"
      ORIG_PATH_NT="${PATH}"

      FAKE_USER_HOME_NT="$(dirname "${FAKE_NT_HOME}")"
      mv "${FAKE_NT_HOME}" "${FAKE_USER_HOME_NT}/.brik"
      FAKE_NT_HOME="${FAKE_USER_HOME_NT}/.brik"

      export HOME="${FAKE_USER_HOME_NT}"
      export BRIK_HOME="${FAKE_NT_HOME}"
      export PATH="${FAKE_BIN_NT}:${ORIG_PATH_NT}"
    }
    cleanup_no_tags() {
      PATH="${ORIG_PATH_NT}"
      rm -rf "${FAKE_NT_HOME}" "${FAKE_BIN_NT}" "${BARE_REPO}"
    }

    Before "setup_no_tags"
    After "cleanup_no_tags"

    It "errors when no tags found for stable channel"
      When run script "${FAKE_NT_HOME}/bin/brik" self-update
      The status should eq 2
      The stdout should be present
      The stderr should include "no tags found"
    End
  End

End

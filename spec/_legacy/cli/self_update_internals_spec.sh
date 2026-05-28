Describe "cli/self_update.sh - in-process tests for kcov coverage"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_CLI_LIB/helpers.sh"
  Include "$BRIK_CLI_LIB/self_update.sh"

  # All tests in this file Include the module so kcov can instrument the
  # functions. The sibling spec/cli/self_update_spec.sh uses `When run script
  # $BRIK_BIN` which spawns a subprocess and therefore does not produce
  # coverage data for lib/cli/self_update.sh.

  Describe "cli.self_update.run - option parsing"
    It "rejects unknown option"
      When call cli.self_update.run --bogus
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The error should be present
    End

    It "rejects invalid channel"
      When call cli.self_update.run --channel invalid
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "invalid channel"
    End

    It "requires a value for --channel"
      When call cli.self_update.run --channel
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "requires a value"
    End

    It "requires a value for --version"
      When call cli.self_update.run --version
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "requires a value"
    End

    It "parses --version and --channel together and falls through to install-method dispatch"
      # Stub the install-method detector so we land in the "unknown" branch
      # without depending on the host's brew/git state.
      _brik_detect_install_method() { printf 'unknown'; }
      When call cli.self_update.run --version v1.2.3 --channel edge
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "cannot self-update"
    End
  End

  Describe "cli.self_update.run - brew and post-update"
    setup_brew_mock() {
      _SU_MOCK_BIN="$(mktemp -d)"
      cat > "${_SU_MOCK_BIN}/brew" <<'SH'
#!/usr/bin/env bash
printf 'brew upgrade %s\n' "$*"
exit 0
SH
      chmod +x "${_SU_MOCK_BIN}/brew"
      _SU_ORIG_PATH="$PATH"
      export PATH="${_SU_MOCK_BIN}:${PATH}"
      # Stub _brik_detect_install_method to steer into the brew branch
      _brik_detect_install_method() { printf 'brew'; }
      # Stub $BRIK_HOME/bin/brik so the post-update "${BRIK_HOME}/bin/brik version"
      # call returns a deterministic line.
      _SU_FAKE_HOME_BR="$(mktemp -d)"
      mkdir -p "${_SU_FAKE_HOME_BR}/bin"
      cat > "${_SU_FAKE_HOME_BR}/bin/brik" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "version" ]] && printf 'brik 9.9.9\n'
exit 0
SH
      chmod +x "${_SU_FAKE_HOME_BR}/bin/brik"
      _SU_ORIG_HOME="${BRIK_HOME:-}"
      export BRIK_HOME="${_SU_FAKE_HOME_BR}"
    }
    cleanup_brew_mock() {
      export PATH="${_SU_ORIG_PATH}"
      rm -rf "${_SU_MOCK_BIN}" "${_SU_FAKE_HOME_BR}"
      if [[ -n "${_SU_ORIG_HOME}" ]]; then
        export BRIK_HOME="${_SU_ORIG_HOME}"
      else
        unset BRIK_HOME
      fi
      unset -f _brik_detect_install_method 2>/dev/null || true
    }
    Before 'setup_brew_mock'
    After 'cleanup_brew_mock'

    It "runs the brew branch and prints the post-update version"
      When call cli.self_update.run
      The status should be success
      The stdout should include "updating via Homebrew"
      The stdout should include "update complete"
      The stdout should include "brik 9.9.9"
    End
  End

  Describe "_cli.self_update._git - branches"
    setup_fake_home() {
      FAKE_HOME_SU="$(mktemp -d)"
      FAKE_HOME_SU="$(cd -P "${FAKE_HOME_SU}" && pwd)"
      # Create a fake git checkout with an explicit main branch so
      # "describe --tags --abbrev=0 origin/main" can resolve.
      git -C "${FAKE_HOME_SU}" init -q -b main
      git -C "${FAKE_HOME_SU}" config user.email "t@t.com"
      git -C "${FAKE_HOME_SU}" config user.name "t"
      printf 'x\n' > "${FAKE_HOME_SU}/readme"
      git -C "${FAKE_HOME_SU}" add -A
      git -C "${FAKE_HOME_SU}" commit -q -m init
      # Create a bare "origin" so fetch/checkout have something to talk to
      BARE_SU="$(mktemp -d)"
      git clone --bare -q "${FAKE_HOME_SU}" "${BARE_SU}/repo.git"
      git -C "${FAKE_HOME_SU}" remote add origin "${BARE_SU}/repo.git" 2>/dev/null || true
      _ORIG_BRIK_HOME_SU="${BRIK_HOME:-}"
      export BRIK_HOME="${FAKE_HOME_SU}"
    }
    cleanup_fake_home() {
      rm -rf "${FAKE_HOME_SU}" "${BARE_SU}"
      if [[ -n "${_ORIG_BRIK_HOME_SU:-}" ]]; then
        export BRIK_HOME="${_ORIG_BRIK_HOME_SU}"
      else
        unset BRIK_HOME
      fi
    }
    Before 'setup_fake_home'
    After 'cleanup_fake_home'

    It "errors when BRIK_HOME is not a git checkout"
      non_git_check() {
        local tmp
        tmp="$(mktemp -d)"
        export BRIK_HOME="$tmp"
        _cli.self_update._git stable ""
        local rc=$?
        rm -rf "$tmp"
        return "$rc"
      }
      When call non_git_check
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "not a git installation"
    End

    It "errors when working tree is dirty"
      dirty_tree() {
        printf 'dirty\n' > "${BRIK_HOME}/new-file"
        _cli.self_update._git stable ""
      }
      When call dirty_tree
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "working tree is dirty"
    End

    It "errors when no tags exist on stable channel"
      When call _cli.self_update._git stable ""
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "no tags found"
      The stdout should include "fetching updates"
    End

    It "errors when target version does not exist"
      bad_version() {
        _cli.self_update._git stable "v99.99.99"
      }
      When call bad_version
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "v99.99.99 not found"
      The stdout should include "switching to v99.99.99"
    End

    It "succeeds on stable channel when a tag exists"
      happy_stable_tag() {
        # Tag the current commit so "describe --tags --abbrev=0 origin/main"
        # and the subsequent "checkout <tag>" both succeed.
        git -C "${BRIK_HOME}" tag v0.0.1-test
        # Push the tag to origin so `describe origin/main` can see it.
        git -C "${BRIK_HOME}" push -q origin --tags 2>/dev/null || true
        _cli.self_update._git stable ""
      }
      When call happy_stable_tag
      The status should be success
      The stdout should include "switching to v0.0.1-test"
    End

    It "succeeds when --version points to an existing tag"
      happy_explicit_version() {
        git -C "${BRIK_HOME}" tag v0.0.2-test
        git -C "${BRIK_HOME}" push -q origin --tags 2>/dev/null || true
        _cli.self_update._git stable "v0.0.2-test"
      }
      When call happy_explicit_version
      The status should be success
      The stdout should include "switching to v0.0.2-test"
    End

    It "succeeds on edge channel via pull --ff-only"
      happy_edge() {
        # Ensure the local and origin refs are aligned so `pull --ff-only` is a no-op fast-forward.
        _cli.self_update._git edge ""
      }
      When call happy_edge
      The status should be success
      The stdout should include "switching to edge"
    End
  End
End

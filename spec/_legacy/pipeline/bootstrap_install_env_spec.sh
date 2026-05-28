Describe "bootstrap.sh - prepare_env and CI edge cases"
  Include "$BRIK_PIPELINE_LIB/bootstrap.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"


  # ---------------------------------------------------------------------------
  # bootstrap.prepare_env
  # ---------------------------------------------------------------------------
  Describe "bootstrap.prepare_env"
    Describe "without stack (mocked local)"
      setup_env_empty() {
        mock.setup
        export BRIK_PLATFORM="local"
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        mock.create "yq"
        mock.create "jq"
        mock.create "git"
        mock.create "bash"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      cleanup_env_empty() {
        rm -rf "$BRIK_HOME"
        mock.cleanup
      }
      Before 'setup_env_empty'
      After 'cleanup_env_empty'
      It "installs only prerequisites"
        When call bootstrap.prepare_env ""
        The status should be success
        The stderr should include "preparing runtime environment"
        The stderr should include "runtime environment ready"
      End
    End

    Describe "without stack argument (mocked local)"
      setup_env_noarg() {
        mock.setup
        export BRIK_PLATFORM="local"
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        mock.create "yq"
        mock.create "jq"
        mock.create "git"
        mock.create "bash"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      cleanup_env_noarg() {
        rm -rf "$BRIK_HOME"
        mock.cleanup
      }
      Before 'setup_env_noarg'
      After 'cleanup_env_noarg'
      It "installs only prerequisites"
        When call bootstrap.prepare_env
        The status should be success
        The stderr should include "preparing runtime environment"
        The stderr should include "runtime environment ready"
      End
    End

    Describe "with stack already present (mocked node)"
      setup_env_present() {
        mock.setup
        export BRIK_PLATFORM="local"
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        mock.create "yq"
        mock.create "jq"
        mock.create "git"
        mock.create "bash"
        mock.create "node"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      cleanup_env_present() {
        rm -rf "$BRIK_HOME"
        mock.cleanup
      }
      Before 'setup_env_present'
      After 'cleanup_env_present'
      It "succeeds"
        When call bootstrap.prepare_env "node"
        The status should be success
        The stderr should include "runtime environment ready"
      End
    End

    Describe "with missing stack on local without mise"
      setup_env_no_mgr() {
        mock.setup
        export BRIK_PLATFORM="local"
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        mock.create "yq"
        mock.create "jq"
        # Keep system PATH but remove directories containing java
        local p=""
        local IFS=":"
        for d in $_MOCK_ORIG_PATH; do
          [[ -x "${d}/java" ]] && continue
          [[ -x "${d}/mise" ]] && continue
          p="${p:+${p}:}${d}"
        done
        PATH="${MOCK_BIN}:${p}"
      }
      Before 'setup_env_no_mgr'
      After 'mock.cleanup'
      It "returns error for missing stack"
        When call bootstrap.prepare_env "java"
        The status should equal 3
        The stderr should include "stack installation failed"
      End
    End

    Describe "full flow on CI with apk"
      setup_env_ci() {
        mock.setup
        export BRIK_PLATFORM="gitlab"
        mock.create "apk"
        mock.create "node"
        mock.create "uname"
        mock.create "wget"
        mock.create "chmod"
        PATH="${MOCK_BIN}"
        export BRIK_BUILD_NODE_VERSION="20"
      }
      cleanup_env_ci() {
        unset BRIK_BUILD_NODE_VERSION
        mock.cleanup
      }
      Before 'setup_env_ci'
      After 'cleanup_env_ci'
      It "installs prerequisites and reports ready"
        When call bootstrap.prepare_env "node"
        The status should be success
        The stderr should include "preparing runtime environment"
        The stderr should include "runtime environment ready"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # bootstrap.install_stack -- additional CI edge cases
  # ---------------------------------------------------------------------------
  Describe "bootstrap.install_stack CI edge cases"
    Describe "on CI with no package manager (fallback to check)"
      setup_stack_no_mgr() {
        mock.setup
        export BRIK_PLATFORM="gitlab"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_stack_no_mgr'
      After 'mock.cleanup'
      It "falls back to check_stack and returns 3"
        When call bootstrap.install_stack "node"
        The status should equal 3
        The stderr should include "no system package manager detected"
      End
    End

    Describe "on CI reads version from env var"
      setup_stack_ver() {
        mock.setup
        export BRIK_PLATFORM="gitlab"
        mock.create "apk"
        PATH="${MOCK_BIN}"
        export BRIK_BUILD_RUST_VERSION=""
      }
      cleanup_stack_ver() {
        unset BRIK_BUILD_RUST_VERSION
        mock.cleanup
      }
      Before 'setup_stack_ver'
      After 'cleanup_stack_ver'
      It "passes empty version through"
        When call bootstrap.install_stack "rust"
        The status should be success
        The stderr should include "rust cargo"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # bootstrap.install_prerequisites -- additional local edge cases
  # ---------------------------------------------------------------------------
  Describe "bootstrap.install_prerequisites local edge cases"
    Describe "on local when bash is missing"
      setup_prereq_no_bash() {
        mock.setup
        export BRIK_PLATFORM="local"
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        mock.create "yq"
        mock.create "jq"
        mock.create "git"
        # Keep system PATH but remove directories containing bash
        local p=""
        local IFS=":"
        for d in $_MOCK_ORIG_PATH; do
          [[ -x "${d}/bash" ]] && continue
          p="${p:+${p}:}${d}"
        done
        PATH="${MOCK_BIN}:${p}"
      }
      Before 'setup_prereq_no_bash'
      After 'mock.cleanup'
      It "returns 3 with hint"
        When call bootstrap.install_prerequisites
        The status should equal 3
        The stderr should include "bash is required but not found"
      End
    End
  End
End

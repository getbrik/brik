Describe "setup.sh - install_stack / check_stack / prepare_env"
  Include "$BRIK_RUNTIME_LIB/setup.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"


  # ---------------------------------------------------------------------------
  # setup.install_stack
  # ---------------------------------------------------------------------------
  Describe "setup.install_stack"
    Describe "with empty stack name"
      It "returns 2"
        When call setup.install_stack ""
        The status should equal 2
        The stderr should include "stack name is required"
      End
    End

    Describe "when stack already on PATH"
      setup_stack_present() {
        mock.setup
        mock.create "node"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      Before 'setup_stack_present'
      After 'mock.cleanup'
      It "returns 0 for node"
        When call setup.install_stack "node"
        The status should be success
        The stderr should include "already available"
      End
    End

    Describe "on CI with apk for node"
      setup_stack_ci() {
        mock.setup
        export BRIK_PLATFORM="gitlab"
        mock.create "apk"
        PATH="${MOCK_BIN}"
        export BRIK_BUILD_NODE_VERSION="20"
      }
      cleanup_stack_ci() {
        unset BRIK_BUILD_NODE_VERSION
        mock.cleanup
      }
      Before 'setup_stack_ci'
      After 'cleanup_stack_ci'
      It "installs via system package manager"
        When call setup.install_stack "node"
        The status should be success
        The stderr should include "installing node via apk"
      End
    End

    Describe "on CI with apk for java with version"
      setup_stack_java() {
        mock.setup
        export BRIK_PLATFORM="gitlab"
        mock.create "apk"
        PATH="${MOCK_BIN}"
        export BRIK_BUILD_JAVA_VERSION="21"
      }
      cleanup_stack_java() {
        unset BRIK_BUILD_JAVA_VERSION
        mock.cleanup
      }
      Before 'setup_stack_java'
      After 'cleanup_stack_java'
      It "installs with version"
        When call setup.install_stack "java"
        The status should be success
        The stderr should include "openjdk21-jdk"
      End
    End

    Describe "on CI with apk for python"
      setup_stack_python() {
        mock.setup
        export BRIK_PLATFORM="gitlab"
        mock.create "apk"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_stack_python'
      After 'mock.cleanup'
      It "installs python"
        When call setup.install_stack "python"
        The status should be success
        The stderr should include "installing python via apk"
      End
    End

    Describe "on CI with apk for rust"
      setup_stack_rust() {
        mock.setup
        export BRIK_PLATFORM="gitlab"
        mock.create "apk"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_stack_rust'
      After 'mock.cleanup'
      It "installs rust"
        When call setup.install_stack "rust"
        The status should be success
        The stderr should include "installing rust via apk"
      End
    End

    Describe "on CI with apk for dotnet"
      setup_stack_dotnet() {
        mock.setup
        export BRIK_PLATFORM="gitlab"
        mock.create "apk"
        PATH="${MOCK_BIN}"
        export BRIK_BUILD_DOTNET_VERSION="8"
      }
      cleanup_stack_dotnet() {
        unset BRIK_BUILD_DOTNET_VERSION
        mock.cleanup
      }
      Before 'setup_stack_dotnet'
      After 'cleanup_stack_dotnet'
      It "installs dotnet"
        When call setup.install_stack "dotnet"
        The status should be success
        The stderr should include "installing dotnet via apk"
      End
    End

    Describe "on local with mise"
      setup_stack_mise() {
        mock.setup
        export BRIK_PLATFORM="local"
        mock.create "mise"
        PATH="${MOCK_BIN}"
        export BRIK_BUILD_NODE_VERSION="20"
      }
      cleanup_stack_mise() {
        unset BRIK_BUILD_NODE_VERSION
        mock.cleanup
      }
      Before 'setup_stack_mise'
      After 'cleanup_stack_mise'
      It "installs via mise"
        When call setup.install_stack "node"
        The status should be success
        The stderr should include "installing node via mise"
      End
    End

    Describe "on local without mise (check-and-fail)"
      setup_stack_no_mise() {
        mock.setup
        export BRIK_PLATFORM="local"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_stack_no_mise'
      After 'mock.cleanup'
      It "returns 3 with hint"
        When call setup.install_stack "node"
        The status should equal 3
        The stderr should include "not found on PATH"
        The stderr should include "hint:"
      End
    End

    Describe "on CI handles install failure"
      setup_stack_fail() {
        mock.setup
        export BRIK_PLATFORM="gitlab"
        mock.create_failing "apk"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_stack_fail'
      After 'mock.cleanup'
      It "returns 5"
        When call setup.install_stack "node"
        The status should equal 5
        The stderr should include "failed to install stack"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # setup.check_stack
  # ---------------------------------------------------------------------------
  Describe "setup.check_stack"
    Describe "when tool is present"
      setup_check_present() {
        mock.setup
        mock.create "node"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      Before 'setup_check_present'
      After 'mock.cleanup'
      It "returns 0 for node"
        When call setup.check_stack "node"
        The status should be success
        The stderr should include "verified"
      End
    End

    Describe "when tool is missing"
      setup_check_missing() {
        mock.setup
        PATH="${MOCK_BIN}"
      }
      Before 'setup_check_missing'
      After 'mock.cleanup'

      It "returns 3 for missing node"
        When call setup.check_stack "node"
        The status should equal 3
        The stderr should include "not found on PATH"
      End

      It "returns 3 for missing python with pyenv hint"
        When call setup.check_stack "python"
        The status should equal 3
        The stderr should include "pyenv"
      End

      It "returns 3 for missing java with sdkman hint"
        When call setup.check_stack "java"
        The status should equal 3
        The stderr should include "sdkman"
      End

      It "returns 3 for missing rust with rustup hint"
        When call setup.check_stack "rust"
        The status should equal 3
        The stderr should include "rustup"
      End

      It "returns 3 for missing dotnet"
        When call setup.check_stack "dotnet"
        The status should equal 3
        The stderr should include "dotnet-install"
      End

      It "returns 3 for unknown stack"
        When call setup.check_stack "elixir"
        The status should equal 3
        The stderr should include "hint:"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # _setup._python_post_install
  # ---------------------------------------------------------------------------
  Describe "_setup._python_post_install"
    Describe "skipped on local platform"
      setup_local_python() {
        export BRIK_PLATFORM="local"
      }
      cleanup_local_python() {
        export BRIK_PLATFORM="${_MOCK_ORIG_PLATFORM:-}"
      }
      Before 'setup_local_python'
      After 'cleanup_local_python'
      It "returns 0 without doing anything"
        When call _setup._python_post_install
        The status should be success
      End
    End

    Describe "when python3 is not present on CI"
      setup_no_python() {
        mock.setup
        export BRIK_PLATFORM="gitlab"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_no_python'
      After 'mock.cleanup'
      It "returns 0 immediately"
        When call _setup._python_post_install
        The status should be success
      End
    End
  End
End

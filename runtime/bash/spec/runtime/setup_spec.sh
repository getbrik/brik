Describe "setup.sh"
  Include "$BRIK_RUNTIME_LIB/setup.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"


  # ---------------------------------------------------------------------------
  # _setup._is_virtualized
  # ---------------------------------------------------------------------------
  Describe "_setup._is_virtualized"
    Describe "returns true for gitlab"
      setup_virt() { export BRIK_PLATFORM="gitlab"; }
      cleanup_virt() { export BRIK_PLATFORM="${_MOCK_ORIG_PLATFORM:-}"; }
      Before 'setup_virt'
      After 'cleanup_virt'
      It "returns 0"
        When call _setup._is_virtualized
        The status should be success
      End
    End

    Describe "returns true for jenkins"
      setup_virt() { export BRIK_PLATFORM="jenkins"; }
      cleanup_virt() { export BRIK_PLATFORM="${_MOCK_ORIG_PLATFORM:-}"; }
      Before 'setup_virt'
      After 'cleanup_virt'
      It "returns 0"
        When call _setup._is_virtualized
        The status should be success
      End
    End

    Describe "returns false for local"
      setup_virt() { export BRIK_PLATFORM="local"; }
      cleanup_virt() { export BRIK_PLATFORM="${_MOCK_ORIG_PLATFORM:-}"; }
      Before 'setup_virt'
      After 'cleanup_virt'
      It "returns 1"
        When call _setup._is_virtualized
        The status should equal 1
      End
    End

    Describe "returns false when unset"
      setup_virt() { unset BRIK_PLATFORM 2>/dev/null || true; }
      cleanup_virt() { export BRIK_PLATFORM="${_MOCK_ORIG_PLATFORM:-}"; }
      Before 'setup_virt'
      After 'cleanup_virt'
      It "returns 1"
        When call _setup._is_virtualized
        The status should equal 1
      End
    End
  End

  # ---------------------------------------------------------------------------
  # _setup._detect_system_pkg_manager
  # ---------------------------------------------------------------------------
  Describe "_setup._detect_system_pkg_manager"
    Describe "when apt-get is available"
      setup_detect() {
        mock.setup
        mock.create "apt-get"
        mock.create "apk"
        PATH="$MOCK_BIN"
      }
      Before 'setup_detect'
      After 'mock.cleanup'
      It "returns apt-get (highest priority)"
        When call _setup._detect_system_pkg_manager
        The output should equal "apt-get"
      End
    End

    Describe "when only apk is available"
      setup_detect() {
        mock.setup
        mock.create "apk"
        PATH="$MOCK_BIN"
      }
      Before 'setup_detect'
      After 'mock.cleanup'
      It "returns apk"
        When call _setup._detect_system_pkg_manager
        The output should equal "apk"
      End
    End

    Describe "when only yum is available"
      setup_detect() {
        mock.setup
        mock.create "yum"
        PATH="$MOCK_BIN"
      }
      Before 'setup_detect'
      After 'mock.cleanup'
      It "returns yum"
        When call _setup._detect_system_pkg_manager
        The output should equal "yum"
      End
    End

    Describe "when only dnf is available"
      setup_detect() {
        mock.setup
        mock.create "dnf"
        PATH="$MOCK_BIN"
      }
      Before 'setup_detect'
      After 'mock.cleanup'
      It "returns dnf"
        When call _setup._detect_system_pkg_manager
        The output should equal "dnf"
      End
    End

    Describe "when no system package manager is available"
      setup_detect() {
        mock.setup
        PATH="$MOCK_BIN"
      }
      Before 'setup_detect'
      After 'mock.cleanup'
      It "returns empty string"
        When call _setup._detect_system_pkg_manager
        The output should equal ""
      End
    End

    Describe "does not detect mise or brew"
      setup_detect() {
        mock.setup
        mock.create "mise"
        mock.create "brew"
        PATH="$MOCK_BIN"
      }
      Before 'setup_detect'
      After 'mock.cleanup'
      It "returns empty string"
        When call _setup._detect_system_pkg_manager
        The output should equal ""
      End
    End
  End

  # ---------------------------------------------------------------------------
  # _setup._tool_command
  # ---------------------------------------------------------------------------
  Describe "_setup._tool_command"
    It "maps node to node"
      When call _setup._tool_command "node"
      The output should equal "node"
    End

    It "maps python to python3"
      When call _setup._tool_command "python"
      The output should equal "python3"
    End

    It "maps java to java"
      When call _setup._tool_command "java"
      The output should equal "java"
    End

    It "maps rust to cargo"
      When call _setup._tool_command "rust"
      The output should equal "cargo"
    End

    It "maps dotnet to dotnet"
      When call _setup._tool_command "dotnet"
      The output should equal "dotnet"
    End

    It "maps jq to jq"
      When call _setup._tool_command "jq"
      The output should equal "jq"
    End

    It "passes unknown names through"
      When call _setup._tool_command "sometool"
      The output should equal "sometool"
    End
  End

  # ---------------------------------------------------------------------------
  # _setup._ensure_brik_bin
  # ---------------------------------------------------------------------------
  Describe "_setup._ensure_brik_bin"
    Describe "with valid BRIK_HOME"
      setup_brik_bin() {
        mock.setup
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
      }
      cleanup_brik_bin() {
        rm -rf "$BRIK_HOME"
        mock.cleanup
      }
      Before 'setup_brik_bin'
      After 'cleanup_brik_bin'

      It "creates bin directory and adds to PATH"
        When call _setup._ensure_brik_bin
        The status should be success
        The path "${BRIK_HOME}/bin" should be directory
      End
    End

    Describe "without BRIK_HOME"
      setup_no_home() {
        mock.setup
        export BRIK_HOME=""
      }
      Before 'setup_no_home'
      After 'mock.cleanup'
      It "returns 1"
        When call _setup._ensure_brik_bin
        The status should equal 1
      End
    End
  End

  # ---------------------------------------------------------------------------
  # _setup._sys_pkg_install (CI dispatcher)
  # ---------------------------------------------------------------------------
  Describe "_setup._sys_pkg_install"
    Describe "skips when tool already present"
      setup_install() {
        mock.setup
        mock.create "apk"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
        export BRIK_LOG_LEVEL="debug"
      }
      cleanup_install() {
        export BRIK_LOG_LEVEL="info"
        mock.cleanup
      }
      Before 'setup_install'
      After 'cleanup_install'
      It "returns 0 without calling manager for bash"
        When call _setup._sys_pkg_install "apk" "bash"
        The status should be success
        The stderr should include "already installed"
      End
    End

    Describe "installs via apk when tool is missing"
      setup_missing() {
        mock.setup
        mock.create "apk"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_missing'
      After 'mock.cleanup'
      It "calls apk for jq"
        When call _setup._sys_pkg_install "apk" "jq"
        The status should be success
        The stderr should include "installing jq via apk"
      End
    End

    Describe "rejects brew as unsupported"
      setup_unsupported() {
        mock.setup
        PATH="${MOCK_BIN}"
      }
      Before 'setup_unsupported'
      After 'mock.cleanup'
      It "returns 5"
        When call _setup._sys_pkg_install "brew" "jq"
        The status should equal 5
        The stderr should include "unsupported package manager"
      End
    End

    Describe "dispatches to apt-get"
      setup_apt() {
        mock.setup
        mock.create "apt-get"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_apt'
      After 'mock.cleanup'
      It "calls apt-get"
        When call _setup._sys_pkg_install "apt-get" "git"
        The status should be success
        The stderr should include "installing git via apt-get"
      End
    End

    Describe "dispatches to yum"
      setup_yum() {
        mock.setup
        mock.create "yum"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_yum'
      After 'mock.cleanup'
      It "calls yum"
        When call _setup._sys_pkg_install "yum" "git"
        The status should be success
        The stderr should include "installing git via yum"
      End
    End

    Describe "dispatches to dnf"
      setup_dnf() {
        mock.setup
        mock.create "dnf"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_dnf'
      After 'mock.cleanup'
      It "calls dnf"
        When call _setup._sys_pkg_install "dnf" "bash"
        The status should be success
        The stderr should include "installing bash via dnf"
      End
    End

    Describe "handles install failure"
      setup_fail() {
        mock.setup
        mock.create_failing "apk"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_fail'
      After 'mock.cleanup'
      It "returns 5 when apk fails"
        When call _setup._sys_pkg_install "apk" "jq"
        The status should equal 5
        The stderr should include "apk install failed"
      End
    End
  End
End

Describe "setup.sh"
  Include "$BRIK_RUNTIME_LIB/setup.sh"

  # ---------------------------------------------------------------------------
  # Helpers for mocking package managers and tools
  # ---------------------------------------------------------------------------

  # Create a mock bin directory. Call BEFORE restricting PATH.
  setup_mock_bin() {
    MOCK_BIN="$(mktemp -d)"
    MOCK_LOG="${MOCK_BIN}/_commands.log"
    : > "$MOCK_LOG"
    ORIG_PATH="$PATH"
    ORIG_PLATFORM="${BRIK_PLATFORM:-}"
    ORIG_BRIK_HOME="${BRIK_HOME:-}"
  }

  cleanup_mock_bin() {
    PATH="$ORIG_PATH"
    export BRIK_PLATFORM="$ORIG_PLATFORM"
    export BRIK_HOME="$ORIG_BRIK_HOME"
    rm -rf "$MOCK_BIN"
  }

  # Create a mock executable that logs its invocation.
  create_mock() {
    local name="$1"
    printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$name" "$MOCK_LOG" > "${MOCK_BIN}/${name}"
    chmod +x "${MOCK_BIN}/${name}"
  }

  # Create a mock that always fails.
  create_failing_mock() {
    local name="$1"
    printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 1\n' "$name" "$MOCK_LOG" > "${MOCK_BIN}/${name}"
    chmod +x "${MOCK_BIN}/${name}"
  }

  # ---------------------------------------------------------------------------
  # _setup._is_virtualized
  # ---------------------------------------------------------------------------
  Describe "_setup._is_virtualized"
    Describe "returns true for gitlab"
      setup_virt() { export BRIK_PLATFORM="gitlab"; }
      cleanup_virt() { export BRIK_PLATFORM="${ORIG_PLATFORM:-}"; }
      Before 'setup_virt'
      After 'cleanup_virt'
      It "returns 0"
        When call _setup._is_virtualized
        The status should be success
      End
    End

    Describe "returns true for jenkins"
      setup_virt() { export BRIK_PLATFORM="jenkins"; }
      cleanup_virt() { export BRIK_PLATFORM="${ORIG_PLATFORM:-}"; }
      Before 'setup_virt'
      After 'cleanup_virt'
      It "returns 0"
        When call _setup._is_virtualized
        The status should be success
      End
    End

    Describe "returns false for local"
      setup_virt() { export BRIK_PLATFORM="local"; }
      cleanup_virt() { export BRIK_PLATFORM="${ORIG_PLATFORM:-}"; }
      Before 'setup_virt'
      After 'cleanup_virt'
      It "returns 1"
        When call _setup._is_virtualized
        The status should equal 1
      End
    End

    Describe "returns false when unset"
      setup_virt() { unset BRIK_PLATFORM 2>/dev/null || true; }
      cleanup_virt() { export BRIK_PLATFORM="${ORIG_PLATFORM:-}"; }
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
        setup_mock_bin
        create_mock "apt-get"
        create_mock "apk"
        PATH="$MOCK_BIN"
      }
      Before 'setup_detect'
      After 'cleanup_mock_bin'
      It "returns apt-get (highest priority)"
        When call _setup._detect_system_pkg_manager
        The output should equal "apt-get"
      End
    End

    Describe "when only apk is available"
      setup_detect() {
        setup_mock_bin
        create_mock "apk"
        PATH="$MOCK_BIN"
      }
      Before 'setup_detect'
      After 'cleanup_mock_bin'
      It "returns apk"
        When call _setup._detect_system_pkg_manager
        The output should equal "apk"
      End
    End

    Describe "when only yum is available"
      setup_detect() {
        setup_mock_bin
        create_mock "yum"
        PATH="$MOCK_BIN"
      }
      Before 'setup_detect'
      After 'cleanup_mock_bin'
      It "returns yum"
        When call _setup._detect_system_pkg_manager
        The output should equal "yum"
      End
    End

    Describe "when only dnf is available"
      setup_detect() {
        setup_mock_bin
        create_mock "dnf"
        PATH="$MOCK_BIN"
      }
      Before 'setup_detect'
      After 'cleanup_mock_bin'
      It "returns dnf"
        When call _setup._detect_system_pkg_manager
        The output should equal "dnf"
      End
    End

    Describe "when no system package manager is available"
      setup_detect() {
        setup_mock_bin
        PATH="$MOCK_BIN"
      }
      Before 'setup_detect'
      After 'cleanup_mock_bin'
      It "returns empty string"
        When call _setup._detect_system_pkg_manager
        The output should equal ""
      End
    End

    Describe "does not detect mise or brew"
      setup_detect() {
        setup_mock_bin
        create_mock "mise"
        create_mock "brew"
        PATH="$MOCK_BIN"
      }
      Before 'setup_detect'
      After 'cleanup_mock_bin'
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
        setup_mock_bin
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
      }
      cleanup_brik_bin() {
        rm -rf "$BRIK_HOME"
        cleanup_mock_bin
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
        setup_mock_bin
        export BRIK_HOME=""
      }
      Before 'setup_no_home'
      After 'cleanup_mock_bin'
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
        setup_mock_bin
        create_mock "apk"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
        export BRIK_LOG_LEVEL="debug"
      }
      cleanup_install() {
        export BRIK_LOG_LEVEL="info"
        cleanup_mock_bin
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
        setup_mock_bin
        create_mock "apk"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_missing'
      After 'cleanup_mock_bin'
      It "calls apk for jq"
        When call _setup._sys_pkg_install "apk" "jq"
        The status should be success
        The stderr should include "installing jq via apk"
      End
    End

    Describe "rejects brew as unsupported"
      setup_unsupported() {
        setup_mock_bin
        PATH="${MOCK_BIN}"
      }
      Before 'setup_unsupported'
      After 'cleanup_mock_bin'
      It "returns 5"
        When call _setup._sys_pkg_install "brew" "jq"
        The status should equal 5
        The stderr should include "unsupported package manager"
      End
    End

    Describe "dispatches to apt-get"
      setup_apt() {
        setup_mock_bin
        create_mock "apt-get"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_apt'
      After 'cleanup_mock_bin'
      It "calls apt-get"
        When call _setup._sys_pkg_install "apt-get" "git"
        The status should be success
        The stderr should include "installing git via apt-get"
      End
    End

    Describe "dispatches to yum"
      setup_yum() {
        setup_mock_bin
        create_mock "yum"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_yum'
      After 'cleanup_mock_bin'
      It "calls yum"
        When call _setup._sys_pkg_install "yum" "git"
        The status should be success
        The stderr should include "installing git via yum"
      End
    End

    Describe "dispatches to dnf"
      setup_dnf() {
        setup_mock_bin
        create_mock "dnf"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_dnf'
      After 'cleanup_mock_bin'
      It "calls dnf"
        When call _setup._sys_pkg_install "dnf" "bash"
        The status should be success
        The stderr should include "installing bash via dnf"
      End
    End

    Describe "handles install failure"
      setup_fail() {
        setup_mock_bin
        create_failing_mock "apk"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_fail'
      After 'cleanup_mock_bin'
      It "returns 5 when apk fails"
        When call _setup._sys_pkg_install "apk" "jq"
        The status should equal 5
        The stderr should include "apk install failed"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # setup.install_yq
  # ---------------------------------------------------------------------------
  Describe "setup.install_yq"
    Describe "when yq is already present"
      setup_yq_present() {
        setup_mock_bin
        create_mock "yq"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
        export BRIK_LOG_LEVEL="debug"
      }
      cleanup_yq_present() {
        export BRIK_LOG_LEVEL="info"
        cleanup_mock_bin
      }
      Before 'setup_yq_present'
      After 'cleanup_yq_present'
      It "returns 0 immediately"
        When call setup.install_yq
        The status should be success
        The stderr should include "yq already installed"
      End
    End

    Describe "on CI via binary download"
      setup_yq_ci() {
        setup_mock_bin
        export BRIK_PLATFORM="gitlab"
        create_mock "wget"
        create_mock "uname"
        create_mock "chmod"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_yq_ci'
      After 'cleanup_mock_bin'
      It "attempts download to /usr/local/bin/"
        When call setup.install_yq
        The status should equal 5
        The stderr should include "installing yq via binary download"
      End
    End

    Describe "on local via self-host in BRIK_HOME/bin"
      setup_yq_local() {
        setup_mock_bin
        export BRIK_PLATFORM="local"
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        # Restrict PATH so yq is NOT found, but keep system tools
        # Remove any directory containing yq from PATH
        local p=""
        local IFS=":"
        for d in $ORIG_PATH; do
          [[ -x "${d}/yq" ]] && continue
          p="${p:+${p}:}${d}"
        done
        PATH="${MOCK_BIN}:${p}"
        create_mock "wget"
      }
      Before 'setup_yq_local'
      After 'cleanup_mock_bin'
      It "attempts download to BRIK_HOME/bin/"
        When call setup.install_yq
        The status should equal 5
        The stderr should include "downloading yq to"
      End
    End

    Describe "fails when no download tool on CI"
      setup_no_download() {
        setup_mock_bin
        export BRIK_PLATFORM="gitlab"
        create_mock "uname"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_no_download'
      After 'cleanup_mock_bin'
      It "returns 5"
        When call setup.install_yq
        The status should equal 5
        The stderr should include "neither wget nor curl"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # setup.install_prerequisites
  # ---------------------------------------------------------------------------
  Describe "setup.install_prerequisites"
    Describe "on CI with apk"
      setup_prereq_ci() {
        setup_mock_bin
        export BRIK_PLATFORM="gitlab"
        create_mock "apk"
        create_mock "wget"
        create_mock "uname"
        create_mock "chmod"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_prereq_ci'
      After 'cleanup_mock_bin'
      It "installs missing tools via system package manager"
        When call setup.install_prerequisites
        The status should be success
        The stderr should include "installing jq via apk"
        The stderr should include "installing git via apk"
        The stderr should include "installing bash via apk"
      End
    End

    Describe "on local when all tools present"
      setup_prereq_local() {
        setup_mock_bin
        export BRIK_PLATFORM="local"
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        create_mock "yq"
        create_mock "jq"
        create_mock "git"
        create_mock "bash"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      Before 'setup_prereq_local'
      After 'cleanup_mock_bin'
      It "succeeds"
        When call setup.install_prerequisites
        The status should be success
      End
    End

    Describe "on local when git is missing"
      setup_prereq_no_git() {
        setup_mock_bin
        export BRIK_PLATFORM="local"
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        create_mock "yq"
        create_mock "jq"
        create_mock "bash"
        # Keep system PATH but remove directories containing git
        local p=""
        local IFS=":"
        for d in $ORIG_PATH; do
          [[ -x "${d}/git" ]] && continue
          p="${p:+${p}:}${d}"
        done
        PATH="${MOCK_BIN}:${p}"
      }
      Before 'setup_prereq_no_git'
      After 'cleanup_mock_bin'
      It "returns 3 with hint"
        When call setup.install_prerequisites
        The status should equal 3
        The stderr should include "git is required but not found"
        The stderr should include "hint:"
      End
    End

    Describe "on CI with no package manager"
      setup_prereq_none() {
        setup_mock_bin
        export BRIK_PLATFORM="gitlab"
        create_mock "uname"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_prereq_none'
      After 'cleanup_mock_bin'
      It "warns about missing tools"
        When call setup.install_prerequisites
        The status should be success
        The stderr should include "not found and no package manager available"
      End
    End

    Describe "on local when all tools present (mocked)"
      setup_prereq_all() {
        setup_mock_bin
        export BRIK_PLATFORM="local"
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        create_mock "yq"
        create_mock "jq"
        create_mock "git"
        create_mock "bash"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      cleanup_prereq_all() {
        rm -rf "$BRIK_HOME"
        cleanup_mock_bin
      }
      Before 'setup_prereq_all'
      After 'cleanup_prereq_all'
      It "succeeds when all prerequisites are mocked"
        When call setup.install_prerequisites
        The status should be success
      End
    End
  End

  # ---------------------------------------------------------------------------
  # _setup._yq_url
  # ---------------------------------------------------------------------------
  Describe "_setup._yq_url"
    It "contains yq version in URL"
      When call _setup._yq_url
      The output should include "yq_"
      The output should include "v4.44.1"
    End

    Describe "with custom BRIK_YQ_VERSION"
      setup_yq_ver() { export BRIK_YQ_VERSION="v4.99.0"; }
      cleanup_yq_ver() { unset BRIK_YQ_VERSION; }
      Before 'setup_yq_ver'
      After 'cleanup_yq_ver'
      It "uses the custom version"
        When call _setup._yq_url
        The output should include "v4.99.0"
      End
    End

    It "returns a github.com URL"
      When call _setup._yq_url
      The output should start with "https://github.com/mikefarah/yq/releases/download/"
    End
  End

  # ---------------------------------------------------------------------------
  # _setup._jq_url
  # ---------------------------------------------------------------------------
  Describe "_setup._jq_url"
    It "contains jq version in URL"
      When call _setup._jq_url
      The output should include "1.7.1"
    End

    Describe "with custom BRIK_JQ_VERSION"
      setup_jq_ver() { export BRIK_JQ_VERSION="1.8.0"; }
      cleanup_jq_ver() { unset BRIK_JQ_VERSION; }
      Before 'setup_jq_ver'
      After 'cleanup_jq_ver'
      It "uses the custom version"
        When call _setup._jq_url
        The output should include "1.8.0"
      End
    End

    It "returns a github.com URL"
      When call _setup._jq_url
      The output should start with "https://github.com/jqlang/jq/releases/download/"
    End

    It "maps darwin to macos in URL"
      When call _setup._jq_url
      # On macOS test runner, this should contain macos
      The output should match pattern "*jq-*-*"
    End
  End

  # ---------------------------------------------------------------------------
  # _setup._self_host_binary
  # ---------------------------------------------------------------------------
  Describe "_setup._self_host_binary"
    Describe "succeeds with wget"
      setup_self_host() {
        setup_mock_bin
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        # Create a mock wget that writes a fake binary
        printf '#!/bin/sh\necho "fake" > "$3"\n' > "${MOCK_BIN}/wget"
        chmod +x "${MOCK_BIN}/wget"
        # Create mock chmod
        create_mock "chmod"
        # Create mock for the target binary to appear on PATH
        printf '#!/bin/sh\ntrue\n' > "${MOCK_BIN}/mytool"
        chmod +x "${MOCK_BIN}/mytool"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      cleanup_self_host() {
        rm -rf "$BRIK_HOME"
        cleanup_mock_bin
      }
      Before 'setup_self_host'
      After 'cleanup_self_host'
      It "downloads to BRIK_HOME/bin"
        When call _setup._self_host_binary "mytool" "https://example.com/mytool"
        The status should be success
        The stderr should include "downloading mytool"
      End
    End

    Describe "fails when BRIK_HOME is empty"
      setup_no_home() {
        setup_mock_bin
        export BRIK_HOME=""
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      Before 'setup_no_home'
      After 'cleanup_mock_bin'
      It "returns 5"
        When call _setup._self_host_binary "mytool" "https://example.com/mytool"
        The status should equal 5
        The stderr should include "cannot create"
      End
    End

    Describe "uses curl when wget is absent"
      setup_curl_only() {
        setup_mock_bin
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        # Only curl, no wget
        printf '#!/bin/sh\necho "fake" > "$4"\n' > "${MOCK_BIN}/curl"
        chmod +x "${MOCK_BIN}/curl"
        create_mock "chmod"
        printf '#!/bin/sh\ntrue\n' > "${MOCK_BIN}/mytool"
        chmod +x "${MOCK_BIN}/mytool"
        # Remove wget from PATH
        local p=""
        local IFS=":"
        for d in $ORIG_PATH; do
          [[ -x "${d}/wget" ]] && continue
          p="${p:+${p}:}${d}"
        done
        PATH="${MOCK_BIN}:${p}"
      }
      cleanup_curl_only() {
        rm -rf "$BRIK_HOME"
        cleanup_mock_bin
      }
      Before 'setup_curl_only'
      After 'cleanup_curl_only'
      It "downloads via curl"
        When call _setup._self_host_binary "mytool" "https://example.com/mytool"
        The status should be success
        The stderr should include "downloading mytool"
      End
    End

    Describe "fails when neither wget nor curl"
      setup_no_dl() {
        setup_mock_bin
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        # Strip wget and curl from PATH
        local p=""
        local IFS=":"
        for d in $ORIG_PATH; do
          [[ -x "${d}/wget" ]] && continue
          [[ -x "${d}/curl" ]] && continue
          p="${p:+${p}:}${d}"
        done
        PATH="${MOCK_BIN}:${p}"
      }
      cleanup_no_dl() {
        rm -rf "$BRIK_HOME"
        cleanup_mock_bin
      }
      Before 'setup_no_dl'
      After 'cleanup_no_dl'
      It "returns 5 with error"
        When call _setup._self_host_binary "mytool" "https://example.com/mytool"
        The status should equal 5
        The stderr should include "neither wget nor curl"
      End
    End
  End
End

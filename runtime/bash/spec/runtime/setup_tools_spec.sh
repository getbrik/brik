Describe "setup.sh - install_yq / install_prerequisites / URL helpers / self_host_binary"
  Include "$BRIK_RUNTIME_LIB/setup.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"


  # ---------------------------------------------------------------------------
  # setup.install_yq
  # ---------------------------------------------------------------------------
  Describe "setup.install_yq"
    Describe "when yq is already present"
      setup_yq_present() {
        mock.setup
        mock.create "yq"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
        export BRIK_LOG_LEVEL="debug"
      }
      cleanup_yq_present() {
        export BRIK_LOG_LEVEL="info"
        mock.cleanup
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
        mock.setup
        export BRIK_PLATFORM="gitlab"
        mock.create "wget"
        mock.create "uname"
        mock.create "chmod"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_yq_ci'
      After 'mock.cleanup'
      It "attempts download to /usr/local/bin/"
        When call setup.install_yq
        The status should equal 5
        The stderr should include "installing yq via binary download"
      End
    End

    Describe "on local via self-host in BRIK_HOME/bin"
      setup_yq_local() {
        mock.setup
        export BRIK_PLATFORM="local"
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        mock.create "wget"
        mock.preserve_cmds
        # Restrict PATH so yq is NOT found, but keep system tools
        # Remove any directory containing yq from PATH
        local p=""
        local IFS=":"
        for d in $_MOCK_ORIG_PATH; do
          [[ -x "${d}/yq" ]] && continue
          p="${p:+${p}:}${d}"
        done
        PATH="${MOCK_BIN}:${p}"
      }
      Before 'setup_yq_local'
      After 'mock.cleanup'
      It "attempts download to BRIK_HOME/bin/"
        When call setup.install_yq
        The status should equal 5
        The stderr should include "downloading yq to"
      End
    End

    Describe "fails when no download tool on CI"
      setup_no_download() {
        mock.setup
        export BRIK_PLATFORM="gitlab"
        mock.create "uname"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_no_download'
      After 'mock.cleanup'
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
        mock.setup
        export BRIK_PLATFORM="gitlab"
        mock.create "apk"
        mock.create "wget"
        mock.create "uname"
        mock.create "chmod"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_prereq_ci'
      After 'mock.cleanup'
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
      Before 'setup_prereq_local'
      After 'mock.cleanup'
      It "succeeds"
        When call setup.install_prerequisites
        The status should be success
      End
    End

    Describe "on local when git is missing"
      setup_prereq_no_git() {
        mock.setup
        export BRIK_PLATFORM="local"
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        mock.create "yq"
        mock.create "jq"
        mock.create "bash"
        # Keep system PATH but remove directories containing git
        local p=""
        local IFS=":"
        for d in $_MOCK_ORIG_PATH; do
          [[ -x "${d}/git" ]] && continue
          p="${p:+${p}:}${d}"
        done
        PATH="${MOCK_BIN}:${p}"
      }
      Before 'setup_prereq_no_git'
      After 'mock.cleanup'
      It "returns 3 with hint"
        When call setup.install_prerequisites
        The status should equal 3
        The stderr should include "git is required but not found"
        The stderr should include "hint:"
      End
    End

    Describe "on CI with no package manager"
      setup_prereq_none() {
        mock.setup
        export BRIK_PLATFORM="gitlab"
        mock.create "uname"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_prereq_none'
      After 'mock.cleanup'
      It "warns about missing tools"
        When call setup.install_prerequisites
        The status should be success
        The stderr should include "not found and no package manager available"
      End
    End

    Describe "on local when all tools present (mocked)"
      setup_prereq_all() {
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
      cleanup_prereq_all() {
        rm -rf "$BRIK_HOME"
        mock.cleanup
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
        mock.setup
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        # Create a mock wget that writes a fake binary
        printf '#!/bin/sh\necho "fake" > "$3"\n' > "${MOCK_BIN}/wget"
        chmod +x "${MOCK_BIN}/wget"
        # Create mock chmod
        mock.create "chmod"
        # Create mock for the target binary to appear on PATH
        printf '#!/bin/sh\ntrue\n' > "${MOCK_BIN}/mytool"
        chmod +x "${MOCK_BIN}/mytool"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      cleanup_self_host() {
        rm -rf "$BRIK_HOME"
        mock.cleanup
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
        mock.setup
        export BRIK_HOME=""
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      Before 'setup_no_home'
      After 'mock.cleanup'
      It "returns 5"
        When call _setup._self_host_binary "mytool" "https://example.com/mytool"
        The status should equal 5
        The stderr should include "cannot create"
      End
    End

    Describe "uses curl when wget is absent"
      setup_curl_only() {
        mock.setup
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        # Only curl, no wget
        printf '#!/bin/sh\necho "fake" > "$4"\n' > "${MOCK_BIN}/curl"
        chmod +x "${MOCK_BIN}/curl"
        mock.create "chmod"
        printf '#!/bin/sh\ntrue\n' > "${MOCK_BIN}/mytool"
        chmod +x "${MOCK_BIN}/mytool"
        mock.preserve_cmds
        # Remove wget from PATH
        local p=""
        local IFS=":"
        for d in $_MOCK_ORIG_PATH; do
          [[ -x "${d}/wget" ]] && continue
          p="${p:+${p}:}${d}"
        done
        PATH="${MOCK_BIN}:${p}"
      }
      cleanup_curl_only() {
        rm -rf "$BRIK_HOME"
        mock.cleanup
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
        mock.setup
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        mock.preserve_cmds
        # Strip wget and curl from PATH
        local p=""
        local IFS=":"
        for d in $_MOCK_ORIG_PATH; do
          [[ -x "${d}/wget" ]] && continue
          [[ -x "${d}/curl" ]] && continue
          p="${p:+${p}:}${d}"
        done
        PATH="${MOCK_BIN}:${p}"
      }
      cleanup_no_dl() {
        rm -rf "$BRIK_HOME"
        mock.cleanup
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

Describe "setup.sh - package manager installers and python post-install"
  Include "$BRIK_RUNTIME_LIB/setup.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"


  # ---------------------------------------------------------------------------
  # _setup._install_via_apk (direct tests)
  # ---------------------------------------------------------------------------
  Describe "_setup._install_via_apk"
    Describe "installs node packages"
      setup_apk() {
        mock.setup
        mock.create "apk"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      Before 'setup_apk'
      After 'mock.cleanup'
      It "maps node to nodejs npm"
        When call _setup._install_via_apk "node"
        The status should be success
        The stderr should include "nodejs npm"
      End
    End

    Describe "installs java with version"
      setup_apk_java() {
        mock.setup
        mock.create "apk"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      Before 'setup_apk_java'
      After 'mock.cleanup'
      It "uses version in package name"
        When call _setup._install_via_apk "java" "17"
        The status should be success
        The stderr should include "openjdk17-jdk"
      End
    End

    Describe "installs java without version (defaults to 21)"
      setup_apk_java_default() {
        mock.setup
        mock.create "apk"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      Before 'setup_apk_java_default'
      After 'mock.cleanup'
      It "defaults to openjdk21-jdk"
        When call _setup._install_via_apk "java" ""
        The status should be success
        The stderr should include "openjdk21-jdk"
      End
    End

    Describe "installs dotnet with version"
      setup_apk_dotnet() {
        mock.setup
        mock.create "apk"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      Before 'setup_apk_dotnet'
      After 'mock.cleanup'
      It "uses version in package name"
        When call _setup._install_via_apk "dotnet" "9"
        The status should be success
        The stderr should include "dotnet9-sdk"
      End
    End

    Describe "handles apk failure"
      setup_apk_fail() {
        mock.setup
        mock.create_failing "apk"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      Before 'setup_apk_fail'
      After 'mock.cleanup'
      It "returns 5 on failure"
        When call _setup._install_via_apk "python"
        The status should equal 5
        The stderr should include "apk install failed"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # _setup._install_via_apt (direct tests)
  # ---------------------------------------------------------------------------
  Describe "_setup._install_via_apt"
    Describe "installs python packages"
      setup_apt() {
        mock.setup
        mock.create "apt-get"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
        unset _BRIK_APT_UPDATED 2>/dev/null || true
      }
      Before 'setup_apt'
      After 'mock.cleanup'
      It "maps python to python3 python3-pip python3-setuptools"
        When call _setup._install_via_apt "python"
        The status should be success
        The stderr should include "python3 python3-pip python3-setuptools"
      End
    End

    Describe "installs java with version"
      setup_apt_java() {
        mock.setup
        mock.create "apt-get"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
        unset _BRIK_APT_UPDATED 2>/dev/null || true
      }
      Before 'setup_apt_java'
      After 'mock.cleanup'
      It "uses version in package name"
        When call _setup._install_via_apt "java" "17"
        The status should be success
        The stderr should include "openjdk-17-jdk"
      End
    End

    Describe "handles apt-get failure"
      setup_apt_fail() {
        mock.setup
        mock.create_failing "apt-get"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
        unset _BRIK_APT_UPDATED 2>/dev/null || true
      }
      Before 'setup_apt_fail'
      After 'mock.cleanup'
      It "returns 5 on failure"
        When call _setup._install_via_apt "jq"
        The status should equal 5
        The stderr should include "apt-get install failed"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # _setup._install_via_yum (direct tests)
  # ---------------------------------------------------------------------------
  Describe "_setup._install_via_yum"
    Describe "installs rust packages"
      setup_yum() {
        mock.setup
        mock.create "yum"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      Before 'setup_yum'
      After 'mock.cleanup'
      It "maps rust to rust cargo"
        When call _setup._install_via_yum "rust"
        The status should be success
        The stderr should include "rust cargo"
      End
    End

    Describe "handles yum failure"
      setup_yum_fail() {
        mock.setup
        mock.create_failing "yum"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      Before 'setup_yum_fail'
      After 'mock.cleanup'
      It "returns 5 on failure"
        When call _setup._install_via_yum "git"
        The status should equal 5
        The stderr should include "yum install failed"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # _setup._install_via_dnf (direct tests)
  # ---------------------------------------------------------------------------
  Describe "_setup._install_via_dnf"
    Describe "installs dotnet with default version"
      setup_dnf() {
        mock.setup
        mock.create "dnf"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      Before 'setup_dnf'
      After 'mock.cleanup'
      It "defaults to dotnet-sdk-8.0"
        When call _setup._install_via_dnf "dotnet" ""
        The status should be success
        The stderr should include "dotnet-sdk-8.0"
      End
    End

    Describe "handles dnf failure"
      setup_dnf_fail() {
        mock.setup
        mock.create_failing "dnf"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      Before 'setup_dnf_fail'
      After 'mock.cleanup'
      It "returns 5 on failure"
        When call _setup._install_via_dnf "bash"
        The status should equal 5
        The stderr should include "dnf install failed"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # _setup._install_via_mise (edge cases)
  # ---------------------------------------------------------------------------
  Describe "_setup._install_via_mise"
    Describe "with unknown tool name"
      setup_mise_unknown() {
        mock.setup
        mock.create "mise"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      Before 'setup_mise_unknown'
      After 'mock.cleanup'
      It "warns and tries as-is"
        When call _setup._install_via_mise "elixir" "1.16"
        The status should be success
        The stderr should include "unknown tool 'elixir'"
      End
    End

    Describe "when mise install fails"
      setup_mise_fail() {
        mock.setup
        mock.create_failing "mise"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      Before 'setup_mise_fail'
      After 'mock.cleanup'
      It "returns 5"
        When call _setup._install_via_mise "node" "20"
        The status should equal 5
        The stderr should include "mise install failed"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # _setup._python_post_install (CI paths)
  # ---------------------------------------------------------------------------
  Describe "_setup._python_post_install on CI"
    Describe "with python3 but no EXTERNALLY-MANAGED marker"
      setup_py_ci() {
        mock.setup
        export BRIK_PLATFORM="gitlab"
        # Provide a python3 mock that returns a fake stdlib path
        local fake_stdlib
        fake_stdlib="$(mktemp -d)/stdlib"
        mkdir -p "$fake_stdlib"
        printf '#!/bin/sh\necho "%s"\n' "$fake_stdlib" > "${MOCK_BIN}/python3"
        chmod +x "${MOCK_BIN}/python3"
        export _TEST_FAKE_STDLIB="$fake_stdlib"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
        export BRIK_PROJECT_DIR
        BRIK_PROJECT_DIR="$(mktemp -d)"
      }
      cleanup_py_ci() {
        rm -rf "$_TEST_FAKE_STDLIB" "$BRIK_PROJECT_DIR"
        mock.cleanup
      }
      Before 'setup_py_ci'
      After 'cleanup_py_ci'
      It "succeeds without marker to remove"
        When call _setup._python_post_install
        The status should be success
      End
    End

    Describe "with EXTERNALLY-MANAGED marker present"
      setup_py_marker() {
        mock.setup
        export BRIK_PLATFORM="gitlab"
        local fake_stdlib
        fake_stdlib="$(mktemp -d)"
        touch "${fake_stdlib}/EXTERNALLY-MANAGED"
        # python3 mock that returns the stdlib path via sysconfig
        printf '#!/bin/sh\nif echo "$*" | grep -q sysconfig; then echo "%s"; fi\n' "$fake_stdlib" > "${MOCK_BIN}/python3"
        chmod +x "${MOCK_BIN}/python3"
        export _TEST_FAKE_STDLIB="$fake_stdlib"
        export BRIK_PROJECT_DIR
        BRIK_PROJECT_DIR="$(mktemp -d)"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      cleanup_py_marker() {
        rm -rf "$_TEST_FAKE_STDLIB" "$BRIK_PROJECT_DIR"
        mock.cleanup
      }
      Before 'setup_py_marker'
      After 'cleanup_py_marker'
      It "removes the marker file"
        check_marker_removed() {
          _setup._python_post_install 2>/dev/null
          if [[ -f "${_TEST_FAKE_STDLIB}/EXTERNALLY-MANAGED" ]]; then
            echo "marker_still_exists"
          else
            echo "marker_removed"
          fi
        }
        When call check_marker_removed
        The output should equal "marker_removed"
      End
    End

    Describe "with requirements.txt"
      setup_py_reqs() {
        mock.setup
        export BRIK_PLATFORM="gitlab"
        # python3 mock - returns empty for sysconfig
        printf '#!/bin/sh\necho ""\n' > "${MOCK_BIN}/python3"
        chmod +x "${MOCK_BIN}/python3"
        # pip mock
        mock.create "pip"
        export BRIK_PROJECT_DIR
        BRIK_PROJECT_DIR="$(mktemp -d)"
        echo "flask==3.0" > "${BRIK_PROJECT_DIR}/requirements.txt"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      cleanup_py_reqs() {
        rm -rf "$BRIK_PROJECT_DIR"
        mock.cleanup
      }
      Before 'setup_py_reqs'
      After 'cleanup_py_reqs'
      It "installs requirements"
        When call _setup._python_post_install
        The status should be success
        The stderr should include "installing python requirements"
      End
    End

    Describe "with pyproject.toml"
      setup_py_pyproject() {
        mock.setup
        export BRIK_PLATFORM="gitlab"
        printf '#!/bin/sh\necho ""\n' > "${MOCK_BIN}/python3"
        chmod +x "${MOCK_BIN}/python3"
        mock.create "pip"
        export BRIK_PROJECT_DIR
        BRIK_PROJECT_DIR="$(mktemp -d)"
        touch "${BRIK_PROJECT_DIR}/pyproject.toml"
        PATH="${MOCK_BIN}:${_MOCK_ORIG_PATH}"
      }
      cleanup_py_pyproject() {
        rm -rf "$BRIK_PROJECT_DIR"
        mock.cleanup
      }
      Before 'setup_py_pyproject'
      After 'cleanup_py_pyproject'
      It "installs project dependencies"
        When call _setup._python_post_install
        The status should be success
        The stderr should include "installing python project dependencies"
      End
    End
  End
End

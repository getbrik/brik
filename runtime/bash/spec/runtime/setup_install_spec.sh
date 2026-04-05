Describe "setup.sh - install_stack / check_stack / prepare_env"
  Include "$BRIK_RUNTIME_LIB/setup.sh"

  # ---------------------------------------------------------------------------
  # Shared helpers (same as setup_spec.sh)
  # ---------------------------------------------------------------------------

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

  create_mock() {
    local name="$1"
    printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$name" "$MOCK_LOG" > "${MOCK_BIN}/${name}"
    chmod +x "${MOCK_BIN}/${name}"
  }

  create_failing_mock() {
    local name="$1"
    printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 1\n' "$name" "$MOCK_LOG" > "${MOCK_BIN}/${name}"
    chmod +x "${MOCK_BIN}/${name}"
  }

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
        setup_mock_bin
        create_mock "node"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      Before 'setup_stack_present'
      After 'cleanup_mock_bin'
      It "returns 0 for node"
        When call setup.install_stack "node"
        The status should be success
        The stderr should include "already available"
      End
    End

    Describe "on CI with apk for node"
      setup_stack_ci() {
        setup_mock_bin
        export BRIK_PLATFORM="gitlab"
        create_mock "apk"
        PATH="${MOCK_BIN}"
        export BRIK_BUILD_NODE_VERSION="20"
      }
      cleanup_stack_ci() {
        unset BRIK_BUILD_NODE_VERSION
        cleanup_mock_bin
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
        setup_mock_bin
        export BRIK_PLATFORM="gitlab"
        create_mock "apk"
        PATH="${MOCK_BIN}"
        export BRIK_BUILD_JAVA_VERSION="21"
      }
      cleanup_stack_java() {
        unset BRIK_BUILD_JAVA_VERSION
        cleanup_mock_bin
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
        setup_mock_bin
        export BRIK_PLATFORM="gitlab"
        create_mock "apk"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_stack_python'
      After 'cleanup_mock_bin'
      It "installs python"
        When call setup.install_stack "python"
        The status should be success
        The stderr should include "installing python via apk"
      End
    End

    Describe "on CI with apk for rust"
      setup_stack_rust() {
        setup_mock_bin
        export BRIK_PLATFORM="gitlab"
        create_mock "apk"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_stack_rust'
      After 'cleanup_mock_bin'
      It "installs rust"
        When call setup.install_stack "rust"
        The status should be success
        The stderr should include "installing rust via apk"
      End
    End

    Describe "on CI with apk for dotnet"
      setup_stack_dotnet() {
        setup_mock_bin
        export BRIK_PLATFORM="gitlab"
        create_mock "apk"
        PATH="${MOCK_BIN}"
        export BRIK_BUILD_DOTNET_VERSION="8"
      }
      cleanup_stack_dotnet() {
        unset BRIK_BUILD_DOTNET_VERSION
        cleanup_mock_bin
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
        setup_mock_bin
        export BRIK_PLATFORM="local"
        create_mock "mise"
        PATH="${MOCK_BIN}"
        export BRIK_BUILD_NODE_VERSION="20"
      }
      cleanup_stack_mise() {
        unset BRIK_BUILD_NODE_VERSION
        cleanup_mock_bin
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
        setup_mock_bin
        export BRIK_PLATFORM="local"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_stack_no_mise'
      After 'cleanup_mock_bin'
      It "returns 3 with hint"
        When call setup.install_stack "node"
        The status should equal 3
        The stderr should include "not found on PATH"
        The stderr should include "hint:"
      End
    End

    Describe "on CI handles install failure"
      setup_stack_fail() {
        setup_mock_bin
        export BRIK_PLATFORM="gitlab"
        create_failing_mock "apk"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_stack_fail'
      After 'cleanup_mock_bin'
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
        setup_mock_bin
        create_mock "node"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      Before 'setup_check_present'
      After 'cleanup_mock_bin'
      It "returns 0 for node"
        When call setup.check_stack "node"
        The status should be success
        The stderr should include "verified"
      End
    End

    Describe "when tool is missing"
      setup_check_missing() {
        setup_mock_bin
        PATH="${MOCK_BIN}"
      }
      Before 'setup_check_missing'
      After 'cleanup_mock_bin'

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
        export BRIK_PLATFORM="${ORIG_PLATFORM:-}"
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
        setup_mock_bin
        export BRIK_PLATFORM="gitlab"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_no_python'
      After 'cleanup_mock_bin'
      It "returns 0 immediately"
        When call _setup._python_post_install
        The status should be success
      End
    End
  End

  # ---------------------------------------------------------------------------
  # setup.prepare_env
  # ---------------------------------------------------------------------------
  Describe "setup.prepare_env"
    Describe "without stack (mocked local)"
      setup_env_empty() {
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
      cleanup_env_empty() {
        rm -rf "$BRIK_HOME"
        cleanup_mock_bin
      }
      Before 'setup_env_empty'
      After 'cleanup_env_empty'
      It "installs only prerequisites"
        When call setup.prepare_env ""
        The status should be success
        The stderr should include "preparing runtime environment"
        The stderr should include "runtime environment ready"
      End
    End

    Describe "without stack argument (mocked local)"
      setup_env_noarg() {
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
      cleanup_env_noarg() {
        rm -rf "$BRIK_HOME"
        cleanup_mock_bin
      }
      Before 'setup_env_noarg'
      After 'cleanup_env_noarg'
      It "installs only prerequisites"
        When call setup.prepare_env
        The status should be success
        The stderr should include "preparing runtime environment"
        The stderr should include "runtime environment ready"
      End
    End

    Describe "with stack already present (mocked node)"
      setup_env_present() {
        setup_mock_bin
        export BRIK_PLATFORM="local"
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        create_mock "yq"
        create_mock "jq"
        create_mock "git"
        create_mock "bash"
        create_mock "node"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      cleanup_env_present() {
        rm -rf "$BRIK_HOME"
        cleanup_mock_bin
      }
      Before 'setup_env_present'
      After 'cleanup_env_present'
      It "succeeds"
        When call setup.prepare_env "node"
        The status should be success
        The stderr should include "runtime environment ready"
      End
    End

    Describe "with missing stack on local without mise"
      setup_env_no_mgr() {
        setup_mock_bin
        export BRIK_PLATFORM="local"
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        create_mock "yq"
        create_mock "jq"
        # Keep system PATH but remove directories containing java
        local p=""
        local IFS=":"
        for d in $ORIG_PATH; do
          [[ -x "${d}/java" ]] && continue
          [[ -x "${d}/mise" ]] && continue
          p="${p:+${p}:}${d}"
        done
        PATH="${MOCK_BIN}:${p}"
      }
      Before 'setup_env_no_mgr'
      After 'cleanup_mock_bin'
      It "returns error for missing stack"
        When call setup.prepare_env "java"
        The status should equal 3
        The stderr should include "stack installation failed"
      End
    End

    Describe "full flow on CI with apk"
      setup_env_ci() {
        setup_mock_bin
        export BRIK_PLATFORM="gitlab"
        create_mock "apk"
        create_mock "node"
        create_mock "uname"
        create_mock "wget"
        create_mock "chmod"
        PATH="${MOCK_BIN}"
        export BRIK_BUILD_NODE_VERSION="20"
      }
      cleanup_env_ci() {
        unset BRIK_BUILD_NODE_VERSION
        cleanup_mock_bin
      }
      Before 'setup_env_ci'
      After 'cleanup_env_ci'
      It "installs prerequisites and reports ready"
        When call setup.prepare_env "node"
        The status should be success
        The stderr should include "preparing runtime environment"
        The stderr should include "runtime environment ready"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # _setup._install_via_apk (direct tests)
  # ---------------------------------------------------------------------------
  Describe "_setup._install_via_apk"
    Describe "installs node packages"
      setup_apk() {
        setup_mock_bin
        create_mock "apk"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      Before 'setup_apk'
      After 'cleanup_mock_bin'
      It "maps node to nodejs npm"
        When call _setup._install_via_apk "node"
        The status should be success
        The stderr should include "nodejs npm"
      End
    End

    Describe "installs java with version"
      setup_apk_java() {
        setup_mock_bin
        create_mock "apk"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      Before 'setup_apk_java'
      After 'cleanup_mock_bin'
      It "uses version in package name"
        When call _setup._install_via_apk "java" "17"
        The status should be success
        The stderr should include "openjdk17-jdk"
      End
    End

    Describe "installs java without version (defaults to 21)"
      setup_apk_java_default() {
        setup_mock_bin
        create_mock "apk"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      Before 'setup_apk_java_default'
      After 'cleanup_mock_bin'
      It "defaults to openjdk21-jdk"
        When call _setup._install_via_apk "java" ""
        The status should be success
        The stderr should include "openjdk21-jdk"
      End
    End

    Describe "installs dotnet with version"
      setup_apk_dotnet() {
        setup_mock_bin
        create_mock "apk"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      Before 'setup_apk_dotnet'
      After 'cleanup_mock_bin'
      It "uses version in package name"
        When call _setup._install_via_apk "dotnet" "9"
        The status should be success
        The stderr should include "dotnet9-sdk"
      End
    End

    Describe "handles apk failure"
      setup_apk_fail() {
        setup_mock_bin
        create_failing_mock "apk"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      Before 'setup_apk_fail'
      After 'cleanup_mock_bin'
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
        setup_mock_bin
        create_mock "apt-get"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
        unset _BRIK_APT_UPDATED 2>/dev/null || true
      }
      Before 'setup_apt'
      After 'cleanup_mock_bin'
      It "maps python to python3 python3-pip python3-setuptools"
        When call _setup._install_via_apt "python"
        The status should be success
        The stderr should include "python3 python3-pip python3-setuptools"
      End
    End

    Describe "installs java with version"
      setup_apt_java() {
        setup_mock_bin
        create_mock "apt-get"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
        unset _BRIK_APT_UPDATED 2>/dev/null || true
      }
      Before 'setup_apt_java'
      After 'cleanup_mock_bin'
      It "uses version in package name"
        When call _setup._install_via_apt "java" "17"
        The status should be success
        The stderr should include "openjdk-17-jdk"
      End
    End

    Describe "handles apt-get failure"
      setup_apt_fail() {
        setup_mock_bin
        create_failing_mock "apt-get"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
        unset _BRIK_APT_UPDATED 2>/dev/null || true
      }
      Before 'setup_apt_fail'
      After 'cleanup_mock_bin'
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
        setup_mock_bin
        create_mock "yum"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      Before 'setup_yum'
      After 'cleanup_mock_bin'
      It "maps rust to rust cargo"
        When call _setup._install_via_yum "rust"
        The status should be success
        The stderr should include "rust cargo"
      End
    End

    Describe "handles yum failure"
      setup_yum_fail() {
        setup_mock_bin
        create_failing_mock "yum"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      Before 'setup_yum_fail'
      After 'cleanup_mock_bin'
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
        setup_mock_bin
        create_mock "dnf"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      Before 'setup_dnf'
      After 'cleanup_mock_bin'
      It "defaults to dotnet-sdk-8.0"
        When call _setup._install_via_dnf "dotnet" ""
        The status should be success
        The stderr should include "dotnet-sdk-8.0"
      End
    End

    Describe "handles dnf failure"
      setup_dnf_fail() {
        setup_mock_bin
        create_failing_mock "dnf"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      Before 'setup_dnf_fail'
      After 'cleanup_mock_bin'
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
        setup_mock_bin
        create_mock "mise"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      Before 'setup_mise_unknown'
      After 'cleanup_mock_bin'
      It "warns and tries as-is"
        When call _setup._install_via_mise "elixir" "1.16"
        The status should be success
        The stderr should include "unknown tool 'elixir'"
      End
    End

    Describe "when mise install fails"
      setup_mise_fail() {
        setup_mock_bin
        create_failing_mock "mise"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      Before 'setup_mise_fail'
      After 'cleanup_mock_bin'
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
        setup_mock_bin
        export BRIK_PLATFORM="gitlab"
        # Provide a python3 mock that returns a fake stdlib path
        local fake_stdlib
        fake_stdlib="$(mktemp -d)/stdlib"
        mkdir -p "$fake_stdlib"
        printf '#!/bin/sh\necho "%s"\n' "$fake_stdlib" > "${MOCK_BIN}/python3"
        chmod +x "${MOCK_BIN}/python3"
        export _TEST_FAKE_STDLIB="$fake_stdlib"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
        export BRIK_PROJECT_DIR
        BRIK_PROJECT_DIR="$(mktemp -d)"
      }
      cleanup_py_ci() {
        rm -rf "$_TEST_FAKE_STDLIB" "$BRIK_PROJECT_DIR"
        cleanup_mock_bin
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
        setup_mock_bin
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
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      cleanup_py_marker() {
        rm -rf "$_TEST_FAKE_STDLIB" "$BRIK_PROJECT_DIR"
        cleanup_mock_bin
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
        setup_mock_bin
        export BRIK_PLATFORM="gitlab"
        # python3 mock - returns empty for sysconfig
        printf '#!/bin/sh\necho ""\n' > "${MOCK_BIN}/python3"
        chmod +x "${MOCK_BIN}/python3"
        # pip mock
        create_mock "pip"
        export BRIK_PROJECT_DIR
        BRIK_PROJECT_DIR="$(mktemp -d)"
        echo "flask==3.0" > "${BRIK_PROJECT_DIR}/requirements.txt"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      cleanup_py_reqs() {
        rm -rf "$BRIK_PROJECT_DIR"
        cleanup_mock_bin
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
        setup_mock_bin
        export BRIK_PLATFORM="gitlab"
        printf '#!/bin/sh\necho ""\n' > "${MOCK_BIN}/python3"
        chmod +x "${MOCK_BIN}/python3"
        create_mock "pip"
        export BRIK_PROJECT_DIR
        BRIK_PROJECT_DIR="$(mktemp -d)"
        touch "${BRIK_PROJECT_DIR}/pyproject.toml"
        PATH="${MOCK_BIN}:${ORIG_PATH}"
      }
      cleanup_py_pyproject() {
        rm -rf "$BRIK_PROJECT_DIR"
        cleanup_mock_bin
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

  # ---------------------------------------------------------------------------
  # setup.install_stack -- additional CI edge cases
  # ---------------------------------------------------------------------------
  Describe "setup.install_stack CI edge cases"
    Describe "on CI with no package manager (fallback to check)"
      setup_stack_no_mgr() {
        setup_mock_bin
        export BRIK_PLATFORM="gitlab"
        PATH="${MOCK_BIN}"
      }
      Before 'setup_stack_no_mgr'
      After 'cleanup_mock_bin'
      It "falls back to check_stack and returns 3"
        When call setup.install_stack "node"
        The status should equal 3
        The stderr should include "no system package manager detected"
      End
    End

    Describe "on CI reads version from env var"
      setup_stack_ver() {
        setup_mock_bin
        export BRIK_PLATFORM="gitlab"
        create_mock "apk"
        PATH="${MOCK_BIN}"
        export BRIK_BUILD_RUST_VERSION=""
      }
      cleanup_stack_ver() {
        unset BRIK_BUILD_RUST_VERSION
        cleanup_mock_bin
      }
      Before 'setup_stack_ver'
      After 'cleanup_stack_ver'
      It "passes empty version through"
        When call setup.install_stack "rust"
        The status should be success
        The stderr should include "rust cargo"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # setup.install_prerequisites -- additional local edge cases
  # ---------------------------------------------------------------------------
  Describe "setup.install_prerequisites local edge cases"
    Describe "on local when bash is missing"
      setup_prereq_no_bash() {
        setup_mock_bin
        export BRIK_PLATFORM="local"
        export BRIK_HOME
        BRIK_HOME="$(mktemp -d)"
        create_mock "yq"
        create_mock "jq"
        create_mock "git"
        # Keep system PATH but remove directories containing bash
        local p=""
        local IFS=":"
        for d in $ORIG_PATH; do
          [[ -x "${d}/bash" ]] && continue
          p="${p:+${p}:}${d}"
        done
        PATH="${MOCK_BIN}:${p}"
      }
      Before 'setup_prereq_no_bash'
      After 'cleanup_mock_bin'
      It "returns 3 with hint"
        When call setup.install_prerequisites
        The status should equal 3
        The stderr should include "bash is required but not found"
      End
    End
  End
End

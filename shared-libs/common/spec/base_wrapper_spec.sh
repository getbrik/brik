Describe "base-wrapper.sh"

  # =========================================================================
  # brik.wrapper.validate_home
  # =========================================================================
  Describe "brik.wrapper.validate_home"
    Include "$BRIK_HOME/shared-libs/common/scripts/base-wrapper.sh"

    It "returns BRIK_EXIT_INVALID_ENV when given empty string"
      When call brik.wrapper.validate_home ""
      The status should equal 4
      The error should include "BRIK_HOME is not set"
    End

    It "returns BRIK_EXIT_INVALID_ENV when directory does not exist"
      When call brik.wrapper.validate_home "/nonexistent/path"
      The status should equal 4
      The error should include "does not exist"
    End

    Describe "with partial runtime"
      setup_partial() {
        _test_dir="$(mktemp -d)"
        mkdir -p "${_test_dir}/runtime/bash/lib/core"
        touch "${_test_dir}/runtime/bash/lib/core/_loader.sh"
      }
      cleanup_partial() { rm -rf "$_test_dir"; }
      Before 'setup_partial'
      After 'cleanup_partial'

      It "returns BRIK_EXIT_INVALID_ENV when stage.sh is missing"
        When call brik.wrapper.validate_home "$_test_dir"
        The status should equal 4
        The error should include "stage.sh not found"
      End
    End

    Describe "with runtime but no loader"
      setup_no_loader() {
        _test_dir="$(mktemp -d)"
        mkdir -p "${_test_dir}/runtime/bash/lib/runtime"
        mkdir -p "${_test_dir}/runtime/bash/lib/core"
        touch "${_test_dir}/runtime/bash/lib/runtime/stage.sh"
      }
      cleanup_no_loader() { rm -rf "$_test_dir"; }
      Before 'setup_no_loader'
      After 'cleanup_no_loader'

      It "returns BRIK_EXIT_INVALID_ENV when _loader.sh is missing"
        When call brik.wrapper.validate_home "$_test_dir"
        The status should equal 4
        The error should include "_loader.sh not found"
      End
    End

    It "succeeds with valid BRIK_HOME"
      When call brik.wrapper.validate_home "$BRIK_HOME"
      The status should be success
    End

    It "exports BRIK_HOME after validation"
      check_export() {
        brik.wrapper.validate_home "$BRIK_HOME" 2>/dev/null
        printf '%s' "$BRIK_HOME"
      }
      When call check_export
      The output should be present
    End

    It "exports _BRIK_RUNTIME_DIR after validation"
      check_runtime_dir() {
        brik.wrapper.validate_home "$BRIK_HOME" 2>/dev/null
        printf '%s' "$_BRIK_RUNTIME_DIR"
      }
      When call check_runtime_dir
      The output should include "runtime/bash/lib/runtime"
    End

    It "exports _BRIK_CORE_DIR after validation"
      check_core_dir() {
        brik.wrapper.validate_home "$BRIK_HOME" 2>/dev/null
        printf '%s' "$_BRIK_CORE_DIR"
      }
      When call check_core_dir
      The output should include "runtime/bash/lib/core"
    End
  End

  # =========================================================================
  # brik.wrapper.set_standard_env
  # =========================================================================
  Describe "brik.wrapper.set_standard_env"
    Include "$BRIK_HOME/shared-libs/common/scripts/base-wrapper.sh"

    setup_standard() {
      brik.wrapper.validate_home "$BRIK_HOME" 2>/dev/null
      export BRIK_PROJECT_DIR
      BRIK_PROJECT_DIR="$(mktemp -d)"
      export BRIK_PLATFORM="test"
    }
    cleanup_standard() { rm -rf "$BRIK_PROJECT_DIR"; }
    Before 'setup_standard'
    After 'cleanup_standard'

    It "sets BRIK_WORKSPACE from BRIK_PROJECT_DIR"
      check_workspace() {
        brik.wrapper.set_standard_env
        printf '%s' "$BRIK_WORKSPACE"
      }
      When call check_workspace
      The output should equal "$BRIK_PROJECT_DIR"
    End

    It "sets BRIK_CONFIG_FILE with brik.yml"
      check_config() {
        brik.wrapper.set_standard_env
        printf '%s' "$BRIK_CONFIG_FILE"
      }
      When call check_config
      The output should include "brik.yml"
    End

    It "sets BRIK_LOG_DIR to default"
      check_logdir() {
        unset BRIK_LOG_DIR 2>/dev/null || true
        brik.wrapper.set_standard_env
        printf '%s' "$BRIK_LOG_DIR"
      }
      When call check_logdir
      The output should include "/tmp/brik/logs"
    End

    It "sets BRIK_LIB to core dir"
      check_lib() {
        brik.wrapper.set_standard_env
        printf '%s' "$BRIK_LIB"
      }
      When call check_lib
      The output should include "runtime/bash/lib/core"
    End

    It "preserves pre-set BRIK_LOG_DIR"
      check_custom_logdir() {
        export BRIK_LOG_DIR="/custom/logs"
        brik.wrapper.set_standard_env
        printf '%s' "$BRIK_LOG_DIR"
      }
      When call check_custom_logdir
      The output should equal "/custom/logs"
    End
  End

  # =========================================================================
  # brik.wrapper.bootstrap
  # =========================================================================
  Describe "brik.wrapper.bootstrap"
    Include "$BRIK_HOME/shared-libs/common/scripts/base-wrapper.sh"

    setup_bootstrap() {
      brik.wrapper.validate_home "$BRIK_HOME" 2>/dev/null
      export BRIK_PROJECT_DIR
      BRIK_PROJECT_DIR="$(mktemp -d)"
      export BRIK_PLATFORM="test"
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
      brik.wrapper.set_standard_env
    }
    cleanup_bootstrap() {
      rm -rf "$BRIK_PROJECT_DIR" "$BRIK_LOG_DIR"
    }
    Before 'setup_bootstrap'
    After 'cleanup_bootstrap'

    It "makes stage.run available"
      check_stagerun() {
        brik.wrapper.bootstrap 2>/dev/null
        declare -f stage.run >/dev/null 2>&1 && echo "available" || echo "missing"
      }
      When call check_stagerun
      The output should equal "available"
    End

    It "makes config.get available"
      check_configget() {
        brik.wrapper.bootstrap 2>/dev/null
        declare -f config.get >/dev/null 2>&1 && echo "available" || echo "missing"
      }
      When call check_configget
      The output should equal "available"
    End

    It "makes stages.init available"
      check_stagesinit() {
        brik.wrapper.bootstrap 2>/dev/null
        declare -f stages.init >/dev/null 2>&1 && echo "available" || echo "missing"
      }
      When call check_stagesinit
      The output should equal "available"
    End
  End

  # =========================================================================
  # brik.wrapper.load_config
  # =========================================================================
  Describe "brik.wrapper.load_config"
    Include "$BRIK_HOME/shared-libs/common/scripts/base-wrapper.sh"

    Describe "with valid config"
      setup_config() {
        brik.wrapper.validate_home "$BRIK_HOME" 2>/dev/null
        export BRIK_PROJECT_DIR
        BRIK_PROJECT_DIR="$(mktemp -d)"
        export BRIK_PLATFORM="test"
        export BRIK_CONFIG_FILE
        BRIK_CONFIG_FILE="$(mktemp)"
        printf 'version: 1\nproject:\n  name: base-test\n  stack: node\n' > "$BRIK_CONFIG_FILE"
        export BRIK_LOG_DIR
        BRIK_LOG_DIR="$(mktemp -d)"
        brik.wrapper.set_standard_env
        brik.wrapper.bootstrap 2>/dev/null
      }
      cleanup_config() {
        rm -f "$BRIK_CONFIG_FILE"
        rm -rf "$BRIK_PROJECT_DIR" "$BRIK_LOG_DIR"
      }
      Before 'setup_config'
      After 'cleanup_config'

      It "succeeds with valid config"
        When call brik.wrapper.load_config
        The status should be success
        The error should be present
      End

      It "exports BRIK_PROJECT_NAME from config"
        check_name() {
          brik.wrapper.load_config 2>/dev/null
          printf '%s' "${BRIK_PROJECT_NAME:-}"
        }
        When call check_name
        The output should equal "base-test"
      End
    End

    Describe "with missing config"
      setup_no_config() {
        brik.wrapper.validate_home "$BRIK_HOME" 2>/dev/null
        export BRIK_PROJECT_DIR
        BRIK_PROJECT_DIR="$(mktemp -d)"
        export BRIK_PLATFORM="test"
        export BRIK_CONFIG_FILE="/nonexistent/brik.yml"
        export BRIK_LOG_DIR
        BRIK_LOG_DIR="$(mktemp -d)"
        brik.wrapper.set_standard_env
        brik.wrapper.bootstrap 2>/dev/null
      }
      cleanup_no_config() {
        rm -rf "$BRIK_PROJECT_DIR" "$BRIK_LOG_DIR"
      }
      Before 'setup_no_config'
      After 'cleanup_no_config'

      It "returns BRIK_EXIT_CONFIG_ERROR when config is missing"
        When call brik.wrapper.load_config
        The status should equal 7
        The error should include "failed to read config"
      End
    End
  End

  # =========================================================================
  # brik.wrapper.run_stage
  # =========================================================================
  Describe "brik.wrapper.run_stage"
    Include "$BRIK_HOME/shared-libs/common/scripts/base-wrapper.sh"

    setup_run_stage() {
      export BRIK_CONFIG_FILE
      BRIK_CONFIG_FILE="$(mktemp)"
      printf "version: 1\nproject:\n  name: test-project\n  stack: node\nquality:\n  lint:\n    enabled: false\n" > "$BRIK_CONFIG_FILE"
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
      export BRIK_WORKSPACE
      BRIK_WORKSPACE="$(mktemp -d)"
      export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
      export BRIK_PLATFORM="test"
      export BRIK_LOG_LEVEL="info"

      MOCK_SEC_BIN="$(mktemp -d)"
      for tool in semgrep osv-scanner gitleaks; do
        printf '#!/usr/bin/env bash\nexit 0\n' > "${MOCK_SEC_BIN}/${tool}"
        chmod +x "${MOCK_SEC_BIN}/${tool}"
      done
      ORIG_PATH_BASE="$PATH"
      export PATH="${MOCK_SEC_BIN}:${PATH}"

      brik.wrapper.validate_home "$BRIK_HOME" 2>/dev/null
      brik.wrapper.set_standard_env
      brik.wrapper.bootstrap 2>/dev/null
      brik.wrapper.load_config 2>/dev/null || true
    }
    cleanup_run_stage() {
      export PATH="$ORIG_PATH_BASE"
      rm -f "$BRIK_CONFIG_FILE"
      rm -rf "$BRIK_LOG_DIR" "$BRIK_WORKSPACE" "$MOCK_SEC_BIN"
    }
    Before 'setup_run_stage'
    After 'cleanup_run_stage'

    It "returns BRIK_EXIT_INVALID_INPUT for empty stage name"
      When call brik.wrapper.run_stage ""
      The status should equal 2
      The error should include "stage name is required"
    End

    It "returns BRIK_EXIT_INVALID_INPUT for unknown stage"
      When call brik.wrapper.run_stage "foobar"
      The status should equal 2
      The error should include "unknown stage"
    End

    It "runs init stage successfully"
      When call brik.wrapper.run_stage "init"
      The status should be success
      The output should include "project: test-project"
      The error should be present
    End

    It "dispatches quality to lint (backward compat)"
      When call brik.wrapper.run_stage "quality"
      The status should be success
      The output should include "lint"
      The error should be present
    End

    It "dispatches security to scan (backward compat)"
      When call brik.wrapper.run_stage "security"
      The status should be success
      The output should be present
      The error should be present
    End

    It "runs lint stage and writes context"
      run_lint_check() {
        brik.wrapper.run_stage "lint" >/dev/null 2>&1
        local context_file
        context_file="$(ls "${BRIK_LOG_DIR}"/context-lint-* 2>/dev/null | head -1)"
        if [[ -n "$context_file" ]]; then
          grep "^BRIK_LINT_STATUS=" "$context_file" | cut -d= -f2
        else
          echo "no_context"
        fi
      }
      When call run_lint_check
      The output should equal "skipped"
    End

    It "generates summary JSON with correct stage name"
      run_and_check() {
        brik.wrapper.run_stage "init" >/dev/null 2>&1
        local summary="${BRIK_LOG_DIR}/init-summary.json"
        if [[ -f "$summary" ]] && command -v jq >/dev/null 2>&1; then
          jq -r '.stage_name' "$summary"
        else
          echo "no_summary_or_jq"
        fi
      }
      When call run_and_check
      The output should equal "init"
    End
  End

  # =========================================================================
  # Exit code constants availability
  # =========================================================================
  Describe "exit code constants"
    Include "$BRIK_HOME/shared-libs/common/scripts/base-wrapper.sh"

    It "defines BRIK_EXIT_INVALID_ENV"
      When call printf '%s' "$BRIK_EXIT_INVALID_ENV"
      The output should equal "4"
    End

    It "defines BRIK_EXIT_CONFIG_ERROR"
      When call printf '%s' "$BRIK_EXIT_CONFIG_ERROR"
      The output should equal "7"
    End

    It "defines BRIK_EXIT_INVALID_INPUT"
      When call printf '%s' "$BRIK_EXIT_INVALID_INPUT"
      The output should equal "2"
    End

    It "defines BRIK_EXIT_FAILURE"
      When call printf '%s' "$BRIK_EXIT_FAILURE"
      The output should equal "1"
    End
  End

  # =========================================================================
  # Guard against double-sourcing
  # =========================================================================
  Describe "double-source guard"
    Include "$BRIK_HOME/shared-libs/common/scripts/base-wrapper.sh"

    It "sets _BRIK_BASE_WRAPPER_LOADED"
      When call printf '%s' "$_BRIK_BASE_WRAPPER_LOADED"
      The output should equal "1"
    End
  End
End

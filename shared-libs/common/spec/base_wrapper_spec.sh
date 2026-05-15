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
        mkdir -p "${_test_dir}/lib/pipeline"
        touch "${_test_dir}/lib/pipeline/loader.sh"
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
        mkdir -p "${_test_dir}/lib/pipeline"
        touch "${_test_dir}/lib/pipeline/stage.sh"
      }
      cleanup_no_loader() { rm -rf "$_test_dir"; }
      Before 'setup_no_loader'
      After 'cleanup_no_loader'

      It "returns BRIK_EXIT_INVALID_ENV when loader.sh is missing"
        When call brik.wrapper.validate_home "$_test_dir"
        The status should equal 4
        The error should include "loader.sh not found"
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

    It "exports _BRIK_PIPELINE_DIR after validation"
      check_pipeline_dir() {
        brik.wrapper.validate_home "$BRIK_HOME" 2>/dev/null
        printf '%s' "$_BRIK_PIPELINE_DIR"
      }
      When call check_pipeline_dir
      The output should include "lib/pipeline"
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

    It "leaves BRIK_LIB empty by default (legacy escape hatch)"
      check_lib() {
        unset BRIK_LIB
        brik.wrapper.set_standard_env
        printf '%s' "${BRIK_LIB:-UNSET}"
      }
      When call check_lib
      The output should equal "UNSET"
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

    It "generates unique BRIK_LOG_DIR when not pre-set"
      check_unique_logdir() {
        unset BRIK_LOG_DIR 2>/dev/null || true
        unset BRIK_DEFAULT_LOG_DIR 2>/dev/null || true
        brik.wrapper.set_standard_env
        local dir1="$BRIK_LOG_DIR"
        unset BRIK_LOG_DIR
        sleep 1
        brik.wrapper.set_standard_env
        local dir2="$BRIK_LOG_DIR"
        if [[ "$dir1" != "$dir2" ]]; then
          echo "unique"
        else
          echo "same"
        fi
      }
      When call check_unique_logdir
      The output should equal "unique"
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

    It "makes pipeline.env.init available"
      check_pipeline_env() {
        brik.wrapper.bootstrap 2>/dev/null
        declare -f pipeline.env.init >/dev/null 2>&1 && echo "available" || echo "missing"
      }
      When call check_pipeline_env
      The output should equal "available"
    End

    It "creates pipeline.env file after bootstrap"
      check_pipeline_env_file() {
        brik.wrapper.bootstrap 2>/dev/null
        if [[ -f "${BRIK_LOG_DIR}/pipeline.env" ]]; then
          echo "exists"
        else
          echo "missing"
        fi
      }
      When call check_pipeline_env_file
      The output should equal "exists"
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
      printf "version: 1\nproject:\n  name: test-project\n  stack: node\n" > "$BRIK_CONFIG_FILE"
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
      export BRIK_WORKSPACE
      BRIK_WORKSPACE="$(mktemp -d)"
      export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
      export BRIK_PLATFORM="test"
      export BRIK_LOG_LEVEL="info"

      MOCK_SEC_BIN="$(mktemp -d)"
      for tool in semgrep osv-scanner gitleaks eslint prettier tsc; do
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
      # Fixture has no quality.lint.* tool, so lint reaches the
      # not-applicable auto-skip branch and returns 0.
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

    It "runs lint stage and records tech.status=success"
      run_lint_check_report() {
        brik.wrapper.run_stage "lint" >/dev/null 2>&1
        local report="${BRIK_LOG_DIR}/aggregate-report.json"
        if [[ -f "$report" ]]; then
          jq -r '.stages[] | select(.name == "lint") | .tech.status // empty' "$report"
        else
          echo "no_report"
        fi
      }
      When call run_lint_check_report
      The output should equal "success"
    End

    It "loads pipeline env variables before running stage"
      check_pipeline_load() {
        _pipeline.env.append "BRIK_TEST_PIPELINE_VAR" "from_pipeline_env"
        brik.wrapper.run_stage "init" >/dev/null 2>&1
        printf '%s' "${BRIK_TEST_PIPELINE_VAR:-}"
      }
      When call check_pipeline_load
      The output should equal "from_pipeline_env"
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
  # brik.wrapper.ensure_artefact_markers
  # =========================================================================
  # CI templates (build.yml, test.yml) declare a fixed set of cache and
  # artefact paths that span all supported stacks. When the active stack
  # only populates one of them, GitLab logs "no matching files" warnings
  # for every other path on every run. The marker function pre-creates the
  # paths with an empty .brik-keep file so the cache/artefact step always
  # finds something and stays silent. Real outputs (npm modules, junit XML,
  # coverage HTML, ...) coexist with the marker without conflict.
  Describe "brik.wrapper.ensure_artefact_markers"
    Include "$BRIK_HOME/shared-libs/common/scripts/base-wrapper.sh"

    setup_ws() {
      _markers_ws="$(mktemp -d)"
    }
    cleanup_ws() {
      # The unwritable-path test chmods .cargo a-w. Restore before rm so
      # the temp dir can be cleaned up regardless of which test ran last.
      [[ -d "$_markers_ws/.cargo" ]] && chmod -R u+w "$_markers_ws/.cargo" 2>/dev/null
      rm -rf "$_markers_ws"
    }
    Before 'setup_ws'
    After 'cleanup_ws'

    It "is callable"
      callable_check() { declare -f brik.wrapper.ensure_artefact_markers >/dev/null; }
      When call callable_check
      The status should be success
    End

    It "fails when no workspace is provided and BRIK_WORKSPACE is unset"
      run_no_workspace() {
        unset BRIK_WORKSPACE
        brik.wrapper.ensure_artefact_markers
      }
      When call run_no_workspace
      The status should equal 4
      The error should include "workspace required"
    End

    It "fails when workspace path is not a directory"
      When call brik.wrapper.ensure_artefact_markers "/nonexistent/path/xyz"
      The status should equal 4
      The error should include "not a directory"
    End

    It "creates a marker in .npm under the given workspace"
      run_markers() {
        brik.wrapper.ensure_artefact_markers "$_markers_ws"
        [[ -f "$_markers_ws/.npm/.brik-keep" ]]
      }
      When call run_markers
      The status should be success
    End

    It "does not alter the caller's PWD"
      run_pwd_check() {
        local before="$PWD"
        brik.wrapper.ensure_artefact_markers "$_markers_ws" >/dev/null 2>&1
        [[ "$PWD" == "$before" ]]
      }
      When call run_pwd_check
      The status should be success
    End

    It "creates markers in every stack cache path under workspace"
      check_all_cache() {
        brik.wrapper.ensure_artefact_markers "$_markers_ws"
        for p in .npm .cache/pip .m2/repository .gradle/caches .gradle/wrapper .cargo/registry .cargo/git .nuget/packages; do
          [[ -f "$_markers_ws/$p/.brik-keep" ]] || return 1
        done
      }
      When call check_all_cache
      The status should be success
    End

    It "creates markers in coverage and reports under workspace"
      check_test_dirs() {
        brik.wrapper.ensure_artefact_markers "$_markers_ws"
        [[ -f "$_markers_ws/coverage/.brik-keep" && -f "$_markers_ws/reports/.brik-keep" ]]
      }
      When call check_test_dirs
      The status should be success
    End

    It "creates markers in build output dirs (build/target/bin/dist)"
      check_build_dirs() {
        brik.wrapper.ensure_artefact_markers "$_markers_ws"
        for p in build target bin dist; do
          [[ -f "$_markers_ws/$p/.brik-keep" ]] || return 1
        done
      }
      When call check_build_dirs
      The status should be success
    End

    It "creates glob placeholders for *.whl, *.tar.gz, reports/*.xml"
      check_globs() {
        brik.wrapper.ensure_artefact_markers "$_markers_ws"
        [[ -f "$_markers_ws/.brik-keep.whl" \
        && -f "$_markers_ws/.brik-keep.tar.gz" \
        && -f "$_markers_ws/reports/.brik-keep.xml" ]]
      }
      When call check_globs
      The status should be success
    End

    It "is idempotent on re-run"
      run_twice() {
        brik.wrapper.ensure_artefact_markers "$_markers_ws"
        brik.wrapper.ensure_artefact_markers "$_markers_ws"
        [[ -f "$_markers_ws/.npm/.brik-keep" ]]
      }
      When call run_twice
      The status should be success
    End

    It "preserves real cache content alongside the marker"
      check_coexistence() {
        mkdir -p "$_markers_ws/.npm"
        : > "$_markers_ws/.npm/real-package.tgz"
        brik.wrapper.ensure_artefact_markers "$_markers_ws"
        [[ -f "$_markers_ws/.npm/.brik-keep" && -f "$_markers_ws/.npm/real-package.tgz" ]]
      }
      When call check_coexistence
      The status should be success
    End

    It "succeeds even when one path is unwritable"
      run_partial_failure() {
        mkdir -p "$_markers_ws/.cargo"
        chmod a-w "$_markers_ws/.cargo"
        brik.wrapper.ensure_artefact_markers "$_markers_ws"
        local rc=$?
        chmod u+w "$_markers_ws/.cargo"
        [[ $rc -eq 0 && -f "$_markers_ws/.npm/.brik-keep" ]]
      }
      When call run_partial_failure
      The status should be success
    End

    It "honors BRIK_WORKSPACE when no argument is passed"
      run_via_env() {
        export BRIK_WORKSPACE="$_markers_ws"
        brik.wrapper.ensure_artefact_markers
        [[ -f "$_markers_ws/.npm/.brik-keep" ]]
      }
      When call run_via_env
      The status should be success
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

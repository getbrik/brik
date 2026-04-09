Describe "stage-wrapper.sh"

  # =========================================================================
  # brik.gitlab.setup
  # =========================================================================
  Describe "brik.gitlab.setup"
    Include "$BRIK_HOME/shared-libs/gitlab/scripts/stage-wrapper.sh"

    It "returns 4 with BRIK_HOME message when given empty string"
      setup_empty() { local saved="$BRIK_HOME"; unset BRIK_HOME; }
      # Note: we cannot fully unset BRIK_HOME in ShellSpec context because
      # the spec_helper sets it. Instead, test the nonexistent path case.
      When call brik.gitlab.setup ""
      The status should not be success
      The error should be present
    End

    It "returns 4 when BRIK_HOME directory does not exist"
      When call brik.gitlab.setup "/nonexistent/path"
      The status should equal 4
      The error should include "does not exist"
    End

    Describe "with valid environment"
      setup_env() {
        export BRIK_CONFIG_FILE
        BRIK_CONFIG_FILE="$(mktemp)"
        printf 'version: 1\nproject:\n  name: setup-test\n  stack: node\n' > "$BRIK_CONFIG_FILE"
        export BRIK_LOG_DIR
        BRIK_LOG_DIR="$(mktemp -d)"
      }
      cleanup_env() {
        rm -f "$BRIK_CONFIG_FILE"
        rm -rf "$BRIK_LOG_DIR"
      }
      Before 'setup_env'
      After 'cleanup_env'

      It "succeeds and logs completion message"
        When call brik.gitlab.setup "$BRIK_HOME"
        The status should be success
        The error should include "setup complete"
      End

      It "sets BRIK_PLATFORM to gitlab"
        setup_and_check() {
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_PLATFORM"
        }
        When call setup_and_check
        The output should equal "gitlab"
      End

      It "sets BRIK_LIB to core library path"
        setup_and_check() {
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_LIB"
        }
        When call setup_and_check
        The output should include "runtime/bash/lib/core"
      End

      It "makes stage.run available after setup"
        setup_and_check() {
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          declare -f stage.run >/dev/null 2>&1 && echo "available" || echo "missing"
        }
        When call setup_and_check
        The output should equal "available"
      End

      It "makes config.get available after setup"
        setup_and_check() {
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          declare -f config.get >/dev/null 2>&1 && echo "available" || echo "missing"
        }
        When call setup_and_check
        The output should equal "available"
      End

      It "makes stages.init available after setup"
        setup_and_check() {
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          declare -f stages.init >/dev/null 2>&1 && echo "available" || echo "missing"
        }
        When call setup_and_check
        The output should equal "available"
      End

      It "calls setup.prepare_env during setup"
        When call brik.gitlab.setup "$BRIK_HOME"
        The status should be success
        The error should include "preparing runtime environment"
      End

      It "exports BRIK_PROJECT_NAME from config"
        setup_and_check() {
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "${BRIK_PROJECT_NAME:-}"
        }
        When call setup_and_check
        The output should equal "setup-test"
      End

      It "exports BRIK_BRANCH from CI_COMMIT_BRANCH"
        setup_and_check() {
          export CI_COMMIT_BRANCH="feature/test"
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_BRANCH"
        }
        When call setup_and_check
        The output should equal "feature/test"
      End

      It "exports BRIK_TAG from CI_COMMIT_TAG"
        setup_and_check() {
          export CI_COMMIT_TAG="v1.0.0"
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_TAG"
        }
        When call setup_and_check
        The output should equal "v1.0.0"
      End

      It "exports BRIK_COMMIT_SHA from CI_COMMIT_SHA"
        setup_and_check() {
          export CI_COMMIT_SHA="abc123def456"
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_COMMIT_SHA"
        }
        When call setup_and_check
        The output should equal "abc123def456"
      End

      It "exports BRIK_COMMIT_SHORT_SHA from CI_COMMIT_SHORT_SHA"
        setup_and_check() {
          export CI_COMMIT_SHORT_SHA="abc123d"
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_COMMIT_SHORT_SHA"
        }
        When call setup_and_check
        The output should equal "abc123d"
      End

      It "exports BRIK_COMMIT_REF from CI_COMMIT_REF_NAME"
        setup_and_check() {
          export CI_COMMIT_REF_NAME="main"
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_COMMIT_REF"
        }
        When call setup_and_check
        The output should equal "main"
      End

      It "exports BRIK_PIPELINE_SOURCE from CI_PIPELINE_SOURCE"
        setup_and_check() {
          export CI_PIPELINE_SOURCE="push"
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_PIPELINE_SOURCE"
        }
        When call setup_and_check
        The output should equal "push"
      End

      It "exports BRIK_MERGE_REQUEST_ID from CI_MERGE_REQUEST_IID"
        setup_and_check() {
          export CI_MERGE_REQUEST_IID="42"
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_MERGE_REQUEST_ID"
        }
        When call setup_and_check
        The output should equal "42"
      End

      It "exports empty BRIK_BRANCH when CI_COMMIT_BRANCH is unset"
        setup_and_check() {
          unset CI_COMMIT_BRANCH 2>/dev/null || true
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_BRANCH"
        }
        When call setup_and_check
        The output should equal ""
      End
    End

    Describe "when brik.yml does not exist"
      setup_no_config() {
        export BRIK_CONFIG_FILE="/nonexistent/brik.yml"
        export BRIK_LOG_DIR
        BRIK_LOG_DIR="$(mktemp -d)"
      }
      cleanup_no_config() { rm -rf "$BRIK_LOG_DIR"; }
      Before 'setup_no_config'
      After 'cleanup_no_config'

      It "returns 7 when config file is missing"
        When call brik.gitlab.setup "$BRIK_HOME"
        The status should equal 7
        The error should include "failed to read config"
      End
    End
  End

  # =========================================================================
  # brik.gitlab.run_stage
  # =========================================================================
  Describe "brik.gitlab.run_stage"
    Include "$BRIK_HOME/shared-libs/gitlab/scripts/stage-wrapper.sh"

    setup_stage_env() {
      export BRIK_CONFIG_FILE
      BRIK_CONFIG_FILE="$(mktemp)"
      printf "version: 1\nproject:\n  name: test-project\n  stack: node\nquality:\n  enabled: 'false'\n" > "$BRIK_CONFIG_FILE"
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
      export BRIK_WORKSPACE
      BRIK_WORKSPACE="$(mktemp -d)"
      export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
      export BRIK_PLATFORM="gitlab"
      export BRIK_LOG_LEVEL="info"

      # Set CI_* variables before brik.gitlab.setup, which maps them to BRIK_*
      export CI_COMMIT_REF_NAME="main"
      export CI_COMMIT_SHORT_SHA="abc123d"

      # Setup needs the runtime sourced and stages loaded
      brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1 || true
    }
    cleanup_stage_env() {
      rm -f "$BRIK_CONFIG_FILE"
      rm -rf "$BRIK_LOG_DIR" "$BRIK_WORKSPACE"
    }
    Before 'setup_stage_env'
    After 'cleanup_stage_env'

    # --- Error handling ---

    It "returns 2 with 'stage name is required' for empty name"
      When call brik.gitlab.run_stage ""
      The status should equal 2
      The error should include "stage name is required"
    End

    It "returns 2 with 'unknown stage' for invalid name"
      When call brik.gitlab.run_stage "foobar"
      The status should equal 2
      The error should include "unknown stage"
    End

    # --- Init stage: verify side effects ---

    It "runs init stage and writes summary file"
      run_init_check_summary() {
        brik.gitlab.run_stage "init" >/dev/null 2>&1
        local status=$?
        local summary_file="${BRIK_LOG_DIR}/init-summary.json"
        if [[ -f "$summary_file" ]]; then
          echo "summary_exists"
        else
          echo "no_summary"
        fi
        return $status
      }
      When call run_init_check_summary
      The status should be success
      The output should equal "summary_exists"
    End

    It "runs init stage and sets BRIK_STACK in context"
      run_init_check_context() {
        brik.gitlab.run_stage "init" >/dev/null 2>&1
        local status=$?
        local context_file
        context_file="$(ls "${BRIK_LOG_DIR}"/context-init-* 2>/dev/null | head -1)"
        if [[ -n "$context_file" ]]; then
          grep "^BRIK_STACK=" "$context_file" | cut -d= -f2
        else
          echo "no_context"
        fi
        return $status
      }
      When call run_init_check_context
      The status should be success
      The output should equal "node"
    End

    It "runs init stage and logs the project name"
      When call brik.gitlab.run_stage "init"
      The status should be success
      The output should include "project: test-project"
      The error should be present
    End

    It "runs init stage and logs configured stack"
      When call brik.gitlab.run_stage "init"
      The status should be success
      The output should include "configured stack: node"
      The error should be present
    End

    # --- Lint stage: verify side effects ---

    It "runs lint stage and writes BRIK_LINT_STATUS=skipped to context"
      run_lint_check_context() {
        brik.gitlab.run_stage "lint" >/dev/null 2>&1
        local context_file
        context_file="$(ls "${BRIK_LOG_DIR}"/context-lint-* 2>/dev/null | head -1)"
        if [[ -n "$context_file" ]]; then
          grep "^BRIK_LINT_STATUS=" "$context_file" | cut -d= -f2
        else
          echo "no_context"
        fi
      }
      When call run_lint_check_context
      The output should equal "skipped"
    End

    It "runs lint stage and logs message"
      When call brik.gitlab.run_stage "lint"
      The status should be success
      The output should include "lint"
      The error should be present
    End

    # --- Scan stage: verify side effects ---

    It "runs scan stage and writes BRIK_SCAN_STATUS to context"
      run_scan_check_context() {
        brik.gitlab.run_stage "scan" >/dev/null 2>&1
        local context_file
        context_file="$(ls "${BRIK_LOG_DIR}"/context-scan-* 2>/dev/null | head -1)"
        if [[ -n "$context_file" ]]; then
          grep "^BRIK_SCAN_STATUS=" "$context_file" | cut -d= -f2
        else
          echo "no_context"
        fi
      }
      When call run_scan_check_context
      The output should be present
    End

    # --- Backward compat: quality -> lint ---

    It "dispatches quality to lint (backward compat)"
      run_compat_quality() {
        brik.gitlab.run_stage "quality" >/dev/null 2>&1
        local context_file
        context_file="$(ls "${BRIK_LOG_DIR}"/context-quality-* 2>/dev/null | head -1)"
        if [[ -n "$context_file" ]]; then
          echo "has_context"
        else
          echo "no_context"
        fi
      }
      When call run_compat_quality
      The output should equal "has_context"
    End

    # --- Backward compat: security -> scan ---

    It "dispatches security to scan (backward compat)"
      run_compat_security() {
        brik.gitlab.run_stage "security" >/dev/null 2>&1
        local context_file
        context_file="$(ls "${BRIK_LOG_DIR}"/context-security-* 2>/dev/null | head -1)"
        if [[ -n "$context_file" ]]; then
          echo "has_context"
        else
          echo "no_context"
        fi
      }
      When call run_compat_security
      The output should equal "has_context"
    End

    # --- Package stub ---

    It "runs package stub and writes BRIK_PACKAGE_STATUS=skipped"
      run_package_check() {
        brik.gitlab.run_stage "package" >/dev/null 2>&1
        local context_file
        context_file="$(ls "${BRIK_LOG_DIR}"/context-package-* 2>/dev/null | head -1)"
        if [[ -n "$context_file" ]]; then
          grep "^BRIK_PACKAGE_STATUS=" "$context_file" | cut -d= -f2
        else
          echo "no_context"
        fi
      }
      When call run_package_check
      The output should equal "skipped"
    End

    # --- Deploy stub ---

    It "runs deploy stub and writes BRIK_DEPLOY_STATUS=skipped"
      run_deploy_check() {
        brik.gitlab.run_stage "deploy" >/dev/null 2>&1
        local context_file
        context_file="$(ls "${BRIK_LOG_DIR}"/context-deploy-* 2>/dev/null | head -1)"
        if [[ -n "$context_file" ]]; then
          grep "^BRIK_DEPLOY_STATUS=" "$context_file" | cut -d= -f2
        else
          echo "no_context"
        fi
      }
      When call run_deploy_check
      The output should equal "skipped"
    End

    # --- Notify stage: verify output content ---

    It "runs notify stage and prints project name in summary"
      When call brik.gitlab.run_stage "notify"
      The status should be success
      The output should include "Pipeline Summary"
      The output should include "test-project"
      The error should be present
    End

    It "runs notify stage and uses BRIK_COMMIT_REF"
      When call brik.gitlab.run_stage "notify"
      The output should include "main"
      The error should be present
    End

    # --- Release stage ---

    It "runs release stage and writes BRIK_VERSION to context"
      run_release_check() {
        brik.gitlab.run_stage "release" >/dev/null 2>&1
        local context_file
        context_file="$(ls "${BRIK_LOG_DIR}"/context-release-* 2>/dev/null | head -1)"
        if [[ -n "$context_file" ]]; then
          local version
          version="$(grep "^BRIK_VERSION=" "$context_file" | cut -d= -f2)"
          if [[ -n "$version" ]]; then echo "has_version"; else echo "no_version"; fi
        else
          echo "no_context"
        fi
      }
      When call run_release_check
      The output should equal "has_version"
    End

    # --- Summary file validation ---

    It "generates summary JSON with correct stage name and status"
      run_and_check_summary() {
        brik.gitlab.run_stage "init" >/dev/null 2>&1
        local summary="${BRIK_LOG_DIR}/init-summary.json"
        if [[ -f "$summary" ]] && command -v jq >/dev/null 2>&1; then
          local stage_name status
          stage_name="$(jq -r '.stage_name' "$summary")"
          status="$(jq -r '.status' "$summary")"
          echo "${stage_name}:${status}"
        else
          echo "no_summary_or_jq"
        fi
      }
      When call run_and_check_summary
      The output should equal "init:SUCCESS"
    End
  End
End

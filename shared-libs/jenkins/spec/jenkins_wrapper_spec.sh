Describe "jenkins-wrapper.sh"

  # =========================================================================
  # brik.jenkins.setup
  # =========================================================================
  Describe "brik.jenkins.setup"
    Include "$BRIK_HOME/shared-libs/jenkins/scripts/jenkins-wrapper.sh"

    It "returns 4 with BRIK_HOME message when given empty string"
      When call brik.jenkins.setup ""
      The status should not be success
      The error should be present
    End

    It "returns 4 when BRIK_HOME directory does not exist"
      When call brik.jenkins.setup "/nonexistent/path"
      The status should equal 4
      The error should include "does not exist"
    End

    Describe "when runtime is missing"
      setup_no_runtime() {
        export _test_dir
        _test_dir="$(mktemp -d)"
        mkdir -p "${_test_dir}/runtime/bash/lib/core"
        touch "${_test_dir}/runtime/bash/lib/core/_loader.sh"
      }
      cleanup_no_runtime() { rm -rf "$_test_dir"; }
      Before 'setup_no_runtime'
      After 'cleanup_no_runtime'

      It "returns 4 when runtime stage.sh is missing"
        When call brik.jenkins.setup "$_test_dir"
        The status should equal 4
        The error should include "stage.sh not found"
      End
    End

    Describe "with valid environment"
      setup_env() {
        export BRIK_CONFIG_FILE
        BRIK_CONFIG_FILE="$(mktemp)"
        printf 'version: 1\nproject:\n  name: jenkins-test\n  stack: node\n' > "$BRIK_CONFIG_FILE"
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
        When call brik.jenkins.setup "$BRIK_HOME"
        The status should be success
        The error should include "setup complete"
      End

      It "sets BRIK_PLATFORM to jenkins"
        setup_and_check() {
          brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_PLATFORM"
        }
        When call setup_and_check
        The output should equal "jenkins"
      End

      It "sets BRIK_LIB to core library path"
        setup_and_check() {
          brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_LIB"
        }
        When call setup_and_check
        The output should include "runtime/bash/lib/core"
      End

      It "makes stage.run available after setup"
        setup_and_check() {
          brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1
          declare -f stage.run >/dev/null 2>&1 && echo "available" || echo "missing"
        }
        When call setup_and_check
        The output should equal "available"
      End

      It "makes config.get available after setup"
        setup_and_check() {
          brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1
          declare -f config.get >/dev/null 2>&1 && echo "available" || echo "missing"
        }
        When call setup_and_check
        The output should equal "available"
      End

      It "makes stages.init available after setup"
        setup_and_check() {
          brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1
          declare -f stages.init >/dev/null 2>&1 && echo "available" || echo "missing"
        }
        When call setup_and_check
        The output should equal "available"
      End

      It "calls setup.prepare_env during setup"
        When call brik.jenkins.setup "$BRIK_HOME"
        The status should be success
        The error should include "preparing runtime environment"
      End

      It "exports BRIK_PROJECT_NAME from config"
        setup_and_check() {
          brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "${BRIK_PROJECT_NAME:-}"
        }
        When call setup_and_check
        The output should equal "jenkins-test"
      End

      # --- Jenkins variable normalization ---

      It "strips origin/ prefix from GIT_BRANCH"
        setup_and_check() {
          export GIT_BRANCH="origin/main"
          brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_BRANCH"
        }
        When call setup_and_check
        The output should equal "main"
      End

      It "strips origin/ prefix from GIT_BRANCH with feature branch"
        setup_and_check() {
          export GIT_BRANCH="origin/feature/my-feature"
          brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_BRANCH"
        }
        When call setup_and_check
        The output should equal "feature/my-feature"
      End

      It "keeps GIT_BRANCH as-is when no origin/ prefix"
        setup_and_check() {
          export GIT_BRANCH="develop"
          brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_BRANCH"
        }
        When call setup_and_check
        The output should equal "develop"
      End

      It "exports BRIK_TAG from TAG_NAME"
        setup_and_check() {
          export TAG_NAME="v2.0.0"
          brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_TAG"
        }
        When call setup_and_check
        The output should equal "v2.0.0"
      End

      It "exports BRIK_COMMIT_SHA from GIT_COMMIT"
        setup_and_check() {
          export GIT_COMMIT="abc123def456789012345678901234567890abcd"
          brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_COMMIT_SHA"
        }
        When call setup_and_check
        The output should equal "abc123def456789012345678901234567890abcd"
      End

      It "exports BRIK_COMMIT_SHORT_SHA as first 7 chars of GIT_COMMIT"
        setup_and_check() {
          export GIT_COMMIT="abc123def456789012345678901234567890abcd"
          brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_COMMIT_SHORT_SHA"
        }
        When call setup_and_check
        The output should equal "abc123d"
      End

      It "sets BRIK_COMMIT_REF from BRIK_TAG when tag is present"
        setup_and_check() {
          export TAG_NAME="v1.0.0"
          export GIT_BRANCH="origin/main"
          brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_COMMIT_REF"
        }
        When call setup_and_check
        The output should equal "v1.0.0"
      End

      It "sets BRIK_COMMIT_REF from BRIK_BRANCH when no tag"
        setup_and_check() {
          unset TAG_NAME 2>/dev/null || true
          export GIT_BRANCH="origin/develop"
          brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_COMMIT_REF"
        }
        When call setup_and_check
        The output should equal "develop"
      End

      It "sets BRIK_PIPELINE_SOURCE to push by default"
        setup_and_check() {
          brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_PIPELINE_SOURCE"
        }
        When call setup_and_check
        The output should equal "push"
      End

      It "exports BRIK_MERGE_REQUEST_ID from CHANGE_ID"
        setup_and_check() {
          export CHANGE_ID="99"
          brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_MERGE_REQUEST_ID"
        }
        When call setup_and_check
        The output should equal "99"
      End

      It "sets BRIK_PROJECT_DIR from WORKSPACE"
        setup_and_check() {
          export WORKSPACE="/var/jenkins/workspace/my-job"
          brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_PROJECT_DIR"
        }
        When call setup_and_check
        The output should equal "/var/jenkins/workspace/my-job"
      End

      It "exports empty BRIK_BRANCH when GIT_BRANCH is unset"
        setup_and_check() {
          unset GIT_BRANCH 2>/dev/null || true
          brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1
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
        When call brik.jenkins.setup "$BRIK_HOME"
        The status should equal 7
        The error should include "failed to read config"
      End
    End
  End

  # =========================================================================
  # brik.jenkins.run_stage
  # =========================================================================
  Describe "brik.jenkins.run_stage"
    Include "$BRIK_HOME/shared-libs/jenkins/scripts/jenkins-wrapper.sh"

    setup_stage_env() {
      export BRIK_CONFIG_FILE
      BRIK_CONFIG_FILE="$(mktemp)"
      printf "version: 1\nproject:\n  name: test-project\n  stack: node\nquality:\n  lint:\n    enabled: false\n" > "$BRIK_CONFIG_FILE"
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
      export BRIK_WORKSPACE
      BRIK_WORKSPACE="$(mktemp -d)"
      export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
      export BRIK_PLATFORM="jenkins"
      export BRIK_LOG_LEVEL="info"

      # Set Jenkins variables before setup, which maps them to BRIK_*
      export GIT_BRANCH="origin/main"
      export GIT_COMMIT="abc123def456789012345678901234567890abcd"

      # Mock non-negotiable security tools
      MOCK_SEC_BIN="$(mktemp -d)"
      for tool in semgrep osv-scanner gitleaks; do
        printf '#!/usr/bin/env bash\nexit 0\n' > "${MOCK_SEC_BIN}/${tool}"
        chmod +x "${MOCK_SEC_BIN}/${tool}"
      done
      ORIG_PATH_STAGE="$PATH"
      export PATH="${MOCK_SEC_BIN}:${PATH}"

      brik.jenkins.setup "$BRIK_HOME" >/dev/null 2>&1 || true
    }
    cleanup_stage_env() {
      export PATH="$ORIG_PATH_STAGE"
      rm -f "$BRIK_CONFIG_FILE"
      rm -rf "$BRIK_LOG_DIR" "$BRIK_WORKSPACE" "$MOCK_SEC_BIN"
    }
    Before 'setup_stage_env'
    After 'cleanup_stage_env'

    # --- Error handling ---

    It "returns 2 with 'stage name is required' for empty name"
      When call brik.jenkins.run_stage ""
      The status should equal 2
      The error should include "stage name is required"
    End

    It "returns 2 with 'unknown stage' for invalid name"
      When call brik.jenkins.run_stage "foobar"
      The status should equal 2
      The error should include "unknown stage"
    End

    # --- Init stage ---

    It "runs init stage and writes summary file"
      run_init_check_summary() {
        brik.jenkins.run_stage "init" >/dev/null 2>&1
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

    It "runs init stage and logs the project name"
      When call brik.jenkins.run_stage "init"
      The status should be success
      The output should include "project: test-project"
      The error should be present
    End

    # --- Lint stage ---

    It "runs lint stage and writes BRIK_LINT_STATUS=skipped to context"
      run_lint_check_context() {
        brik.jenkins.run_stage "lint" >/dev/null 2>&1
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

    # --- Scan stage ---

    It "runs scan stage and writes BRIK_SCAN_STATUS to context"
      run_scan_check_context() {
        brik.jenkins.run_stage "scan" >/dev/null 2>&1
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

    # --- Backward compat ---

    It "dispatches quality to lint (backward compat)"
      When call brik.jenkins.run_stage "quality"
      The status should be success
      The output should include "lint"
      The error should be present
    End

    It "dispatches security to scan (backward compat)"
      When call brik.jenkins.run_stage "security"
      The status should be success
      The output should be present
      The error should be present
    End

    # --- Notify stage ---

    It "runs notify stage and prints project name in summary"
      When call brik.jenkins.run_stage "notify"
      The status should be success
      The output should include "Pipeline Summary"
      The output should include "test-project"
      The error should be present
    End

    # --- Summary validation ---

    It "generates summary JSON with correct stage name and status"
      run_and_check_summary() {
        brik.jenkins.run_stage "init" >/dev/null 2>&1
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

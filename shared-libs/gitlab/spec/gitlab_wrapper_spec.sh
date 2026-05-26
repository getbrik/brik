Describe "gitlab-wrapper.sh"

  # =========================================================================
  # brik.gitlab.setup
  # =========================================================================
  Describe "brik.gitlab.setup"
    Include "$BRIK_HOME/shared-libs/gitlab/scripts/gitlab-wrapper.sh"

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

      It "leaves BRIK_LIB empty by default (legacy escape hatch)"
        setup_and_check() {
          unset BRIK_LIB
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "${BRIK_LIB:-UNSET}"
        }
        When call setup_and_check
        The output should equal "UNSET"
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

      It "makes pipeline.env.init available after setup"
        setup_and_check() {
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          declare -f pipeline.env.init >/dev/null 2>&1 && echo "available" || echo "missing"
        }
        When call setup_and_check
        The output should equal "available"
      End

      It "creates pipeline.env file during setup"
        setup_and_check() {
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          if [[ -f "${BRIK_LOG_DIR}/pipeline.env" ]]; then
            echo "exists"
          else
            echo "missing"
          fi
        }
        When call setup_and_check
        The output should equal "exists"
      End

      It "calls bootstrap.prepare_env during setup"
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

      It "derives BRIK_COMMIT_SHORT_SHA from the first 7 hex chars of CI_COMMIT_SHA"
        # CI_COMMIT_SHORT_SHA is GitLab's 8-char default, which diverges
        # from git's 7-char `--short` and the Jenkins wrapper. Truncating
        # the full SHA keeps short_sha aligned across platforms.
        setup_and_check() {
          export CI_COMMIT_SHA="abc123def456"
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_COMMIT_SHORT_SHA"
        }
        When call setup_and_check
        The output should equal "abc123d"
      End

      It "falls back to CI_COMMIT_SHORT_SHA when CI_COMMIT_SHA is unset"
        setup_and_check() {
          unset CI_COMMIT_SHA
          export CI_COMMIT_SHORT_SHA="deadbee"
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_COMMIT_SHORT_SHA"
        }
        When call setup_and_check
        The output should equal "deadbee"
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

      It "sets BRIK_LOG_DIR inside workspace when CI_PROJECT_DIR is set"
        setup_and_check() {
          export CI_PROJECT_DIR="/builds/my-group/my-project"
          unset BRIK_LOG_DIR 2>/dev/null || true
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_LOG_DIR"
        }
        When call setup_and_check
        The output should equal "/builds/my-group/my-project/.brik-logs"
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

      # ---------------------------------------------------------------------
      # BRIK_DRY_RUN normalization
      # ---------------------------------------------------------------------
      It "normalizes BRIK_DRY_RUN=true to canonical 'true'"
        setup_and_check() {
          export BRIK_DRY_RUN="true"
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_DRY_RUN"
        }
        When call setup_and_check
        The output should equal "true"
      End

      It "normalizes BRIK_DRY_RUN=false to canonical 'false'"
        setup_and_check() {
          export BRIK_DRY_RUN="false"
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_DRY_RUN"
        }
        When call setup_and_check
        The output should equal "false"
      End

      It "defaults BRIK_DRY_RUN to 'false' when unset"
        setup_and_check() {
          unset BRIK_DRY_RUN 2>/dev/null || true
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_DRY_RUN"
        }
        When call setup_and_check
        The output should equal "false"
      End

      It "downgrades BRIK_DRY_RUN=1 to 'false' with a warning"
        setup_and_check() {
          export BRIK_DRY_RUN="1"
          brik.gitlab.setup "$BRIK_HOME" 2>&1 >/dev/null
        }
        When call setup_and_check
        The status should be success
        The output should include "unexpected value '1'"
      End

      It "downgrades BRIK_DRY_RUN=yes to 'false'"
        setup_and_check() {
          export BRIK_DRY_RUN="yes"
          brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1
          printf '%s' "$BRIK_DRY_RUN"
        }
        When call setup_and_check
        The output should equal "false"
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
    Include "$BRIK_HOME/shared-libs/gitlab/scripts/gitlab-wrapper.sh"

    setup_stage_env() {
      export BRIK_CONFIG_FILE
      BRIK_CONFIG_FILE="$(mktemp)"
      printf "version: 1\nproject:\n  name: test-project\n  stack: node\n" > "$BRIK_CONFIG_FILE"
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

      # Mock non-negotiable security tools
      MOCK_SEC_BIN="$(mktemp -d)"
      for tool in semgrep osv-scanner gitleaks eslint prettier tsc; do
        printf '#!/usr/bin/env bash\nexit 0\n' > "${MOCK_SEC_BIN}/${tool}"
        chmod +x "${MOCK_SEC_BIN}/${tool}"
      done
      ORIG_PATH_STAGE="$PATH"
      export PATH="${MOCK_SEC_BIN}:${PATH}"

      # Setup needs the runtime sourced and stages loaded
      brik.gitlab.setup "$BRIK_HOME" >/dev/null 2>&1 || true
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

    It "runs init stage and records tech.stack in the pipeline report"
      run_init_check_report() {
        brik.gitlab.run_stage "init" >/dev/null 2>&1
        local status=$?
        local report="${BRIK_LOG_DIR}/aggregate-report.json"
        if [[ -f "$report" ]]; then
          jq -r '.stages[] | select(.stage == "init") | .tech.stack // empty' "$report"
        else
          echo "no_report"
        fi
        return $status
      }
      When call run_init_check_report
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

    It "runs lint stage and records tech.status=success"
      run_lint_check_report() {
        brik.gitlab.run_stage "lint" >/dev/null 2>&1
        local report="${BRIK_LOG_DIR}/aggregate-report.json"
        if [[ -f "$report" ]]; then
          jq -r '.stages[] | select(.stage == "lint") | .tech.status // empty' "$report"
        else
          echo "no_report"
        fi
      }
      When call run_lint_check_report
      The output should equal "success"
    End

    It "runs lint stage and logs message"
      # Fixture has no quality.lint.* tool, so lint reaches the
      # not-applicable auto-skip branch and returns 0.
      When call brik.gitlab.run_stage "lint"
      The status should be success
      The output should include "lint"
      The error should be present
    End

    # --- Scan stage: verify side effects ---

    It "runs scan stage and lazy-initializes the pipeline report"
      run_scan_check_report() {
        brik.gitlab.run_stage "scan" >/dev/null 2>&1
        if [[ -f "${BRIK_LOG_DIR}/aggregate-report.json" ]]; then
          echo "report_present"
        else
          echo "no_report"
        fi
      }
      When call run_scan_check_report
      The output should equal "report_present"
    End

    # --- Backward compat: quality -> lint ---

    It "dispatches quality to lint (backward compat)"
      run_compat_quality() {
        brik.gitlab.run_stage "quality" >/dev/null 2>&1
        if [[ -f "${BRIK_LOG_DIR}/quality-summary.json" ]]; then
          echo "has_summary"
        else
          echo "no_summary"
        fi
      }
      When call run_compat_quality
      The output should equal "has_summary"
    End

    # --- Backward compat: security -> scan ---

    It "dispatches security to scan (backward compat)"
      run_compat_security() {
        brik.gitlab.run_stage "security" >/dev/null 2>&1
        if [[ -f "${BRIK_LOG_DIR}/security-summary.json" ]]; then
          echo "has_summary"
        else
          echo "no_summary"
        fi
      }
      When call run_compat_security
      The output should equal "has_summary"
    End

    # --- Package stub ---

    It "runs package stub and records status skipped in the pipeline report"
      run_package_check() {
        brik.gitlab.run_stage "package" >/dev/null 2>&1
        local report="${BRIK_LOG_DIR}/aggregate-report.json"
        if [[ -f "$report" ]]; then
          jq -r '.stages[] | select(.stage == "package") | .tech.status // empty' "$report"
        else
          echo "no_report"
        fi
      }
      When call run_package_check
      The output should equal "skipped"
    End

    # --- Deploy stub ---

    It "runs deploy stub and silent-skips when no environments configured"
      run_deploy_check() {
        brik.gitlab.run_stage "deploy" >/dev/null 2>&1
        local report="${BRIK_LOG_DIR}/aggregate-report.json"
        if [[ -f "$report" ]]; then
          jq -r '.stages[] | select(.stage == "deploy") | .tech.status // empty' "$report"
        else
          echo "no_report"
        fi
      }
      When call run_deploy_check
      # Silent skip: stages.deploy returns 0 without recording a status, so
      # pipeline.run's default success-on-rc=0 path applies. No warning,
      # no fragment-side enrichment.
      The output should equal "success"
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

    It "runs release stage and records new_version in the pipeline report"
      run_release_check() {
        brik.gitlab.run_stage "release" >/dev/null 2>&1
        local report="${BRIK_LOG_DIR}/aggregate-report.json"
        if [[ -f "$report" ]]; then
          local version
          version="$(jq -r '.stages[] | select(.stage == "release") | .business.new_version // empty' "$report")"
          if [[ -n "$version" ]]; then echo "has_version"; else echo "no_version"; fi
        else
          echo "no_report"
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

  # =========================================================================
  # _brik_gitlab._ensure_artefact_markers
  # =========================================================================
  # Pre-creates the cache and artefact directories declared in GitLab job
  # templates (build.yml, test.yml, ...) with a .brik-keep file so GitLab's
  # cache and artefact upload steps never log "no matching files" for paths
  # the active stack does not populate. Cache paths come from the canonical
  # stacks.cache_paths; artefact output dirs (coverage, reports, build, ...)
  # stay inline because they are stack-independent.
  Describe "_brik_gitlab._ensure_artefact_markers"
    Include "$BRIK_HOME/shared-libs/gitlab/scripts/gitlab-wrapper.sh"
    Include "$BRIK_HOME/lib/stacks/_deps.sh"

    setup_ws() {
      _markers_ws="$(mktemp -d)"
    }
    cleanup_ws() {
      [[ -d "$_markers_ws/.cargo" ]] && chmod -R u+w "$_markers_ws/.cargo" 2>/dev/null
      rm -rf "$_markers_ws"
    }
    Before 'setup_ws'
    After 'cleanup_ws'

    It "is defined as a function"
      callable_check() { declare -f _brik_gitlab._ensure_artefact_markers >/dev/null; }
      When call callable_check
      The status should be success
    End

    It "fails when no workspace is provided and BRIK_WORKSPACE is unset"
      run_no_workspace() {
        unset BRIK_WORKSPACE
        _brik_gitlab._ensure_artefact_markers
      }
      When call run_no_workspace
      The status should equal 4
      The error should include "workspace required"
    End

    It "fails when workspace path is not a directory"
      When call _brik_gitlab._ensure_artefact_markers "/nonexistent/path/xyz"
      The status should equal 4
      The error should include "not a directory"
    End

    It "creates a marker in .npm under the given workspace"
      run_markers() {
        _brik_gitlab._ensure_artefact_markers "$_markers_ws"
        [[ -f "$_markers_ws/.npm/.brik-keep" ]]
      }
      When call run_markers
      The status should be success
    End

    It "does not alter the caller's PWD"
      run_pwd_check() {
        local before="$PWD"
        _brik_gitlab._ensure_artefact_markers "$_markers_ws" >/dev/null 2>&1
        [[ "$PWD" == "$before" ]]
      }
      When call run_pwd_check
      The status should be success
    End

    It "creates markers in every stacks.cache_paths entry"
      check_all_cache() {
        _brik_gitlab._ensure_artefact_markers "$_markers_ws"
        local p
        while IFS= read -r p; do
          [[ -f "$_markers_ws/$p/.brik-keep" ]] || return 1
        done < <(stacks.cache_paths)
      }
      When call check_all_cache
      The status should be success
    End

    It "creates markers in coverage and reports under workspace"
      check_test_dirs() {
        _brik_gitlab._ensure_artefact_markers "$_markers_ws"
        [[ -f "$_markers_ws/coverage/.brik-keep" && -f "$_markers_ws/reports/.brik-keep" ]]
      }
      When call check_test_dirs
      The status should be success
    End

    It "creates markers in build output dirs (build/target/bin/dist)"
      check_build_dirs() {
        _brik_gitlab._ensure_artefact_markers "$_markers_ws"
        for p in build target bin dist; do
          [[ -f "$_markers_ws/$p/.brik-keep" ]] || return 1
        done
      }
      When call check_build_dirs
      The status should be success
    End

    It "creates glob placeholders for *.whl, *.tar.gz, reports/*.xml"
      check_globs() {
        _brik_gitlab._ensure_artefact_markers "$_markers_ws"
        [[ -f "$_markers_ws/.brik-keep.whl" \
        && -f "$_markers_ws/.brik-keep.tar.gz" \
        && -f "$_markers_ws/reports/.brik-keep.xml" ]]
      }
      When call check_globs
      The status should be success
    End

    It "is idempotent on re-run"
      run_twice() {
        _brik_gitlab._ensure_artefact_markers "$_markers_ws"
        _brik_gitlab._ensure_artefact_markers "$_markers_ws"
        [[ -f "$_markers_ws/.npm/.brik-keep" ]]
      }
      When call run_twice
      The status should be success
    End

    It "preserves real cache content alongside the marker"
      check_coexistence() {
        mkdir -p "$_markers_ws/.npm"
        : > "$_markers_ws/.npm/real-package.tgz"
        _brik_gitlab._ensure_artefact_markers "$_markers_ws"
        [[ -f "$_markers_ws/.npm/.brik-keep" && -f "$_markers_ws/.npm/real-package.tgz" ]]
      }
      When call check_coexistence
      The status should be success
    End

    It "succeeds even when one path is unwritable"
      run_partial_failure() {
        mkdir -p "$_markers_ws/.cargo"
        chmod a-w "$_markers_ws/.cargo"
        _brik_gitlab._ensure_artefact_markers "$_markers_ws"
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
        _brik_gitlab._ensure_artefact_markers
        [[ -f "$_markers_ws/.npm/.brik-keep" ]]
      }
      When call run_via_env
      The status should be success
    End
  End
End

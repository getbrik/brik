Describe "local-wrapper.sh"

  # =========================================================================
  # brik.local.setup
  # =========================================================================
  Describe "brik.local.setup"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"

    Describe "when BRIK_HOME is empty"
      setup_empty() { unset BRIK_HOME 2>/dev/null || true; }
      Before 'setup_empty'

      It "returns 4 with BRIK_HOME message"
        When call brik.local.setup
        The status should equal 4
        The error should include "BRIK_HOME is not set"
      End
    End

    Describe "when BRIK_HOME directory does not exist"
      setup_bad() { export BRIK_HOME="/nonexistent/path"; }
      Before 'setup_bad'

      It "returns 4"
        When call brik.local.setup
        The status should equal 4
        The error should include "does not exist"
      End
    End

    Describe "with valid environment"
      setup_env() {
        export BRIK_CONFIG_FILE
        BRIK_CONFIG_FILE="$(mktemp)"
        printf 'version: 1\nproject:\n  name: local-test\n  stack: node\n' > "$BRIK_CONFIG_FILE"
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
        When call brik.local.setup
        The status should be success
        The error should include "setup complete"
      End

      It "sets BRIK_PLATFORM to local"
        setup_and_check() {
          brik.local.setup >/dev/null 2>&1
          printf '%s' "$BRIK_PLATFORM"
        }
        When call setup_and_check
        The output should equal "local"
      End

      It "sets BRIK_LIB to core library path"
        setup_and_check() {
          brik.local.setup >/dev/null 2>&1
          printf '%s' "$BRIK_LIB"
        }
        When call setup_and_check
        The output should include "runtime/bash/lib/core"
      End

      It "makes stage.run available after setup"
        setup_and_check() {
          brik.local.setup >/dev/null 2>&1
          declare -f stage.run >/dev/null 2>&1 && echo "available" || echo "missing"
        }
        When call setup_and_check
        The output should equal "available"
      End

      It "makes config.get available after setup"
        setup_and_check() {
          brik.local.setup >/dev/null 2>&1
          declare -f config.get >/dev/null 2>&1 && echo "available" || echo "missing"
        }
        When call setup_and_check
        The output should equal "available"
      End

      It "makes stages.init available after setup"
        setup_and_check() {
          brik.local.setup >/dev/null 2>&1
          declare -f stages.init >/dev/null 2>&1 && echo "available" || echo "missing"
        }
        When call setup_and_check
        The output should equal "available"
      End

      It "calls setup.prepare_env during setup"
        When call brik.local.setup
        The status should be success
        The error should include "preparing runtime environment"
      End

      It "exports BRIK_PROJECT_NAME from config"
        setup_and_check() {
          brik.local.setup >/dev/null 2>&1
          printf '%s' "${BRIK_PROJECT_NAME:-}"
        }
        When call setup_and_check
        The output should equal "local-test"
      End

      It "sets BRIK_PIPELINE_SOURCE to local"
        setup_and_check() {
          brik.local.setup >/dev/null 2>&1
          printf '%s' "$BRIK_PIPELINE_SOURCE"
        }
        When call setup_and_check
        The output should equal "local"
      End

      It "sets BRIK_MERGE_REQUEST_ID to empty"
        setup_and_check() {
          brik.local.setup >/dev/null 2>&1
          printf '%s' "$BRIK_MERGE_REQUEST_ID"
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
        When call brik.local.setup
        The status should equal 7
        The error should include "failed to read config"
      End
    End
  End

  # =========================================================================
  # _brik_local_setup_git_context
  # =========================================================================
  Describe "_brik_local_setup_git_context"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"

    Describe "inside a git repository"
      setup_git() {
        GIT_REPO="$(mktemp -d)"
        git -C "$GIT_REPO" init -q
        git -C "$GIT_REPO" config user.email "test@test.com"
        git -C "$GIT_REPO" config user.name "Test"
        touch "$GIT_REPO/file.txt"
        git -C "$GIT_REPO" add file.txt
        git -C "$GIT_REPO" commit -q -m "initial"
        ORIG_DIR="$(pwd)"
        cd "$GIT_REPO" || return 1
      }
      cleanup_git() {
        cd "$ORIG_DIR" || true
        rm -rf "$GIT_REPO"
      }
      Before 'setup_git'
      After 'cleanup_git'

      It "sets BRIK_COMMIT_SHA to a 40-char hash"
        check_sha() {
          _brik_local_setup_git_context 2>/dev/null
          printf '%s' "${#BRIK_COMMIT_SHA}"
        }
        When call check_sha
        The output should equal "40"
      End

      It "sets BRIK_COMMIT_SHORT_SHA to a short hash"
        check_short_sha() {
          _brik_local_setup_git_context 2>/dev/null
          if [[ ${#BRIK_COMMIT_SHORT_SHA} -ge 7 ]] && [[ ${#BRIK_COMMIT_SHORT_SHA} -le 12 ]]; then
            echo "valid"
          else
            echo "invalid: ${#BRIK_COMMIT_SHORT_SHA}"
          fi
        }
        When call check_short_sha
        The output should equal "valid"
      End

      It "sets BRIK_BRANCH to current branch"
        check_branch() {
          _brik_local_setup_git_context 2>/dev/null
          if [[ -n "$BRIK_BRANCH" ]]; then
            echo "has_branch"
          else
            echo "no_branch"
          fi
        }
        When call check_branch
        The output should equal "has_branch"
      End

      It "sets BRIK_TAG to empty when no tag"
        check_tag() {
          _brik_local_setup_git_context 2>/dev/null
          printf '%s' "$BRIK_TAG"
        }
        When call check_tag
        The output should equal ""
      End

      It "sets BRIK_PIPELINE_SOURCE to local"
        check_source() {
          _brik_local_setup_git_context 2>/dev/null
          printf '%s' "$BRIK_PIPELINE_SOURCE"
        }
        When call check_source
        The output should equal "local"
      End
    End

    Describe "inside a git repo with a tag"
      setup_tagged() {
        GIT_REPO="$(mktemp -d)"
        git -C "$GIT_REPO" init -q
        git -C "$GIT_REPO" config user.email "test@test.com"
        git -C "$GIT_REPO" config user.name "Test"
        touch "$GIT_REPO/file.txt"
        git -C "$GIT_REPO" add file.txt
        git -C "$GIT_REPO" commit -q -m "initial"
        git -C "$GIT_REPO" tag v1.0.0
        ORIG_DIR="$(pwd)"
        cd "$GIT_REPO" || return 1
      }
      cleanup_tagged() {
        cd "$ORIG_DIR" || true
        rm -rf "$GIT_REPO"
      }
      Before 'setup_tagged'
      After 'cleanup_tagged'

      It "sets BRIK_TAG to the exact tag"
        check_tag() {
          _brik_local_setup_git_context 2>/dev/null
          printf '%s' "$BRIK_TAG"
        }
        When call check_tag
        The output should equal "v1.0.0"
      End
    End

    Describe "inside a detached HEAD"
      setup_detached() {
        GIT_REPO="$(mktemp -d)"
        git -C "$GIT_REPO" init -q
        git -C "$GIT_REPO" config user.email "test@test.com"
        git -C "$GIT_REPO" config user.name "Test"
        touch "$GIT_REPO/file.txt"
        git -C "$GIT_REPO" add file.txt
        git -C "$GIT_REPO" commit -q -m "initial"
        local sha
        sha="$(git -C "$GIT_REPO" rev-parse HEAD)"
        git -C "$GIT_REPO" checkout -q "$sha"
        ORIG_DIR="$(pwd)"
        cd "$GIT_REPO" || return 1
      }
      cleanup_detached() {
        cd "$ORIG_DIR" || true
        rm -rf "$GIT_REPO"
      }
      Before 'setup_detached'
      After 'cleanup_detached'

      It "sets BRIK_BRANCH to empty in detached HEAD"
        check_branch() {
          _brik_local_setup_git_context 2>/dev/null
          printf '%s' "$BRIK_BRANCH"
        }
        When call check_branch
        The output should equal ""
      End

      It "still has BRIK_COMMIT_SHA set"
        check_sha() {
          _brik_local_setup_git_context 2>/dev/null
          printf '%s' "${#BRIK_COMMIT_SHA}"
        }
        When call check_sha
        The output should equal "40"
      End
    End

    Describe "outside a git repository"
      setup_no_git() {
        NO_GIT_DIR="$(mktemp -d)"
        ORIG_DIR="$(pwd)"
        cd "$NO_GIT_DIR" || return 1
      }
      cleanup_no_git() {
        cd "$ORIG_DIR" || true
        rm -rf "$NO_GIT_DIR"
      }
      Before 'setup_no_git'
      After 'cleanup_no_git'

      It "warns and sets empty variables"
        When call _brik_local_setup_git_context
        The error should include "not inside a git repository"
      End

      It "sets all git variables to empty"
        check_empty() {
          _brik_local_setup_git_context 2>/dev/null
          if [[ -z "$BRIK_BRANCH" ]] && [[ -z "$BRIK_TAG" ]] && \
             [[ -z "$BRIK_COMMIT_SHA" ]] && [[ -z "$BRIK_COMMIT_SHORT_SHA" ]]; then
            echo "all_empty"
          else
            echo "not_all_empty"
          fi
        }
        When call check_empty
        The output should equal "all_empty"
      End
    End
  End

  # =========================================================================
  # brik.local.run_stage
  # =========================================================================
  Describe "brik.local.run_stage"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"

    setup_stage_env() {
      export BRIK_CONFIG_FILE
      BRIK_CONFIG_FILE="$(mktemp)"
      printf "version: 1\nproject:\n  name: test-project\n  stack: node\nquality:\n  enabled: 'false'\n" > "$BRIK_CONFIG_FILE"
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
      export BRIK_WORKSPACE
      BRIK_WORKSPACE="$(mktemp -d)"
      export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
      export BRIK_LOG_LEVEL="info"
      brik.local.setup >/dev/null 2>&1 || true
    }
    cleanup_stage_env() {
      rm -f "$BRIK_CONFIG_FILE"
      rm -rf "$BRIK_LOG_DIR" "$BRIK_WORKSPACE"
    }
    Before 'setup_stage_env'
    After 'cleanup_stage_env'

    It "returns 2 with 'stage name is required' for empty name"
      When call brik.local.run_stage ""
      The status should equal 2
      The error should include "stage name is required"
    End

    It "returns 2 with 'unknown stage' for invalid name"
      When call brik.local.run_stage "foobar"
      The status should equal 2
      The error should include "unknown stage"
    End

    It "runs init stage successfully"
      When call brik.local.run_stage "init"
      The status should be success
      The output should include "project: test-project"
      The error should be present
    End

    It "runs lint stage successfully"
      When call brik.local.run_stage "lint"
      The status should be success
      The output should include "lint"
      The error should be present
    End

    It "runs scan stage successfully"
      When call brik.local.run_stage "scan"
      The status should be success
      The output should be present
      The error should be present
    End

    It "dispatches quality to lint (backward compat)"
      When call brik.local.run_stage "quality"
      The status should be success
      The output should include "lint"
      The error should be present
    End

    It "dispatches security to scan (backward compat)"
      When call brik.local.run_stage "security"
      The status should be success
      The output should be present
      The error should be present
    End

    It "runs release stage and creates context"
      run_release() {
        brik.local.run_stage "release" >/dev/null 2>&1
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
      When call run_release
      The output should equal "has_version"
    End

    It "runs package stage and writes skipped status"
      run_package() {
        brik.local.run_stage "package" >/dev/null 2>&1
        local context_file
        context_file="$(ls "${BRIK_LOG_DIR}"/context-package-* 2>/dev/null | head -1)"
        if [[ -n "$context_file" ]]; then
          grep "^BRIK_PACKAGE_STATUS=" "$context_file" | cut -d= -f2
        else
          echo "no_context"
        fi
      }
      When call run_package
      The output should equal "skipped"
    End

    It "runs deploy stage and writes skipped status"
      run_deploy() {
        brik.local.run_stage "deploy" >/dev/null 2>&1
        local context_file
        context_file="$(ls "${BRIK_LOG_DIR}"/context-deploy-* 2>/dev/null | head -1)"
        if [[ -n "$context_file" ]]; then
          grep "^BRIK_DEPLOY_STATUS=" "$context_file" | cut -d= -f2
        else
          echo "no_context"
        fi
      }
      When call run_deploy
      The output should equal "skipped"
    End

    It "runs notify stage and prints summary"
      When call brik.local.run_stage "notify"
      The status should be success
      The output should include "Pipeline Summary"
      The error should be present
    End
  End

  # =========================================================================
  # _brik_local_should_skip_stage
  # =========================================================================
  Describe "_brik_local_should_skip_stage"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"

    It "skips release when with_release is false"
      When call _brik_local_should_skip_stage "release" "false" "false" "false"
      The status should be success
    End

    It "does not skip release when with_release is true"
      When call _brik_local_should_skip_stage "release" "true" "false" "false"
      The status should equal 1
    End

    It "skips package when with_package is false"
      When call _brik_local_should_skip_stage "package" "false" "false" "false"
      The status should be success
    End

    It "does not skip package when with_package is true"
      When call _brik_local_should_skip_stage "package" "false" "true" "false"
      The status should equal 1
    End

    It "skips deploy when with_deploy is false"
      When call _brik_local_should_skip_stage "deploy" "false" "false" "false"
      The status should be success
    End

    It "does not skip deploy when with_deploy is true"
      When call _brik_local_should_skip_stage "deploy" "false" "false" "true"
      The status should equal 1
    End

    It "skips notify when with_deploy is false"
      When call _brik_local_should_skip_stage "notify" "false" "false" "false"
      The status should be success
    End

    It "does not skip notify when with_deploy is true"
      When call _brik_local_should_skip_stage "notify" "false" "false" "true"
      The status should equal 1
    End

    It "never skips init"
      When call _brik_local_should_skip_stage "init" "false" "false" "false"
      The status should equal 1
    End

    It "never skips build"
      When call _brik_local_should_skip_stage "build" "false" "false" "false"
      The status should equal 1
    End

    It "never skips lint"
      When call _brik_local_should_skip_stage "lint" "false" "false" "false"
      The status should equal 1
    End

    It "never skips sast"
      When call _brik_local_should_skip_stage "sast" "false" "false" "false"
      The status should equal 1
    End

    It "never skips scan"
      When call _brik_local_should_skip_stage "scan" "false" "false" "false"
      The status should equal 1
    End

    It "never skips test"
      When call _brik_local_should_skip_stage "test" "false" "false" "false"
      The status should equal 1
    End

    It "skips container-scan when with_package is false"
      When call _brik_local_should_skip_stage "container-scan" "false" "false" "false"
      The status should be success
    End

    It "does not skip container-scan when with_package is true"
      When call _brik_local_should_skip_stage "container-scan" "false" "true" "false"
      The status should equal 1
    End
  End

  # =========================================================================
  # brik.local.run_pipeline
  # =========================================================================
  Describe "brik.local.run_pipeline"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"

    setup_pipeline_env() {
      export BRIK_CONFIG_FILE
      BRIK_CONFIG_FILE="$(mktemp)"
      printf "version: 1\nproject:\n  name: pipeline-test\n  stack: node\nquality:\n  enabled: 'false'\ntest:\n  framework: npm\n" > "$BRIK_CONFIG_FILE"
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
      export BRIK_WORKSPACE
      BRIK_WORKSPACE="$(mktemp -d)"
      # Create a minimal node workspace so build/test stages succeed
      printf '{"name":"pipeline-test","version":"1.0.0","scripts":{"build":"echo ok","test":"echo ok"}}\n' > "${BRIK_WORKSPACE}/package.json"
      mkdir -p "${BRIK_WORKSPACE}/node_modules"
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/npm" << 'MOCKEOF'
#!/usr/bin/env bash
echo "mock npm: $*"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/npm"
      cat > "${MOCK_BIN}/node" << 'MOCKEOF'
#!/usr/bin/env bash
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/node"
      cat > "${MOCK_BIN}/npx" << 'MOCKEOF'
#!/usr/bin/env bash
echo "mock npx: $*"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/npx"
      export PATH="${MOCK_BIN}:${PATH}"
      export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
      export BRIK_LOG_LEVEL="info"
      brik.local.setup >/dev/null 2>&1 || true
    }
    cleanup_pipeline_env() {
      rm -f "$BRIK_CONFIG_FILE"
      rm -rf "$BRIK_LOG_DIR" "$BRIK_WORKSPACE" "$MOCK_BIN"
    }
    Before 'setup_pipeline_env'
    After 'cleanup_pipeline_env'

    It "returns error for unknown flag"
      When call brik.local.run_pipeline "--bad-flag"
      The status should equal 2
      The error should include "unknown pipeline flag"
    End

    It "runs default pipeline and prints summary"
      When call brik.local.run_pipeline
      The status should be success
      The output should include "Pipeline Summary"
      The output should include "PASS"
      The output should include "SKIP"
      The error should be present
    End

    It "skips release/package/deploy/notify by default"
      check_skipped() {
        local output
        output="$(brik.local.run_pipeline 2>/dev/null)"
        local release_line package_line deploy_line notify_line
        release_line="$(echo "$output" | grep -F "release")"
        package_line="$(echo "$output" | grep -F "package")"
        deploy_line="$(echo "$output" | grep -F "deploy")"
        notify_line="$(echo "$output" | grep -F "notify")"
        if echo "$release_line" | grep -qF "SKIP" && \
           echo "$package_line" | grep -qF "SKIP" && \
           echo "$deploy_line" | grep -qF "SKIP" && \
           echo "$notify_line" | grep -qF "SKIP"; then
          echo "all_skipped"
        else
          echo "not_all_skipped"
        fi
      }
      When call check_skipped
      The output should equal "all_skipped"
    End

    It "includes package with --with-package"
      check_package() {
        local output
        output="$(brik.local.run_pipeline --with-package 2>/dev/null)"
        local package_line
        package_line="$(echo "$output" | grep -F "package")"
        if echo "$package_line" | grep -qF "SKIP"; then
          echo "skipped"
        else
          echo "ran"
        fi
      }
      When call check_package
      The output should equal "ran"
    End

    It "stops at first failure without --continue-on-error"
      check_stop_on_failure() {
        # Override stages.build to fail
        stages.build() { return 1; }
        local output
        output="$(brik.local.run_pipeline 2>/dev/null)"
        local build_line test_line
        build_line="$(echo "$output" | grep -F "build")"
        test_line="$(echo "$output" | grep -F "test")"
        if echo "$build_line" | grep -qF "FAIL" && echo "$test_line" | grep -qF "SKIP"; then
          echo "stopped"
        else
          echo "continued"
        fi
      }
      When call check_stop_on_failure
      The output should equal "stopped"
    End

    It "continues after failure with --continue-on-error"
      check_continue() {
        # Override stages.build to fail
        stages.build() { return 1; }
        local output
        output="$(brik.local.run_pipeline --continue-on-error 2>/dev/null)"
        local test_line
        test_line="$(echo "$output" | grep -F "test")"
        # test should have run (PASS or FAIL), not SKIP
        if echo "$test_line" | grep -qF "SKIP"; then
          echo "skipped"
        else
          echo "ran"
        fi
      }
      When call check_continue
      The output should equal "ran"
    End
  End

  # =========================================================================
  # brik.local.print_summary
  # =========================================================================
  Describe "brik.local.print_summary"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"

    It "prints pass/fail/skip counts"
      check_summary() {
        local -a my_stages=(init build lint)
        local -A my_status=([init]="PASS" [build]="PASS" [lint]="SKIP")
        local -A my_duration=([init]="1" [build]="2" [lint]="0")
        local output
        output="$(brik.local.print_summary my_stages my_status my_duration 3)"
        if echo "$output" | grep -qF "2/2 passed" && echo "$output" | grep -qF "1 skipped"; then
          echo "correct"
        else
          echo "wrong: $output"
        fi
      }
      When call check_summary
      The output should equal "correct"
    End

    It "shows FAIL result when any stage fails"
      check_fail() {
        local -a my_stages=(init build)
        local -A my_status=([init]="PASS" [build]="FAIL")
        local -A my_duration=([init]="1" [build]="2")
        local output
        output="$(brik.local.print_summary my_stages my_status my_duration 3)"
        if echo "$output" | grep -qF "FAIL"; then
          echo "shows_fail"
        else
          echo "no_fail"
        fi
      }
      When call check_fail
      The output should equal "shows_fail"
    End

    It "shows correct counts with all 3 states"
      check_all_states() {
        local -a my_stages=(init build lint scan)
        local -A my_status=([init]="PASS" [build]="FAIL" [lint]="PASS" [scan]="SKIP")
        local -A my_duration=([init]="1" [build]="2" [lint]="1" [scan]="0")
        local output
        output="$(brik.local.print_summary my_stages my_status my_duration 4)"
        if echo "$output" | grep -qF "2/3 passed" && echo "$output" | grep -qF "1 skipped"; then
          echo "correct"
        else
          echo "wrong: $output"
        fi
      }
      When call check_all_states
      The output should equal "correct"
    End

    It "returns error with insufficient arguments"
      When call brik.local.print_summary "a" "b"
      The status should equal 2
      The error should include "requires 4 arguments"
    End
  End

  # =========================================================================
  # Additional coverage: edge cases
  # =========================================================================

  Describe "brik.local.run_stage without prior setup"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"

    Describe "when BRIK_HOME is unset"
      setup_no_home() { unset BRIK_HOME 2>/dev/null || true; }
      Before 'setup_no_home'

      It "returns 4 with setup error"
        When call brik.local.run_stage "init"
        The status should equal 4
        The error should include "brik.local.setup must be called"
      End
    End
  End

  Describe "brik.local.run_pipeline with --with-release"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"

    setup_pipeline_release() {
      export BRIK_CONFIG_FILE
      BRIK_CONFIG_FILE="$(mktemp)"
      printf "version: 1\nproject:\n  name: pipeline-test\n  stack: node\nquality:\n  enabled: 'false'\ntest:\n  framework: npm\n" > "$BRIK_CONFIG_FILE"
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
      export BRIK_WORKSPACE
      BRIK_WORKSPACE="$(mktemp -d)"
      printf '{"name":"pipeline-test","version":"1.0.0","scripts":{"build":"echo ok","test":"echo ok"}}\n' > "${BRIK_WORKSPACE}/package.json"
      mkdir -p "${BRIK_WORKSPACE}/node_modules"
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/npm" << 'MOCKEOF'
#!/usr/bin/env bash
echo "mock npm: $*"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/npm"
      cat > "${MOCK_BIN}/node" << 'MOCKEOF'
#!/usr/bin/env bash
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/node"
      cat > "${MOCK_BIN}/npx" << 'MOCKEOF'
#!/usr/bin/env bash
echo "mock npx: $*"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/npx"
      export PATH="${MOCK_BIN}:${PATH}"
      export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
      export BRIK_LOG_LEVEL="info"
      brik.local.setup >/dev/null 2>&1 || true
    }
    cleanup_pipeline_release() {
      rm -f "$BRIK_CONFIG_FILE"
      rm -rf "$BRIK_LOG_DIR" "$BRIK_WORKSPACE" "$MOCK_BIN"
    }
    Before 'setup_pipeline_release'
    After 'cleanup_pipeline_release'

    It "includes release stage with --with-release"
      check_release() {
        local output
        output="$(brik.local.run_pipeline --with-release 2>/dev/null)"
        local release_line
        release_line="$(echo "$output" | grep -F "release")"
        if echo "$release_line" | grep -qF "SKIP"; then
          echo "skipped"
        else
          echo "ran"
        fi
      }
      When call check_release
      The output should equal "ran"
    End

    It "includes deploy and notify with --with-deploy"
      check_deploy() {
        local output
        output="$(brik.local.run_pipeline --with-deploy 2>/dev/null)"
        local deploy_line notify_line
        deploy_line="$(echo "$output" | grep -F "deploy")"
        notify_line="$(echo "$output" | grep -F "notify")"
        if echo "$deploy_line" | grep -qF "SKIP" || echo "$notify_line" | grep -qF "SKIP"; then
          echo "some_skipped"
        else
          echo "both_ran"
        fi
      }
      When call check_deploy
      The output should equal "both_ran"
    End

    It "warns about deploy danger with --with-deploy"
      When call brik.local.run_pipeline --with-deploy
      The output should be present
      The error should include "be careful running deploy locally"
    End

    It "returns exit code 1 when pipeline has failure"
      check_fail_exit() {
        stages.build() { return 1; }
        brik.local.run_pipeline >/dev/null 2>&1
        echo "$?"
      }
      When call check_fail_exit
      The output should equal "1"
    End
  End

  Describe "_brik_local_setup_git_context BRIK_COMMIT_REF"
    Include "$BRIK_HOME/shared-libs/local/scripts/local-wrapper.sh"

    Describe "on a branch"
      setup_ref_branch() {
        GIT_REPO="$(mktemp -d)"
        git -C "$GIT_REPO" init -q
        git -C "$GIT_REPO" config user.email "test@test.com"
        git -C "$GIT_REPO" config user.name "Test"
        touch "$GIT_REPO/file.txt"
        git -C "$GIT_REPO" add file.txt
        git -C "$GIT_REPO" commit -q -m "initial"
        ORIG_DIR="$(pwd)"
        cd "$GIT_REPO" || return 1
      }
      cleanup_ref_branch() {
        cd "$ORIG_DIR" || true
        rm -rf "$GIT_REPO"
      }
      Before 'setup_ref_branch'
      After 'cleanup_ref_branch'

      It "sets BRIK_COMMIT_REF to the branch name"
        check_ref() {
          _brik_local_setup_git_context 2>/dev/null
          local branch
          branch="$(git branch --show-current)"
          if [[ "$BRIK_COMMIT_REF" == "$branch" ]]; then
            echo "matches_branch"
          else
            echo "mismatch: ref=$BRIK_COMMIT_REF branch=$branch"
          fi
        }
        When call check_ref
        The output should equal "matches_branch"
      End
    End

    Describe "with a tag on detached HEAD"
      setup_ref_tag() {
        GIT_REPO="$(mktemp -d)"
        git -C "$GIT_REPO" init -q
        git -C "$GIT_REPO" config user.email "test@test.com"
        git -C "$GIT_REPO" config user.name "Test"
        touch "$GIT_REPO/file.txt"
        git -C "$GIT_REPO" add file.txt
        git -C "$GIT_REPO" commit -q -m "initial"
        git -C "$GIT_REPO" tag v2.0.0
        local sha
        sha="$(git -C "$GIT_REPO" rev-parse HEAD)"
        git -C "$GIT_REPO" checkout -q "$sha"
        ORIG_DIR="$(pwd)"
        cd "$GIT_REPO" || return 1
      }
      cleanup_ref_tag() {
        cd "$ORIG_DIR" || true
        rm -rf "$GIT_REPO"
      }
      Before 'setup_ref_tag'
      After 'cleanup_ref_tag'

      It "sets BRIK_COMMIT_REF to the tag when detached"
        check_ref() {
          _brik_local_setup_git_context 2>/dev/null
          printf '%s' "$BRIK_COMMIT_REF"
        }
        When call check_ref
        The output should equal "v2.0.0"
      End
    End
  End
End

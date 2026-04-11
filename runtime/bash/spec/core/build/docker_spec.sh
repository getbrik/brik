Describe "build/docker.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/build/docker.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "build.docker.run"
    It "returns 6 for nonexistent workspace"
      When call build.docker.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    It "returns 2 for unknown option"
      When call build.docker.run "$WORKSPACES/docker-simple" --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 6 when Dockerfile is missing"
      When call build.docker.run "$WORKSPACES/unknown"
      The status should equal 6
      The stderr should include "required file not found"
    End

    Describe "require_tool docker failure"
      setup_no_docker() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf 'FROM alpine:3.19\n' > "${TEST_WS}/Dockerfile"
        mock.isolate
      }
      cleanup_no_docker() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_docker'
      After 'cleanup_no_docker'

      It "returns 3 when docker is not on PATH"
        When call build.docker.run "$TEST_WS"
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "with mock docker"
      setup_docker() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_docker.log"
        printf 'FROM alpine:3.19\nCMD ["echo","hello"]\n' > "${TEST_WS}/Dockerfile"
        mock.create_logging "docker" "$MOCK_LOG"
        mock.activate
      }
      cleanup_docker() {
        mock.cleanup
        unset BRIK_PROJECT_NAME BRIK_VERSION 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_docker'
      After 'cleanup_docker'

      It "succeeds and reports completion"
        When call build.docker.run "$TEST_WS"
        The status should be success
        The stderr should include "build completed successfully"
      End

      It "runs docker build with default tag project:latest"
        invoke_docker_default() {
          build.docker.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^docker build" "$MOCK_LOG" && grep -q "\-t project:latest" "$MOCK_LOG"
        }
        When call invoke_docker_default
        The status should be success
      End

      It "uses BRIK_PROJECT_NAME and BRIK_VERSION for default tag"
        invoke_env_tag() {
          export BRIK_PROJECT_NAME="myapp"
          export BRIK_VERSION="2.0"
          build.docker.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "\-t myapp:2.0" "$MOCK_LOG"
        }
        When call invoke_env_tag
        The status should be success
      End

      It "uses custom tag when --tag specified"
        invoke_custom_tag() {
          build.docker.run "$TEST_WS" --tag "myapp:1.0" 2>/dev/null || return 1
          grep -q "\-t myapp:1.0" "$MOCK_LOG"
        }
        When call invoke_custom_tag
        The status should be success
      End

      It "uses custom Dockerfile when --file specified"
        invoke_custom_file() {
          local custom="${TEST_WS}/Dockerfile.prod"
          printf 'FROM alpine:3.19\n' > "$custom"
          build.docker.run "$TEST_WS" --file "$custom" 2>/dev/null || return 1
          grep -q "\-f ${custom}" "$MOCK_LOG"
        }
        When call invoke_custom_file
        The status should be success
      End

      It "uses custom context when --context specified"
        invoke_custom_context() {
          local ctx="${TEST_WS}/sub"
          mkdir -p "$ctx"
          build.docker.run "$TEST_WS" --context "$ctx" 2>/dev/null || return 1
          grep -q "${ctx}$" "$MOCK_LOG"
        }
        When call invoke_custom_context
        The status should be success
      End

      It "passes build args"
        invoke_build_args() {
          build.docker.run "$TEST_WS" --build-arg "VERSION=1.0" 2>/dev/null || return 1
          grep -q "\-\-build-arg VERSION=1.0" "$MOCK_LOG"
        }
        When call invoke_build_args
        The status should be success
      End

      It "accumulates multiple build args"
        invoke_multi_args() {
          build.docker.run "$TEST_WS" --build-arg "A=1" --build-arg "B=2" 2>/dev/null || return 1
          grep -q "\-\-build-arg A=1" "$MOCK_LOG" && grep -q "\-\-build-arg B=2" "$MOCK_LOG"
        }
        When call invoke_multi_args
        The status should be success
      End
    End

    Describe "dry-run mode"
      setup_dryrun() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf 'FROM alpine:3.19\n' > "${TEST_WS}/Dockerfile"
        mock.create_script "docker" 'printf "SHOULD NOT RUN\n"
exit 1'
        mock.activate
      }
      cleanup_dryrun() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_dryrun'
      After 'cleanup_dryrun'

      It "does not execute docker in dry-run mode"
        When call build.docker.run "$TEST_WS" --dry-run
        The status should be success
        The stdout should not include "SHOULD NOT RUN"
        The stderr should include "dry-run"
      End
    End

    Describe "BRIK_DRY_RUN env var"
      setup_env_dryrun() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf 'FROM alpine:3.19\n' > "${TEST_WS}/Dockerfile"
        mock.create_script "docker" 'printf "SHOULD NOT RUN\n"
exit 1'
        mock.activate
        export BRIK_DRY_RUN="true"
      }
      cleanup_env_dryrun() {
        mock.cleanup
        unset BRIK_DRY_RUN
        rm -rf "$TEST_WS"
      }
      Before 'setup_env_dryrun'
      After 'cleanup_env_dryrun'

      It "respects BRIK_DRY_RUN env var"
        When call build.docker.run "$TEST_WS"
        The status should be success
        The stdout should not include "SHOULD NOT RUN"
        The stderr should include "dry-run"
      End
    End

    Describe "with failing docker"
      setup_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf 'FROM alpine:3.19\n' > "${TEST_WS}/Dockerfile"
        mock.create_exit "docker" 1
        mock.activate
      }
      cleanup_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 5 when build fails"
        When call build.docker.run "$TEST_WS"
        The status should equal 5
        The stderr should include "build failed"
      End
    End
  End
End

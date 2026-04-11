Describe "deploy/compose.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/deploy/compose.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "deploy.compose.run"
    It "returns 2 for unknown option"
      When call deploy.compose.run --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "require_tool docker failure"
      setup_no_docker() {
        mock.setup
        mock.isolate
      }
      cleanup_no_docker() {
        mock.cleanup
      }
      Before 'setup_no_docker'
      After 'cleanup_no_docker'

      It "returns 3 when docker is not on PATH"
        When call deploy.compose.run --namespace myapp
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "local deploy with mock docker"
      setup_docker() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_docker.log"
        printf 'version: "3"\nservices:\n  app:\n    image: myapp\n' > "${TEST_WS}/docker-compose.yml"
        mock.create_logging "docker" "$MOCK_LOG"
        mock.activate
      }
      cleanup_docker() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_docker'
      After 'cleanup_docker'

      It "uses default docker-compose.yml when no --compose-file"
        invoke_default_file() {
          cd "$TEST_WS" || return 1
          deploy.compose.run --namespace myapp 2>/dev/null || return 1
          grep -q "docker-compose.yml" "$MOCK_LOG"
        }
        When call invoke_default_file
        The status should be success
      End

      It "uses custom --compose-file when provided"
        invoke_custom_file() {
          deploy.compose.run --namespace myapp \
            --compose-file "${TEST_WS}/docker-compose.yml" 2>/dev/null || return 1
          grep -q "docker-compose.yml" "$MOCK_LOG"
        }
        When call invoke_custom_file
        The status should be success
      End

      It "runs docker compose up -d for local deploy"
        invoke_local() {
          deploy.compose.run --namespace myapp \
            --compose-file "${TEST_WS}/docker-compose.yml" 2>/dev/null || return 1
          grep -q "up -d" "$MOCK_LOG"
        }
        When call invoke_local
        The status should be success
      End

      It "uses --namespace as project name"
        invoke_project() {
          deploy.compose.run --namespace my-project \
            --compose-file "${TEST_WS}/docker-compose.yml" 2>/dev/null || return 1
          grep -q "my-project" "$MOCK_LOG"
        }
        When call invoke_project
        The status should be success
      End

      It "passes -p flag with project name"
        invoke_flag_p() {
          deploy.compose.run --namespace my-project \
            --compose-file "${TEST_WS}/docker-compose.yml" 2>/dev/null || return 1
          grep -q "\-p my-project" "$MOCK_LOG"
        }
        When call invoke_flag_p
        The status should be success
      End

      It "succeeds and reports deployment completed"
        When call deploy.compose.run --namespace myapp \
          --compose-file "${TEST_WS}/docker-compose.yml"
        The status should be success
        The stderr should include "compose deployment completed"
      End

      It "dry-run mode: logs without executing"
        invoke_dryrun() {
          deploy.compose.run --namespace myapp \
            --compose-file "${TEST_WS}/docker-compose.yml" \
            --dry-run 2>&1 | grep -q "\[dry-run\]"
        }
        When call invoke_dryrun
        The status should be success
      End

      It "dry-run mode: does not execute docker command"
        invoke_dryrun_noexec() {
          local log="${TEST_WS}/mock_docker.log"
          deploy.compose.run --namespace myapp \
            --compose-file "${TEST_WS}/docker-compose.yml" \
            --dry-run 2>/dev/null
          # docker should not have been called with up in dry-run
          [[ ! -f "$log" ]] || ! grep -q "up" "$log"
        }
        When call invoke_dryrun_noexec
        The status should be success
      End
    End

    Describe "remote deploy with --host"
      setup_remote() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_cmds.log"
        printf 'version: "3"\n' > "${TEST_WS}/docker-compose.yml"
        mock.create_logging "scp" "$MOCK_LOG"
        mock.create_logging "ssh" "$MOCK_LOG"
        mock.create_logging "docker" "$MOCK_LOG"
        mock.activate
      }
      cleanup_remote() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_remote'
      After 'cleanup_remote'

      It "uses scp to copy compose file to remote host"
        invoke_scp() {
          deploy.compose.run --namespace myapp \
            --compose-file "${TEST_WS}/docker-compose.yml" \
            --host deploy.example.com \
            --remote-path /srv/myapp 2>/dev/null || return 1
          grep -q "^scp" "$MOCK_LOG"
        }
        When call invoke_scp
        The status should be success
      End

      It "uses --remote-path for scp destination"
        invoke_remote_path() {
          deploy.compose.run --namespace myapp \
            --compose-file "${TEST_WS}/docker-compose.yml" \
            --host deploy.example.com \
            --remote-path /srv/myapp 2>/dev/null || return 1
          grep -q "/srv/myapp" "$MOCK_LOG"
        }
        When call invoke_remote_path
        The status should be success
      End

      It "uses ssh to run docker compose on remote host"
        invoke_ssh() {
          deploy.compose.run --namespace myapp \
            --compose-file "${TEST_WS}/docker-compose.yml" \
            --host deploy.example.com \
            --remote-path /srv/myapp 2>/dev/null || return 1
          grep -q "^ssh" "$MOCK_LOG"
        }
        When call invoke_ssh
        The status should be success
      End

      It "passes host to ssh command"
        invoke_ssh_host() {
          deploy.compose.run --namespace myapp \
            --compose-file "${TEST_WS}/docker-compose.yml" \
            --host deploy.example.com \
            --remote-path /srv/myapp 2>/dev/null || return 1
          grep -q "deploy.example.com" "$MOCK_LOG"
        }
        When call invoke_ssh_host
        The status should be success
      End

      It "dry-run with host: logs without executing scp and ssh"
        invoke_remote_dryrun() {
          deploy.compose.run --namespace myapp \
            --compose-file "${TEST_WS}/docker-compose.yml" \
            --host deploy.example.com \
            --remote-path /srv/myapp \
            --dry-run 2>&1 | grep -q "\[dry-run\]"
        }
        When call invoke_remote_dryrun
        The status should be success
      End

      It "dry-run with host: does not execute scp"
        invoke_remote_dryrun_noscp() {
          local log="${TEST_WS}/mock_cmds.log"
          deploy.compose.run --namespace myapp \
            --compose-file "${TEST_WS}/docker-compose.yml" \
            --host deploy.example.com \
            --remote-path /srv/myapp \
            --dry-run 2>/dev/null
          [[ ! -f "$log" ]] || ! grep -q "^scp" "$log"
        }
        When call invoke_remote_dryrun_noscp
        The status should be success
      End
    End

    Describe "BRIK_DRY_RUN env var"
      setup_env_dryrun() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_docker.log"
        printf 'version: "3"\n' > "${TEST_WS}/docker-compose.yml"
        mock.create_logging "docker" "$MOCK_LOG"
        mock.activate
        export BRIK_DRY_RUN="true"
      }
      cleanup_env_dryrun() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_env_dryrun'
      After 'cleanup_env_dryrun'

      It "respects BRIK_DRY_RUN env var"
        invoke_env_dryrun() {
          local log="${TEST_WS}/mock_docker.log"
          deploy.compose.run --namespace myapp \
            --compose-file "${TEST_WS}/docker-compose.yml" 2>/dev/null
          [[ ! -f "$log" ]] || ! grep -q "up" "$log"
        }
        When call invoke_env_dryrun
        The status should be success
      End
    End

    Describe "double-sourcing guard"
      It "is callable after double include"
        double_include() {
          # shellcheck source=/dev/null
          . "$BRIK_CORE_LIB/deploy/compose.sh"
          declare -f deploy.compose.run >/dev/null && echo "ok" || echo "missing"
        }
        When call double_include
        The output should equal "ok"
      End
    End
  End
End

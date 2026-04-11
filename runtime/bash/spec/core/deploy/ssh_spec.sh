Describe "deploy/ssh.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/deploy/ssh.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "deploy.ssh.run"
    It "returns 2 for unknown option"
      When call deploy.ssh.run --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 2 when --host is missing"
      When call deploy.ssh.run --remote-path /srv/myapp
      The status should equal 2
      The stderr should include "host is required"
    End

    It "returns 2 when --remote-path is missing"
      When call deploy.ssh.run --host deploy.example.com
      The status should equal 2
      The stderr should include "remote-path is required"
    End

    Describe "require_tool rsync failure"
      setup_no_rsync() {
        mock.setup
        mock.isolate
      }
      cleanup_no_rsync() {
        mock.cleanup
      }
      Before 'setup_no_rsync'
      After 'cleanup_no_rsync'

      It "returns 3 when rsync is not on PATH"
        When call deploy.ssh.run --host deploy.example.com --remote-path /srv/myapp
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "require_tool ssh failure"
      setup_no_ssh() {
        mock.setup
        mock.create_exit "rsync" 0
        mock.isolate
      }
      cleanup_no_ssh() {
        mock.cleanup
      }
      Before 'setup_no_ssh'
      After 'cleanup_no_ssh'

      It "returns 3 when ssh is not on PATH"
        When call deploy.ssh.run --host deploy.example.com --remote-path /srv/myapp
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "with mock rsync and ssh"
      setup_tools() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_cmds.log"
        mock.create_logging "rsync" "$MOCK_LOG"
        mock.create_logging "ssh" "$MOCK_LOG"
        mock.activate
      }
      cleanup_tools() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_tools'
      After 'cleanup_tools'

      It "runs rsync with -avz --delete flags"
        invoke_rsync_flags() {
          deploy.ssh.run --host deploy.example.com --remote-path /srv/myapp 2>/dev/null || return 1
          grep -q "\-avz" "$MOCK_LOG" && grep -q "\-\-delete" "$MOCK_LOG"
        }
        When call invoke_rsync_flags
        The status should be success
      End

      It "passes host:remote-path as rsync destination"
        invoke_rsync_dest() {
          deploy.ssh.run --host deploy.example.com --remote-path /srv/myapp 2>/dev/null || return 1
          grep -q "deploy.example.com:/srv/myapp" "$MOCK_LOG"
        }
        When call invoke_rsync_dest
        The status should be success
      End

      It "uses --manifest as rsync source when provided"
        invoke_manifest_src() {
          deploy.ssh.run --host deploy.example.com --remote-path /srv/myapp \
            --manifest "${TEST_WS}" 2>/dev/null || return 1
          grep -q "${TEST_WS}" "$MOCK_LOG"
        }
        When call invoke_manifest_src
        The status should be success
      End

      It "defaults to '.' as rsync source when no --manifest"
        invoke_default_src() {
          deploy.ssh.run --host deploy.example.com --remote-path /srv/myapp 2>/dev/null || return 1
          grep -qE "rsync.*\.\s" "$MOCK_LOG" || grep -qE "rsync.* \.$" "$MOCK_LOG" || grep -q "rsync -avz --delete ." "$MOCK_LOG"
        }
        When call invoke_default_src
        The status should be success
      End

      It "executes --restart-cmd via ssh after rsync"
        invoke_restart() {
          deploy.ssh.run --host deploy.example.com --remote-path /srv/myapp \
            --restart-cmd "systemctl restart myapp" 2>/dev/null || return 1
          grep -q "^ssh" "$MOCK_LOG"
        }
        When call invoke_restart
        The status should be success
      End

      It "passes restart-cmd to ssh"
        invoke_restart_cmd() {
          deploy.ssh.run --host deploy.example.com --remote-path /srv/myapp \
            --restart-cmd "systemctl restart myapp" 2>/dev/null || return 1
          grep -q "systemctl restart myapp" "$MOCK_LOG"
        }
        When call invoke_restart_cmd
        The status should be success
      End

      It "skips ssh when no --restart-cmd"
        invoke_no_restart() {
          deploy.ssh.run --host deploy.example.com --remote-path /srv/myapp 2>/dev/null || return 1
          # ssh should not be in log if no restart-cmd
          ! grep -q "^ssh" "$MOCK_LOG"
        }
        When call invoke_no_restart
        The status should be success
      End

      It "succeeds and reports deployment completed"
        When call deploy.ssh.run --host deploy.example.com --remote-path /srv/myapp
        The status should be success
        The stderr should include "ssh deployment completed"
      End

      It "dry-run mode: uses rsync --dry-run flag"
        invoke_dryrun_rsync() {
          deploy.ssh.run --host deploy.example.com --remote-path /srv/myapp \
            --dry-run 2>/dev/null || return 1
          grep -q "\-\-dry-run" "$MOCK_LOG"
        }
        When call invoke_dryrun_rsync
        The status should be success
      End

      It "dry-run mode: logs ssh command without executing it"
        invoke_dryrun_ssh_log() {
          deploy.ssh.run --host deploy.example.com --remote-path /srv/myapp \
            --restart-cmd "systemctl restart myapp" \
            --dry-run 2>&1 | grep -q "\[dry-run\]"
        }
        When call invoke_dryrun_ssh_log
        The status should be success
      End

      It "dry-run mode: does not execute ssh restart"
        invoke_dryrun_nossh() {
          local log="${TEST_WS}/mock_cmds.log"
          deploy.ssh.run --host deploy.example.com --remote-path /srv/myapp \
            --restart-cmd "systemctl restart myapp" \
            --dry-run 2>/dev/null
          [[ ! -f "$log" ]] || ! grep -q "^ssh" "$log"
        }
        When call invoke_dryrun_nossh
        The status should be success
      End
    End

    Describe "with failing rsync"
      setup_fail_rsync() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "rsync" 1
        mock.create_exit "ssh" 0
        mock.activate
      }
      cleanup_fail_rsync() {
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_fail_rsync'
      After 'cleanup_fail_rsync'

      It "returns 5 when rsync fails"
        When call deploy.ssh.run --host deploy.example.com --remote-path /srv/myapp
        The status should equal 5
        The stderr should include "rsync failed"
      End
    End

    Describe "BRIK_DRY_RUN env var"
      setup_env_dryrun() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_cmds.log"
        mock.create_logging "rsync" "$MOCK_LOG"
        mock.create_logging "ssh" "$MOCK_LOG"
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

      It "respects BRIK_DRY_RUN env var and uses rsync --dry-run"
        invoke_env_dryrun() {
          deploy.ssh.run --host deploy.example.com --remote-path /srv/myapp 2>/dev/null || return 1
          grep -q "\-\-dry-run" "$MOCK_LOG"
        }
        When call invoke_env_dryrun
        The status should be success
      End
    End

    Describe "double-sourcing guard"
      It "is callable after double include"
        double_include() {
          # shellcheck source=/dev/null
          . "$BRIK_CORE_LIB/deploy/ssh.sh"
          declare -f deploy.ssh.run >/dev/null && echo "ok" || echo "missing"
        }
        When call double_include
        The output should equal "ok"
      End
    End
  End
End

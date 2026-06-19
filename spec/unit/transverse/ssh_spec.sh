Describe "ssh.sh (transverse ssh-agent helper)"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_TRANSVERSE_LIB/ssh.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  Describe "transverse.ssh.setup_agent"
    Describe "skip when no SSH_PRIVATE_KEY"
      setup_no_key() {
        unset SSH_PRIVATE_KEY 2>/dev/null
      }
      Before 'setup_no_key'

      It "returns 0 when SSH_PRIVATE_KEY is unset"
        When call transverse.ssh.setup_agent
        The status should be success
      End
    End

    Describe "skip when agent already has identities"
      setup_agent_ok() {
        mock.setup
        export SSH_PRIVATE_KEY="inline-key-content"
        mock.create_exit "ssh-add" 0
        mock.activate
      }
      cleanup_agent_ok() {
        mock.cleanup
        unset SSH_PRIVATE_KEY 2>/dev/null
      }
      Before 'setup_agent_ok'
      After 'cleanup_agent_ok'

      It "returns 0 when ssh-add -l succeeds"
        When call transverse.ssh.setup_agent
        The status should be success
      End
    End

    Describe "inline key loading"
      setup_inline_key() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_cmds.log"
        export SSH_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
FAKEKEYDATA
-----END RSA PRIVATE KEY-----"
        # ssh-add -l must fail (no identities) so setup continues
        cat > "${MOCK_BIN}/ssh-add" <<'SCRIPT'
#!/bin/sh
if [ "$1" = "-l" ]; then exit 1; fi
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/ssh-add"
        mock.create_exit "ssh-agent" 0
        mock.activate
        export SSH_AUTH_SOCK="/tmp/fake-ssh-agent.sock"
      }
      cleanup_inline_key() {
        mock.cleanup
        unset SSH_PRIVATE_KEY SSH_AUTH_SOCK 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_inline_key'
      After 'cleanup_inline_key'

      It "loads inline key via ssh-add stdin"
        When call transverse.ssh.setup_agent
        The status should be success
        The stderr should include "SSH key loaded"
      End
    End

    Describe "file key loading"
      setup_file_key() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '%s\n' "-----BEGIN RSA PRIVATE KEY-----" "FAKEKEYDATA" "-----END RSA PRIVATE KEY-----" > "${TEST_WS}/id_rsa"
        export SSH_PRIVATE_KEY="${TEST_WS}/id_rsa"
        cat > "${MOCK_BIN}/ssh-add" <<'SCRIPT'
#!/bin/sh
if [ "$1" = "-l" ]; then exit 1; fi
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/ssh-add"
        mock.create_exit "ssh-agent" 0
        mock.activate
        export SSH_AUTH_SOCK="/tmp/fake-ssh-agent.sock"
      }
      cleanup_file_key() {
        mock.cleanup
        unset SSH_PRIVATE_KEY SSH_AUTH_SOCK 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_file_key'
      After 'cleanup_file_key'

      It "loads key from file path"
        When call transverse.ssh.setup_agent
        The status should be success
        The stderr should include "SSH key loaded"
      End
    End

    Describe "starts ssh-agent when SSH_AUTH_SOCK unset"
      setup_no_sock() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        export SSH_PRIVATE_KEY="inline-key"
        cat > "${MOCK_BIN}/ssh-add" <<'SCRIPT'
#!/bin/sh
if [ "$1" = "-l" ]; then exit 1; fi
exit 0
SCRIPT
        chmod +x "${MOCK_BIN}/ssh-add"
        # ssh-agent must output valid eval-able content
        printf '#!/bin/sh\necho "SSH_AUTH_SOCK=/tmp/test; export SSH_AUTH_SOCK"\n' > "${MOCK_BIN}/ssh-agent"
        chmod +x "${MOCK_BIN}/ssh-agent"
        mock.activate
        unset SSH_AUTH_SOCK 2>/dev/null
      }
      cleanup_no_sock() {
        mock.cleanup
        unset SSH_PRIVATE_KEY SSH_AUTH_SOCK 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_sock'
      After 'cleanup_no_sock'

      It "starts ssh-agent and loads key"
        When call transverse.ssh.setup_agent
        The status should be success
        The stderr should include "ssh-agent started"
      End
    End

    Describe "inline key add failure"
      setup_inline_fail() {
        mock.setup
        export SSH_PRIVATE_KEY="bad-inline-key"
        cat > "${MOCK_BIN}/ssh-add" <<'SCRIPT'
#!/bin/sh
if [ "$1" = "-l" ]; then exit 1; fi
exit 1
SCRIPT
        chmod +x "${MOCK_BIN}/ssh-add"
        mock.activate
        export SSH_AUTH_SOCK="/tmp/fake.sock"
      }
      cleanup_inline_fail() {
        mock.cleanup
        unset SSH_PRIVATE_KEY SSH_AUTH_SOCK 2>/dev/null
      }
      Before 'setup_inline_fail'
      After 'cleanup_inline_fail'

      It "warns and returns 0 when inline key add fails"
        When call transverse.ssh.setup_agent
        The status should be success
        The stderr should include "failed to add inline SSH key"
      End
    End

    Describe "file key add failure"
      setup_file_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf 'bad-key-data\n' > "${TEST_WS}/id_rsa"
        export SSH_PRIVATE_KEY="${TEST_WS}/id_rsa"
        cat > "${MOCK_BIN}/ssh-add" <<'SCRIPT'
#!/bin/sh
if [ "$1" = "-l" ]; then exit 1; fi
exit 1
SCRIPT
        chmod +x "${MOCK_BIN}/ssh-add"
        mock.activate
        export SSH_AUTH_SOCK="/tmp/fake.sock"
      }
      cleanup_file_fail() {
        mock.cleanup
        unset SSH_PRIVATE_KEY SSH_AUTH_SOCK 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_file_fail'
      After 'cleanup_file_fail'

      It "warns and returns 0 when file key add fails"
        When call transverse.ssh.setup_agent
        The status should be success
        The stderr should include "failed to add SSH key from file"
      End
    End
  End

  # T3 (#39 P1): the connection identity (user, port) declared on the SshTarget
  # must reach the transport. Applied regardless of the host-key stance.
  Describe "transverse.ssh.host_opts (referential user/port)"
    Include "$BRIK_PIPELINE_LIB/loader.sh"
    Include "$BRIK_TRANSVERSE_LIB/env.sh"
    Include "$BRIK_TRANSVERSE_LIB/config.sh"
    Include "$BRIK_TRANSVERSE_LIB/infra.sh"

    make_ssh_instance() {
      INFRA_DIR="$(mktemp -d)"
      mkdir -p "$INFRA_DIR/endpoints"
      cat > "$INFRA_DIR/referential.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Referential
profile: p-lab
YAML
      cat > "$INFRA_DIR/endpoints/app.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: SshTarget
name: app
hosts: [app.lab]
user: deploy
port: 2222
strict_host_key: false
YAML
      export BRIK_INFRA_DIR="$INFRA_DIR"
    }
    cleanup_ssh_instance() { rm -rf "$INFRA_DIR"; unset BRIK_INFRA_DIR INFRA_DIR; }
    Before 'make_ssh_instance'
    After 'cleanup_ssh_instance'

    emit_opts() {
      local -a opts=()
      transverse.ssh.host_opts opts app.lab || return "$?"
      printf '%s\n' "${opts[@]}"
    }

    It "applies the declared user as -o User="
      When call emit_opts
      The status should be success
      The output should include "User=deploy"
      The stderr should include "strict_host_key: false"
    End

    It "applies the declared port as -o Port="
      When call emit_opts
      The status should be success
      The output should include "Port=2222"
      The stderr should include "strict_host_key: false"
    End
  End
End

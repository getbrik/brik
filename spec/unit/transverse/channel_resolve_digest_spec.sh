Describe "transverse/channel.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_TRANSVERSE_LIB/env.sh"
  Include "$BRIK_TRANSVERSE_LIB/config.sh"
  Include "$BRIK_TRANSVERSE_LIB/channel.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  # A syntactically valid manifest digest (sha256 + 64 lowercase hex).
  VALID_DIGEST="sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

  write_config() {
    CHAN_CFG="$(mktemp)"
    cat > "$CHAN_CFG" <<'YAML'
artifacts:
  channels:
    candidate:
      registry: registry.internal/app
    release:
      registry: registry.release/app
YAML
    export BRIK_CONFIG_FILE="$CHAN_CFG"
  }
  cleanup_config() {
    rm -f "$CHAN_CFG"
    unset BRIK_CONFIG_FILE
  }
  Before 'write_config'
  After 'cleanup_config'

  # =========================================================================
  # channel.registry
  # =========================================================================
  Describe "channel.registry"
    It "returns the registry endpoint configured for the channel"
      When call channel.registry release
      The output should equal "registry.release/app"
    End

    It "returns config_error (7) when the channel is not declared"
      When call channel.registry ghost
      The status should equal 7
      The stderr should include "ghost"
    End

    It "returns invalid_input (2) when no channel name is given"
      When call channel.registry ""
      The status should equal 2
      The stderr should include "required"
    End
  End

  # =========================================================================
  # channel.resolve_digest
  # =========================================================================
  Describe "channel.resolve_digest"
    BeforeEach 'mock.setup'
    AfterEach 'mock.cleanup'

    It "resolves a known version to a digest-pinned ref"
      resolve_ok() {
        mock.create_output "crane" "$VALID_DIGEST" 0
        mock.activate
        channel.resolve_digest v1.2.3 release
      }
      When call resolve_ok
      The output should equal "registry.release/app@${VALID_DIGEST}"
    End

    It "fails external_fail (5) when the version is absent from the channel"
      resolve_absent() {
        mock.create_exit "crane" 1
        mock.activate
        channel.resolve_digest v9.9.9 release
      }
      When call resolve_absent
      The status should equal 5
      The stderr should include "digest"
    End

    It "fails external_fail (5) when the resolver returns a malformed digest"
      resolve_malformed() {
        mock.create_output "crane" "not-a-digest" 0
        mock.activate
        channel.resolve_digest v1.2.3 release
      }
      When call resolve_malformed
      The status should equal 5
      The stderr should include "malformed"
    End

    It "fails config_error (7) when the channel has no registry"
      When call channel.resolve_digest v1.2.3 ghost
      The status should equal 7
      The stderr should include "ghost"
    End

    It "fails missing_dep (3) when no digest resolver is on PATH"
      resolve_no_tool() {
        mock.preserve_cmds
        # Keep yq available so the channel registry lookup succeeds and the
        # resolver-missing path (crane absent) is the one under test.
        ln -s "$(command -v yq)" "${MOCK_BIN}/yq" 2>/dev/null || true
        mock.isolate
        channel.resolve_digest v1.2.3 release
      }
      When call resolve_no_tool
      The status should equal 3
      The stderr should include "crane"
    End
  End
End

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

    # The resolver talks the OCI distribution API over curl: a manifest GET
    # returns the immutable digest in the Docker-Content-Digest response
    # header. The curl mock emits a canned header block regardless of args
    # (the https attempt succeeds, so the http fallback is never reached).
    ok_headers() {
      printf 'HTTP/1.1 200 OK\r\nDocker-Content-Digest: %s\r\nContent-Type: application/vnd.oci.image.manifest.v1+json\r\n\r\n' "$1"
    }

    It "resolves a known version to a digest-pinned ref"
      resolve_ok() {
        mock.create_output "curl" "$(ok_headers "$VALID_DIGEST")" 0
        mock.activate
        channel.resolve_digest v1.2.3 release
      }
      When call resolve_ok
      The output should equal "registry.release/app@${VALID_DIGEST}"
    End

    It "fails external_fail (5) when the version is absent from the channel"
      resolve_absent() {
        # 404: the manifest endpoint returns no Docker-Content-Digest header.
        mock.create_output "curl" "$(printf 'HTTP/1.1 404 Not Found\r\n\r\n')" 0
        mock.activate
        channel.resolve_digest v9.9.9 release
      }
      When call resolve_absent
      The status should equal 5
      The stderr should include "digest"
    End

    It "fails external_fail (5) when the resolver returns a malformed digest"
      resolve_malformed() {
        mock.create_output "curl" "$(ok_headers "not-a-digest")" 0
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
        # resolver-missing path (curl absent) is the one under test.
        ln -s "$(command -v yq)" "${MOCK_BIN}/yq" 2>/dev/null || true
        mock.isolate
        channel.resolve_digest v1.2.3 release
      }
      When call resolve_no_tool
      The status should equal 3
      The stderr should include "curl"
    End
  End

  # =========================================================================
  # _channel._extract_digest (pure header parsing)
  # =========================================================================
  Describe "_channel._extract_digest"
    It "reads the digest from a CRLF header block"
      headers="$(printf 'HTTP/1.1 200 OK\r\nDocker-Content-Digest: %s\r\n' "$VALID_DIGEST")"
      When call _channel._extract_digest "$headers"
      The output should equal "$VALID_DIGEST"
    End

    It "is empty when no digest header is present"
      When call _channel._extract_digest "$(printf 'HTTP/1.1 404 Not Found\r\n')"
      The output should equal ""
    End
  End

  # =========================================================================
  # _channel._basic_credential (docker config, then BRIK_REGISTRY_* fallback)
  # =========================================================================
  Describe "_channel._basic_credential"
    It "derives Basic auth from BRIK_REGISTRY_* when no docker credential exists"
      from_env() {
        # No DOCKER_CONFIG file -> docker-config lookup misses; the env
        # convention (already used by lib/deployments/compose.sh) supplies it.
        export DOCKER_CONFIG="$(mktemp -d)"
        export BRIK_REGISTRY_USER="admin" BRIK_REGISTRY_PASSWORD="s3cr3t"
        _channel._basic_credential "nexus.internal:8082"
      }
      When call from_env
      The output should equal "$(printf 'admin:s3cr3t' | base64 | tr -d '\n')"
    End

    It "does not send env creds to a host other than BRIK_REGISTRY_HOST"
      wrong_host() {
        export DOCKER_CONFIG="$(mktemp -d)"
        export BRIK_REGISTRY_HOST="nexus.internal:8082"
        export BRIK_REGISTRY_USER="admin" BRIK_REGISTRY_PASSWORD="s3cr3t"
        _channel._basic_credential "other.registry:5000"
      }
      When call wrong_host
      The status should not equal 0
      The output should equal ""
    End
  End

  Describe "_channel._registry_digest input shape"
    BeforeEach 'mock.setup'
    AfterEach 'mock.cleanup'

    It "rejects a registry endpoint without a repository path"
      bad_registry() {
        mock.create_output "curl" "" 0
        mock.activate
        _channel._registry_digest "registry.only" v1.2.3
      }
      When call bad_registry
      The status should equal 5
      The stderr should include "repository"
    End
  End
End

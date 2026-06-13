Describe "transverse/channel.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_TRANSVERSE_LIB/env.sh"
  Include "$BRIK_TRANSVERSE_LIB/config.sh"
  Include "$BRIK_TRANSVERSE_LIB/infra.sh"
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

    # The transport to a registry comes from its declared Registry endpoint
    # in the infrastructure referential, never from a fallback.
    CHAN_INFRA="$(mktemp -d)"
    mkdir -p "$CHAN_INFRA/endpoints"
    printf 'apiVersion: brik.dev/referential/v1\nkind: Referential\nprofile: p-lab\n' \
      > "$CHAN_INFRA/referential.yml"
    cat > "$CHAN_INFRA/endpoints/registry-internal.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Registry
name: registry-internal
url: https://registry.internal
tls:
  trust: system
YAML
    cat > "$CHAN_INFRA/endpoints/registry-release.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Registry
name: registry-release
url: https://registry.release
tls:
  trust: system
YAML
    export BRIK_INFRA_DIR="$CHAN_INFRA"
  }
  cleanup_config() {
    rm -f "$CHAN_CFG"
    rm -rf "$CHAN_INFRA"
    unset BRIK_CONFIG_FILE BRIK_INFRA_DIR CHAN_INFRA
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
    # header. The curl mock emits a canned header block regardless of args;
    # the scheme it is called with comes from the declared Registry endpoint.
    ok_headers() {
      printf 'HTTP/1.1 200 OK\r\nDocker-Content-Digest: %s\r\nContent-Type: application/vnd.oci.image.manifest.v1+json\r\n\r\n' "$1"
    }

    # A curl mock that records its argv to MOCK_LOG and answers 200 + digest,
    # so a test can assert WHICH URL scheme the resolver used.
    recording_curl() {
      cat > "${MOCK_BIN}/curl" <<EOF
#!/bin/sh
echo "curl \$*" >> "${MOCK_LOG}"
printf 'HTTP/1.1 200 OK\r\nDocker-Content-Digest: ${VALID_DIGEST}\r\n\r\n'
EOF
      chmod +x "${MOCK_BIN}/curl"
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

    It "exchanges a bearer token on a 401 challenge, then resolves the digest"
      # Token-gated registries (ghcr, Docker Hub): the first manifest GET is
      # answered with a 401 + WWW-Authenticate Bearer realm, the realm GET
      # returns a token, and the authenticated retry returns the digest.
      resolve_bearer() {
        mock.create_script "curl" '
          case "$*" in
            *"/token"*) printf "{\"token\":\"TOK123\"}" ;;
            *Bearer*)   printf "HTTP/1.1 200 OK\r\nDocker-Content-Digest: '"${VALID_DIGEST}"'\r\n\r\n" ;;
            *)          printf "HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Bearer realm=\"https://registry.release/token\",service=\"registry.release\",scope=\"repository:app:pull\"\r\n\r\n" ;;
          esac'
        mock.activate
        channel.resolve_digest v1.2.3 release
      }
      When call resolve_bearer
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

    It "resolves over https when the endpoint declares https://"
      resolve_declared_https() {
        recording_curl
        mock.activate
        channel.resolve_digest v1.2.3 release >/dev/null || return $?
        mock.call_args curl
      }
      When call resolve_declared_https
      The output should include "https://registry.release/v2/app/manifests/v1.2.3"
    End

    It "resolves over http when the endpoint declares http:// (no fallback, a declaration)"
      resolve_declared_http() {
        yq -i '.url = "http://registry.release"' "$CHAN_INFRA/endpoints/registry-release.yml"
        recording_curl
        mock.activate
        channel.resolve_digest v1.2.3 release >/dev/null || return $?
        mock.call_args curl
      }
      When call resolve_declared_http
      The output should include "http://registry.release/v2/app/manifests/v1.2.3"
      The stderr should include "plain http"
    End

    It "fails closed (7) when the registry host is not declared in the referential"
      resolve_undeclared() {
        rm "$CHAN_INFRA/endpoints/registry-release.yml"
        mock.create_output "curl" "$(ok_headers "$VALID_DIGEST")" 0
        mock.activate
        channel.resolve_digest v1.2.3 release
      }
      When call resolve_undeclared
      The status should equal 7
      The stderr should include "registry.release"
    End

    It "fails closed (4) when no referential is configured at all"
      resolve_no_infra() {
        unset BRIK_INFRA_DIR
        mock.create_output "curl" "$(ok_headers "$VALID_DIGEST")" 0
        mock.activate
        channel.resolve_digest v1.2.3 release
      }
      When call resolve_no_infra
      The status should equal 4
      The stderr should include "brik infra init"
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

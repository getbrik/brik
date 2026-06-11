Describe "transverse/channel.sh copy_with_referrers"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_TRANSVERSE_LIB/env.sh"
  Include "$BRIK_TRANSVERSE_LIB/config.sh"
  Include "$BRIK_TRANSVERSE_LIB/infra.sh"
  Include "$BRIK_TRANSVERSE_LIB/channel.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  VALID_DIGEST="sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  OTHER_DIGEST="sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"

  # The evidence gate itself is attest_spec.sh's contract: stub it as a
  # function (the loader guard keeps brik.use from re-sourcing the module)
  # so this unit stays focused on the copy + fail-closed proof sequence.
  _BRIK_MODULE_TRANSVERSE_ATTEST_LOADED=1
  attest.verify() {
    printf 'attest.verify %s\n' "$*" >> "$MOCK_LOG"
    return "${ATTEST_RC:-0}"
  }

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

  BeforeEach 'mock.setup'
  AfterEach 'mock.cleanup'

  ok_headers() {
    printf 'HTTP/1.1 200 OK\r\nDocker-Content-Digest: %s\r\n\r\n' "$1"
  }

  # curl mock simulating a real promotion: the destination channel is EMPTY
  # (404) until the oras mock drops the populated marker, then resolves to
  # the digest given as $1; every other host resolves to VALID_DIGEST.
  mock_curl_dst() {
    cat > "${MOCK_BIN}/curl" <<EOF
#!/bin/sh
case "\$*" in
  *registry.release*)
    if [ -f "${MOCK_BIN}/.release-populated" ]; then
      printf 'HTTP/1.1 200 OK\r\nDocker-Content-Digest: ${1}\r\n\r\n'
    else
      printf 'HTTP/1.1 404 Not Found\r\n\r\n'
    fi ;;
  *) printf 'HTTP/1.1 200 OK\r\nDocker-Content-Digest: ${VALID_DIGEST}\r\n\r\n' ;;
esac
EOF
    chmod +x "${MOCK_BIN}/curl"
  }

  # oras mock: records its argv and populates the destination (the marker the
  # curl mock keys on), like a real copy would.
  mock_oras_ok() {
    cat > "${MOCK_BIN}/oras" <<EOF
#!/bin/sh
echo "oras \$*" >> "${MOCK_LOG}"
touch "${MOCK_BIN}/.release-populated"
EOF
    chmod +x "${MOCK_BIN}/oras"
  }

  mock_copy_ok() {
    mock_curl_dst "$VALID_DIGEST"
    mock_oras_ok
    mock.activate
  }

  # ==========================================================================
  # Input and dependency guards
  # ==========================================================================
  It "returns invalid_input (2) when version/from/to are missing"
    When call channel.copy_with_referrers v1.2.3 candidate
    The status should equal 2
    The stderr should include "required"
  End

  It "returns invalid_input (2) on an unknown option"
    When call channel.copy_with_referrers v1.2.3 candidate release --bogus x
    The status should equal 2
    The stderr should include "--bogus"
  End

  It "returns missing_dep (3) when oras is not on PATH"
    copy_no_oras() {
      mock.preserve_cmds
      mock.isolate
      channel.copy_with_referrers v1.2.3 candidate release
    }
    When call copy_no_oras
    The status should equal 3
    The stderr should include "oras"
  End

  It "returns config_error (7) when the destination channel is not declared"
    copy_ghost() {
      mock_copy_ok
      channel.copy_with_referrers v1.2.3 candidate ghost
    }
    When call copy_ghost
    The status should equal 7
    The stderr should include "ghost"
  End

  # ==========================================================================
  # Copy semantics
  # ==========================================================================
  It "copies the digest-pinned source ref to the destination version tag with referrers"
    copy_ok() {
      mock_copy_ok
      channel.copy_with_referrers v1.2.3 candidate release >/dev/null || return $?
      mock.call_args oras
    }
    When call copy_ok
    The output should include "cp -r"
    The output should include "registry.internal/app@${VALID_DIGEST} registry.release/app:v1.2.3"
    The stderr should include "copying"
  End

  It "echoes the digest-pinned destination ref"
    copy_pinned() {
      mock_copy_ok
      channel.copy_with_referrers v1.2.3 candidate release
    }
    When call copy_pinned
    The output should equal "registry.release/app@${VALID_DIGEST}"
    The stderr should include "copying"
  End

  It "uses plain-http on the side whose endpoint declares http://"
    copy_http_dst() {
      yq -i '.url = "http://registry.release"' "$CHAN_INFRA/endpoints/registry-release.yml"
      mock_copy_ok
      channel.copy_with_referrers v1.2.3 candidate release >/dev/null || return $?
      mock.call_args oras
    }
    When call copy_http_dst
    The output should include "--to-plain-http"
    The output should not include "--from-plain-http"
    The stderr should include "plain http"
  End

  It "uses insecure TLS on the side whose endpoint declares tls.trust: insecure"
    copy_insecure_src() {
      yq -i '.tls.trust = "insecure"' "$CHAN_INFRA/endpoints/registry-internal.yml"
      mock_copy_ok
      channel.copy_with_referrers v1.2.3 candidate release >/dev/null || return $?
      mock.call_args oras
    }
    When call copy_insecure_src
    The output should include "--from-insecure"
    The output should not include "--to-insecure"
    The stderr should include "copying"
  End

  It "passes the canonical registry credential to both sides when unscoped"
    copy_creds() {
      export BRIK_REGISTRY_USER="admin" BRIK_REGISTRY_PASSWORD="s3cr3t"
      mock_copy_ok
      channel.copy_with_referrers v1.2.3 candidate release >/dev/null || return $?
      mock.call_args oras
    }
    When call copy_creds
    The output should include "--from-username admin"
    The output should include "--to-username admin"
    The stderr should include "copying"
  End

  It "does not send the credential to a side other than BRIK_REGISTRY_HOST"
    copy_scoped_creds() {
      export BRIK_REGISTRY_HOST="registry.release"
      export BRIK_REGISTRY_USER="admin" BRIK_REGISTRY_PASSWORD="s3cr3t"
      mock_copy_ok
      channel.copy_with_referrers v1.2.3 candidate release >/dev/null || return $?
      mock.call_args oras
    }
    When call copy_scoped_creds
    The output should include "--to-username admin"
    The output should not include "--from-username"
    The stderr should include "copying"
  End

  It "fails closed (7) when the destination registry host is not declared in the referential"
    copy_undeclared_dst() {
      rm "$CHAN_INFRA/endpoints/registry-release.yml"
      mock_copy_ok
      channel.copy_with_referrers v1.2.3 candidate release
    }
    When call copy_undeclared_dst
    The status should equal 7
    The stderr should include "registry.release"
  End

  It "fails external_fail (5) when oras cp fails"
    copy_oras_fails() {
      mock_curl_dst "$VALID_DIGEST"
      mock.create_exit "oras" 1
      mock.activate
      channel.copy_with_referrers v1.2.3 candidate release
    }
    When call copy_oras_fails
    The status should equal 5
    The stderr should include "oras"
  End

  # ==========================================================================
  # Destination-channel immutability (release semantics, idempotent re-run)
  # ==========================================================================
  It "is an idempotent no-op when the destination already holds the version at the same digest"
    copy_noop() {
      mock.create_output "curl" "$(ok_headers "$VALID_DIGEST")" 0
      mock.create "oras"
      mock.activate
      channel.copy_with_referrers v1.2.3 candidate release >/dev/null || return $?
      mock.was_called oras && echo "oras-called"
      grep -o "attest.verify registry.release/app@${VALID_DIGEST}" "$MOCK_LOG"
    }
    When call copy_noop
    The output should equal "attest.verify registry.release/app@${VALID_DIGEST}"
    The stderr should include "no-op"
  End

  It "echoes the pinned destination ref on the idempotent no-op"
    copy_noop_ref() {
      mock.create_output "curl" "$(ok_headers "$VALID_DIGEST")" 0
      mock.create "oras"
      mock.activate
      channel.copy_with_referrers v1.2.3 candidate release
    }
    When call copy_noop_ref
    The output should equal "registry.release/app@${VALID_DIGEST}"
    The stderr should include "no-op"
  End

  It "fails check_failed (10) when the destination already holds the version at a different digest"
    copy_immutable() {
      cat > "${MOCK_BIN}/curl" <<EOF
#!/bin/sh
case "\$*" in
  *registry.release*) printf 'HTTP/1.1 200 OK\r\nDocker-Content-Digest: ${OTHER_DIGEST}\r\n\r\n' ;;
  *)                  printf 'HTTP/1.1 200 OK\r\nDocker-Content-Digest: ${VALID_DIGEST}\r\n\r\n' ;;
esac
EOF
      chmod +x "${MOCK_BIN}/curl"
      mock.create "oras"
      mock.activate
      channel.copy_with_referrers v1.2.3 candidate release || { local rc=$?; mock.was_called oras && echo "oras-called"; return $rc; }
    }
    When call copy_immutable
    The status should equal 10
    The output should equal ""
    The stderr should include "immutable"
  End

  # ==========================================================================
  # Fail-closed post-copy proof (the H13 lesson: a copy can silently drop
  # the evidence graph, so the destination must PROVE both bytes and proofs)
  # ==========================================================================
  It "fails external_fail (5) when the destination digest differs from the source"
    copy_digest_drift() {
      mock_curl_dst "$OTHER_DIGEST"
      mock_oras_ok
      mock.activate
      channel.copy_with_referrers v1.2.3 candidate release
    }
    When call copy_digest_drift
    The status should equal 5
    The stderr should include "digest mismatch"
  End

  It "verifies the attestations on the DESTINATION digest after the copy"
    copy_verify_dst() {
      mock_copy_ok
      channel.copy_with_referrers v1.2.3 candidate release >/dev/null || return $?
      grep 'attest.verify' "$MOCK_LOG"
    }
    When call copy_verify_dst
    The output should include "attest.verify registry.release/app@${VALID_DIGEST}"
    The stderr should include "copying"
  End

  It "forwards --identity and --issuer to the keyless verification"
    copy_keyless_expectations() {
      mock_copy_ok
      channel.copy_with_referrers v1.2.3 candidate release \
        --identity 'https://ci.example/.*' --issuer 'https://oidc.example' \
        >/dev/null || return $?
      grep 'attest.verify' "$MOCK_LOG"
    }
    When call copy_keyless_expectations
    The output should include "--identity https://ci.example/.*"
    The output should include "--issuer https://oidc.example"
    The stderr should include "copying"
  End

  It "fails external_fail (5) when the copied artifact has no verifiable evidence"
    copy_without_evidence() {
      ATTEST_RC=5
      mock_copy_ok
      channel.copy_with_referrers v1.2.3 candidate release
    }
    When call copy_without_evidence
    The status should equal 5
    The stderr should include "evidence"
  End
End

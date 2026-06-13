#shellcheck shell=bash
# Contract for lib/transverse/attest.sh -- cosign signing/verification of the
# published image digest (SBOM + SLSA provenance as OCI referrers).
#
# cosign and oras are stubbed as shell functions so the contract runs without
# the real binaries: the tests assert the argv the module builds and the
# keyless-vs-local-key mode switch, not network behaviour.

Describe "transverse.attest"
  BRIK_HOME="$(cd "${SHELLSPEC_PROJECT_ROOT}" && pwd)"
  export BRIK_HOME
  Include "${BRIK_HOME}/lib/pipeline/error.sh"

  # Minimal loader + logging stubs so the module under test sources cleanly.
  brik.use() { :; }
  log.info()  { :; }
  log.warn()  { :; }
  log.error() { printf 'ERROR: %s\n' "$*" >&2; }
  pipeline.require_tool() { command -v "$1" >/dev/null 2>&1; }

  Include "${BRIK_HOME}/lib/transverse/env.sh"
  Include "${BRIK_HOME}/lib/transverse/infra.sh"
  # channel.sh provides channel.scoped_docker_config: cosign authenticates to
  # the registry through a scoped DOCKER_CONFIG, never a --registry-password.
  Include "${BRIK_HOME}/lib/transverse/channel.sh"
  Include "${BRIK_HOME}/lib/transverse/attest.sh"

  # Record the argv cosign is called with for assertions, and declare the
  # registry the test REF lives in: cosign's registry-connection flags come
  # from the referential's Registry endpoint, fail-closed when undeclared.
  COSIGN_ARGS_FILE=""
  ATTEST_INFRA=""
  setup_recorder() {
    COSIGN_ARGS_FILE="$(mktemp)"
    # Record argv plus the KMS address env so tests can assert the OpenBAO
    # connection wiring without a real cosign.
    cosign() {
      printf '%s\n' "$*" >"$COSIGN_ARGS_FILE"
      printf 'BAO_ADDR=%s\n' "${BAO_ADDR:-}" >>"$COSIGN_ARGS_FILE"
      # Registry credentials must reach cosign through DOCKER_CONFIG, never the
      # argv (a --registry-password is visible in the process table). Record the
      # config auths so the spec can prove the credential travelled out of band.
      if [[ -f "${DOCKER_CONFIG:-}/config.json" ]]; then
        printf 'DOCKER_AUTHS=%s\n' \
          "$(jq -c '.auths // {}' "${DOCKER_CONFIG}/config.json" 2>/dev/null)" \
          >>"$COSIGN_ARGS_FILE"
      fi
      return 0
    }
    oras()   { printf '%s\n' "$*"; return 0; }

    ATTEST_INFRA="$(mktemp -d)"
    mkdir -p "$ATTEST_INFRA/endpoints"
    printf 'apiVersion: brik.dev/referential/v1\nkind: Referential\nprofile: p-lab\n' \
      > "$ATTEST_INFRA/referential.yml"
    cat > "$ATTEST_INFRA/endpoints/registry.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Registry
name: registry
url: https://registry.example.com
tls:
  trust: system
YAML
    cat > "$ATTEST_INFRA/endpoints/signing.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Signing
name: signing
backend: keyless
transparency: rekor-public
YAML
    export BRIK_INFRA_DIR="$ATTEST_INFRA"
  }

  # Switch the fixture's Signing endpoint to a referenced local key with no
  # transparency log (the air-gapped / lab posture).
  use_key_backend() {
    cat > "$ATTEST_INFRA/endpoints/signing.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Signing
name: signing
backend: key
key: env://COSIGN_PRIVATE_KEY
transparency: none
YAML
  }

  # Switch the fixture to the OpenBAO Transit KMS backend (key never leaves
  # the secret manager) and declare the SecretManager endpoint it needs.
  use_kms_backend() {
    cat > "$ATTEST_INFRA/endpoints/signing.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Signing
name: signing
backend: kms
kms_uri: openbao://brik-signing
transparency: none
YAML
    cat > "$ATTEST_INFRA/endpoints/secret-manager.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: SecretManager
name: secret-manager
url: http://bao.lab:8200
auth:
  method: token
  ref: env://ATTEST_SPEC_BAO_TOKEN
tls:
  trust: insecure
YAML
    export ATTEST_SPEC_BAO_TOKEN="t0ken"
  }
  cleanup_recorder() {
    [[ -n "$COSIGN_ARGS_FILE" ]] && rm -f "$COSIGN_ARGS_FILE"
    [[ -n "$ATTEST_INFRA" ]] && rm -rf "$ATTEST_INFRA"
    unset BRIK_INFRA_DIR
  }
  BeforeEach setup_recorder
  AfterEach cleanup_recorder

  REF="registry.example.com/app@sha256:1111111111111111111111111111111111111111111111111111111111111111"

  Describe "attest.mode"
    It "reads the keyless backend from the Signing endpoint"
      When call attest.mode
      The output should equal "keyless"
    End

    It "reads the key backend from the Signing endpoint"
      mode_key() { use_key_backend; attest.mode; }
      When call mode_key
      The output should equal "key"
    End

    It "reads the kms backend from the Signing endpoint"
      mode_kms() { use_kms_backend; attest.mode; }
      When call mode_kms
      The output should equal "kms"
    End

    It "fails closed (7) when no Signing endpoint is declared"
      mode_none() { rm "$ATTEST_INFRA/endpoints/signing.yml"; attest.mode; }
      When call mode_none
      The status should equal 7
      The stderr should include "Signing"
    End
  End

  Describe "attest.available"
    It "succeeds when cosign resolves"
      When call attest.available
      The status should be success
    End

    It "fails when cosign is absent"
      # Neutralise both the stub and any real cosign on PATH.
      unset -f cosign
      absent() { PATH="" attest.available; }
      When call absent
      The status should be failure
    End
  End

  Describe "attest.provenance_predicate"
    It "emits an in-toto SLSA predicate carrying version and commit"
      When call attest.provenance_predicate --version v1.2.3 --commit abc123 --repo git+https://x/y --builder brik/local --run-id run-9
      The output should include '"version": "v1.2.3"'
      The output should include '"commit": "abc123"'
      The output should include "buildDefinition"
      The output should include "run-9"
    End

    It "carries the brik builder-identity convention (builder.id + builder.version.brik)"
      convention() {
        attest.provenance_predicate \
          --version v1.2.3 --commit abc123 --repo git+https://x/y \
          --builder "https://gitlab.example/-/brik/scanner" \
          --brik-version 0.6.0 --run-id run-9 \
          | jq -r '.runDetails.builder.id, .runDetails.builder.version.brik'
      }
      When call convention
      The output should equal "https://gitlab.example/-/brik/scanner
0.6.0"
    End
  End

  Describe "attest.sign"
    It "rejects a ref without a digest (fail-closed)"
      When call attest.sign "registry.example.com/app:latest" --sbom /tmp/sbom.json
      The status should be failure
      The stderr should include "digest"
    End

    It "keyless: attaches the SBOM as a cyclonedx attestation on the digest"
      unset BRIK_COSIGN_KEY
      printf '{}' >"${SHELLSPEC_TMPBASE}/sbom.json"
      When call attest.sign "$REF" --sbom "${SHELLSPEC_TMPBASE}/sbom.json"
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should include "attest"
      The contents of file "$COSIGN_ARGS_FILE" should include "--type cyclonedx"
      The contents of file "$COSIGN_ARGS_FILE" should include "$REF"
      The contents of file "$COSIGN_ARGS_FILE" should not include "--key"
    End

    It "key backend: passes the referenced key and no-transparency flags"
      printf '{}' >"${SHELLSPEC_TMPBASE}/sbom.json"
      sign_key() { use_key_backend; attest.sign "$REF" --sbom "${SHELLSPEC_TMPBASE}/sbom.json"; }
      When call sign_key
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should include "--key env://COSIGN_PRIVATE_KEY"
      The contents of file "$COSIGN_ARGS_FILE" should include "--tlog-upload=false"
      The contents of file "$COSIGN_ARGS_FILE" should include "--use-signing-config=false"
    End

    It "kms backend: passes the KMS URI and wires the OpenBAO connection env"
      printf '{}' >"${SHELLSPEC_TMPBASE}/sbom.json"
      sign_kms() { use_kms_backend; attest.sign "$REF" --sbom "${SHELLSPEC_TMPBASE}/sbom.json"; }
      When call sign_kms
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should include "--key openbao://brik-signing"
      The contents of file "$COSIGN_ARGS_FILE" should include "--tlog-upload=false"
      The contents of file "$COSIGN_ARGS_FILE" should include "BAO_ADDR=http://bao.lab:8200"
    End

    It "key backend: refuses (7) a bao:// key reference (kms is the OpenBAO path)"
      printf '{}' >"${SHELLSPEC_TMPBASE}/sbom.json"
      sign_bao_key() {
        use_key_backend
        yq -i '.key = "bao://secret/ci/cosign#key"' "$ATTEST_INFRA/endpoints/signing.yml"
        attest.sign "$REF" --sbom "${SHELLSPEC_TMPBASE}/sbom.json"
      }
      When call sign_bao_key
      The status should equal 7
      The stderr should include "kms"
      The contents of file "$COSIGN_ARGS_FILE" should equal ""
    End

    It "dry-run does not invoke cosign"
      printf '{}' >"${SHELLSPEC_TMPBASE}/sbom.json"
      When call attest.sign "$REF" --sbom "${SHELLSPEC_TMPBASE}/sbom.json" --dry-run
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should equal ""
    End

    It "derives the HTTP flag from a declared http:// registry endpoint and keeps the credential out of the argv"
      unset BRIK_COSIGN_KEY
      export BRIK_REGISTRY_USER=u BRIK_REGISTRY_PASSWORD=p
      yq -i '.url = "http://registry.example.com"' "$ATTEST_INFRA/endpoints/registry.yml"
      printf '{}' >"${SHELLSPEC_TMPBASE}/sbom.json"
      When call attest.sign "$REF" --sbom "${SHELLSPEC_TMPBASE}/sbom.json"
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should include "--allow-http-registry"
      # The password never reaches the process table: cosign reads it from the
      # scoped DOCKER_CONFIG (base64 of "u:p" == "dTpw").
      The contents of file "$COSIGN_ARGS_FILE" should not include "--registry-password"
      The contents of file "$COSIGN_ARGS_FILE" should not include "--registry-username"
      The contents of file "$COSIGN_ARGS_FILE" should include "dTpw"
    End

    It "derives --allow-insecure-registry from a declared tls.trust: insecure https endpoint"
      unset BRIK_COSIGN_KEY BRIK_REGISTRY_USER BRIK_REGISTRY_PASSWORD
      yq -i '.tls.trust = "insecure"' "$ATTEST_INFRA/endpoints/registry.yml"
      printf '{}' >"${SHELLSPEC_TMPBASE}/sbom.json"
      When call attest.sign "$REF" --sbom "${SHELLSPEC_TMPBASE}/sbom.json"
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should include "--allow-insecure-registry"
      The contents of file "$COSIGN_ARGS_FILE" should not include "--allow-http-registry"
    End

    It "derives --registry-cacert from a declared tls.trust: custom-ca endpoint"
      unset BRIK_COSIGN_KEY BRIK_REGISTRY_USER BRIK_REGISTRY_PASSWORD
      yq -i '.tls.trust = "custom-ca"' "$ATTEST_INFRA/endpoints/registry.yml"
      reg_host="$(yq '.url' "$ATTEST_INFRA/endpoints/registry.yml")"
      reg_host="${reg_host#*://}"; reg_host="${reg_host%%/*}"; reg_host="${reg_host%%:*}"
      mkdir -p "$ATTEST_INFRA/trust/ca/${reg_host}"
      printf 'PEM\n' > "$ATTEST_INFRA/trust/ca/${reg_host}/ca.crt"
      printf '{}' >"${SHELLSPEC_TMPBASE}/sbom.json"
      When call attest.sign "$REF" --sbom "${SHELLSPEC_TMPBASE}/sbom.json"
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should include "--registry-cacert"
      The contents of file "$COSIGN_ARGS_FILE" should include "trust/ca/${reg_host}/ca.crt"
      The contents of file "$COSIGN_ARGS_FILE" should not include "--allow-insecure-registry"
    End

    It "fails closed (7) when custom-ca is declared without its bundle"
      unset BRIK_COSIGN_KEY
      yq -i '.tls.trust = "custom-ca"' "$ATTEST_INFRA/endpoints/registry.yml"
      printf '{}' >"${SHELLSPEC_TMPBASE}/sbom.json"
      When call attest.sign "$REF" --sbom "${SHELLSPEC_TMPBASE}/sbom.json"
      The status should equal 7
      The stderr should include "custom-ca"
    End

    It "fails closed (7) when the ref's registry host is not declared"
      unset BRIK_COSIGN_KEY
      rm "$ATTEST_INFRA/endpoints/registry.yml"
      printf '{}' >"${SHELLSPEC_TMPBASE}/sbom.json"
      When call attest.sign "$REF" --sbom "${SHELLSPEC_TMPBASE}/sbom.json"
      The status should equal 7
      The stderr should include "registry.example.com"
      The contents of file "$COSIGN_ARGS_FILE" should equal ""
    End

    It "fails closed (4) when no referential is configured"
      unset BRIK_COSIGN_KEY BRIK_INFRA_DIR
      printf '{}' >"${SHELLSPEC_TMPBASE}/sbom.json"
      When call attest.sign "$REF" --sbom "${SHELLSPEC_TMPBASE}/sbom.json"
      The status should equal 4
      The stderr should include "brik infra init"
      The contents of file "$COSIGN_ARGS_FILE" should equal ""
    End
  End

  Describe "attest.verify_provenance"
    # cosign is stubbed to emit a DSSE envelope wrapping a brik provenance
    # predicate, so the contract checks the expectation logic for real.
    make_envelope() {
      local version="$1" builder="$2" source_uri="$3"
      jq -cn --arg v "$version" --arg b "$builder" --arg s "$source_uri" '
        {
          buildDefinition: { externalParameters: { version: $v },
                             resolvedDependencies: [ { uri: $s } ] },
          runDetails: { builder: { id: $b, version: { brik: "0.6.0" } } }
        } as $pred
        | { _type: "https://in-toto.io/Statement/v1",
            predicateType: "https://slsa.dev/provenance/v1",
            predicate: $pred }
        | { payloadType: "application/vnd.in-toto+json",
            payload: (tojson | @base64) }'
    }
    setup_envelope() {
      ENVELOPE_FILE="$(mktemp)"
      cosign() {
        printf '%s\n' "$*" >"$COSIGN_ARGS_FILE"
        cat "$ENVELOPE_FILE"
      }
    }
    cleanup_envelope() { rm -f "$ENVELOPE_FILE"; }
    BeforeEach setup_envelope
    AfterEach cleanup_envelope

    It "accepts a provenance matching the version, builder and source expectations"
      ok() {
        unset BRIK_COSIGN_KEY
        make_envelope "v1.2.3" "https://gitlab.example/-/brik/scanner" "git+https://gitlab.example/team/app" >"$ENVELOPE_FILE"
        attest.verify_provenance "$REF" \
          --expect-version "1.2.3,v1.2.3" \
          --expect-builder-re '^https://gitlab\.example/-/brik/' \
          --expect-source-re 'gitlab\.example/team/app$' \
          --identity 'https://ci/.*' --issuer 'https://issuer'
      }
      When call ok
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should include "--type slsaprovenance1"
    End

    It "fails closed when the predicate version is not the deployed version"
      ko() {
        unset BRIK_COSIGN_KEY
        make_envelope "v9.9.9" "https://gitlab.example/-/brik/scanner" "git+https://x/y" >"$ENVELOPE_FILE"
        attest.verify_provenance "$REF" --expect-version "1.2.3,v1.2.3" \
          --identity 'https://ci/.*' --issuer 'https://issuer'
      }
      When call ko
      The status should equal "$BRIK_EXIT_CHECK_FAILED"
      The stderr should include "expectation"
    End

    It "fails closed when the builder does not match the expected convention"
      ko() {
        unset BRIK_COSIGN_KEY
        make_envelope "v1.2.3" "https://evil.example/-/brik/scanner" "git+https://x/y" >"$ENVELOPE_FILE"
        attest.verify_provenance "$REF" --expect-version "1.2.3,v1.2.3" \
          --expect-builder-re '^https://gitlab\.example/-/brik/' \
          --identity 'https://ci/.*' --issuer 'https://issuer'
      }
      When call ko
      The status should equal "$BRIK_EXIT_CHECK_FAILED"
      The stderr should include "expectation"
    End

    It "fails closed when the source repo does not match"
      ko() {
        unset BRIK_COSIGN_KEY
        make_envelope "v1.2.3" "https://gitlab.example/-/brik/scanner" "git+https://evil/y" >"$ENVELOPE_FILE"
        attest.verify_provenance "$REF" --expect-version "1.2.3,v1.2.3" \
          --expect-source-re 'gitlab\.example/team/app$' \
          --identity 'https://ci/.*' --issuer 'https://issuer'
      }
      When call ko
      The status should equal "$BRIK_EXIT_CHECK_FAILED"
      The stderr should include "expectation"
    End

    It "fails closed when verification yields no provenance payload"
      ko() {
        unset BRIK_COSIGN_KEY
        : >"$ENVELOPE_FILE"
        attest.verify_provenance "$REF" --expect-version "1.2.3" \
          --identity 'https://ci/.*' --issuer 'https://issuer'
      }
      When call ko
      The status should equal "$BRIK_EXIT_CHECK_FAILED"
      The stderr should include "payload"
    End
  End

  Describe "attest.verify"
    It "rejects a ref without a digest (fail-closed)"
      When call attest.verify "registry.example.com/app:latest"
      The status should be failure
      The stderr should include "digest"
    End

    It "keyless: verifies with identity and issuer constraints"
      unset BRIK_COSIGN_KEY
      When call attest.verify "$REF" --identity 'https://gitlab/.*' --issuer 'https://gitlab'
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should include "verify-attestation"
      The contents of file "$COSIGN_ARGS_FILE" should include "--certificate-identity-regexp https://gitlab/.*"
      The contents of file "$COSIGN_ARGS_FILE" should include "--certificate-oidc-issuer-regexp https://gitlab"
    End

    It "keyless: fails closed without --identity and --issuer (would accept any Fulcio cert)"
      unset BRIK_COSIGN_KEY
      When call attest.verify "$REF"
      The status should equal 2
      The stderr should include "keyless verification requires --identity and --issuer"
      # cosign must never run: an unconstrained verify is the fail-open the gate prevents.
      The contents of file "$COSIGN_ARGS_FILE" should equal ""
    End

    It "keyless: fails closed with --identity but no --issuer"
      unset BRIK_COSIGN_KEY
      When call attest.verify "$REF" --identity 'https://gitlab/.*'
      The status should equal 2
      The stderr should include "keyless verification requires --identity and --issuer"
    End

    It "key backend: verifies with the referenced key and ignores the absent tlog"
      verify_key() { use_key_backend; attest.verify "$REF"; }
      When call verify_key
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should include "--key env://COSIGN_PRIVATE_KEY"
      The contents of file "$COSIGN_ARGS_FILE" should include "--insecure-ignore-tlog=true"
    End

    It "key backend: prefers the declared verification_key on verify (cosign rejects private keys)"
      verify_pub() {
        use_key_backend
        printf 'verification_key: env://COSIGN_PUBLIC_KEY\n' \
          >> "$ATTEST_INFRA/endpoints/signing.yml"
        attest.verify "$REF"
      }
      When call verify_pub
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should include "--key env://COSIGN_PUBLIC_KEY"
      The contents of file "$COSIGN_ARGS_FILE" should not include "--key env://COSIGN_PRIVATE_KEY"
    End

    It "key backend: file:// key resolves even when only subshells loaded the infra module"
      sign_fresh_shell() {
        use_key_backend
        printf 'apiVersion: brik.dev/referential/v1\nkind: Signing\nname: signing\nbackend: key\nkey: file://trust/cosign.key\ntransparency: none\n' \
          > "$ATTEST_INFRA/endpoints/signing.yml"
        mkdir -p "$ATTEST_INFRA/trust" && : > "$ATTEST_INFRA/trust/cosign.key"
        # Simulate the runtime: attest.sh sourced, infra.* NOT yet loaded in
        # the calling shell (its first load happened inside a command
        # substitution). brik.use must bring it back in THIS shell.
        (
          while IFS= read -r _fn; do unset -f "$_fn"; done \
            < <(declare -F | awk '$3 ~ /^_?infra\./ {print $3}')
          unset _BRIK_MODULE_TRANSVERSE_INFRA_LOADED
          brik.use() { . "${BRIK_HOME}/lib/transverse/${1#transverse.}.sh"; }
          attest.sign "$REF" --sbom "${SHELLSPEC_TMPBASE}/sbom.json"
        )
      }
      When call sign_fresh_shell
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should include "--key $ATTEST_INFRA/trust/cosign.key"
    End

    It "key backend: still signs with the private key when verification_key is declared"
      sign_with_pub() {
        use_key_backend
        printf 'verification_key: env://COSIGN_PUBLIC_KEY\n' \
          >> "$ATTEST_INFRA/endpoints/signing.yml"
        attest.sign "$REF" --sbom "${SHELLSPEC_TMPBASE}/sbom.json"
      }
      When call sign_with_pub
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should include "--key env://COSIGN_PRIVATE_KEY"
    End

    It "kms backend: prefers the declared verification_key on verify (no KMS round-trip, no token)"
      verify_kms_pub() {
        use_kms_backend
        printf 'verification_key: env://COSIGN_PUBLIC_KEY\n' \
          >> "$ATTEST_INFRA/endpoints/signing.yml"
        attest.verify "$REF"
      }
      When call verify_kms_pub
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should include "--key env://COSIGN_PUBLIC_KEY"
      The contents of file "$COSIGN_ARGS_FILE" should not include "openbao://brik-signing"
      The contents of file "$COSIGN_ARGS_FILE" should not include "BAO_ADDR=http"
    End

    It "kms backend: still signs through the KMS when verification_key is declared"
      sign_kms_pub() {
        use_kms_backend
        printf 'verification_key: env://COSIGN_PUBLIC_KEY\n' \
          >> "$ATTEST_INFRA/endpoints/signing.yml"
        attest.sign "$REF" --sbom "${SHELLSPEC_TMPBASE}/sbom.json"
      }
      When call sign_kms_pub
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should include "--key openbao://brik-signing"
      The contents of file "$COSIGN_ARGS_FILE" should include "BAO_ADDR=http://bao.lab:8200"
    End

    It "discards the verified attestation envelope from stdout (multi-MB payload)"
      verify_quiet() {
        # On success cosign prints the whole verified in-toto envelope
        # (base64 SBOM, megabytes) to stdout; the job log must not carry it.
        cosign() {
          printf '%s\n' "$*" > "$COSIGN_ARGS_FILE"
          printf '{"payload":"QkFTRTY0LXNCT00tYmxvYg=="}\n'
          return 0
        }
        attest.verify "$REF" --identity 'https://x/.*' --issuer 'https://x'
      }
      When call verify_quiet
      The status should be success
      The output should equal ""
    End

    It "propagates a cosign verification failure (fail-closed)"
      cosign() { return 1; }
      When call attest.verify "$REF" --identity 'x' --issuer 'y'
      The status should be failure
      The stderr should include "did not verify"
    End
  End
End

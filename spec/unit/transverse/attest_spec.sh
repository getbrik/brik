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

  Include "${BRIK_HOME}/lib/transverse/attest.sh"

  # Record the argv cosign is called with for assertions.
  COSIGN_ARGS_FILE=""
  setup_recorder() {
    COSIGN_ARGS_FILE="$(mktemp)"
    cosign() { printf '%s\n' "$*" >"$COSIGN_ARGS_FILE"; return 0; }
    oras()   { printf '%s\n' "$*"; return 0; }
  }
  cleanup_recorder() { [[ -n "$COSIGN_ARGS_FILE" ]] && rm -f "$COSIGN_ARGS_FILE"; }
  BeforeEach setup_recorder
  AfterEach cleanup_recorder

  REF="registry.example.com/app@sha256:1111111111111111111111111111111111111111111111111111111111111111"

  Describe "attest.mode"
    It "is keyless by default"
      unset BRIK_COSIGN_KEY
      When call attest.mode
      The output should equal "keyless"
    End

    It "switches to key when BRIK_COSIGN_KEY is set"
      BRIK_COSIGN_KEY="cosign.key"
      When call attest.mode
      The output should equal "key"
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

    It "key mode: passes the local key to cosign"
      BRIK_COSIGN_KEY="env://COSIGN_PRIVATE_KEY"
      printf '{}' >"${SHELLSPEC_TMPBASE}/sbom.json"
      When call attest.sign "$REF" --sbom "${SHELLSPEC_TMPBASE}/sbom.json"
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should include "--key env://COSIGN_PRIVATE_KEY"
      The contents of file "$COSIGN_ARGS_FILE" should include "--tlog-upload=false"
      The contents of file "$COSIGN_ARGS_FILE" should include "--use-signing-config=false"
    End

    It "dry-run does not invoke cosign"
      printf '{}' >"${SHELLSPEC_TMPBASE}/sbom.json"
      When call attest.sign "$REF" --sbom "${SHELLSPEC_TMPBASE}/sbom.json" --dry-run
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should equal ""
    End

    It "passes registry HTTP + auth flags when configured (insecure lab registry)"
      unset BRIK_COSIGN_KEY
      export BRIK_COSIGN_ALLOW_HTTP=true BRIK_REGISTRY_USER=u BRIK_REGISTRY_PASSWORD=p
      printf '{}' >"${SHELLSPEC_TMPBASE}/sbom.json"
      When call attest.sign "$REF" --sbom "${SHELLSPEC_TMPBASE}/sbom.json"
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should include "--allow-http-registry"
      The contents of file "$COSIGN_ARGS_FILE" should include "--registry-username u"
      The contents of file "$COSIGN_ARGS_FILE" should include "--registry-password p"
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

    It "key mode: verifies with the local key"
      BRIK_COSIGN_KEY="env://COSIGN_PUBLIC_KEY"
      When call attest.verify "$REF"
      The status should be success
      The contents of file "$COSIGN_ARGS_FILE" should include "--key env://COSIGN_PUBLIC_KEY"
      The contents of file "$COSIGN_ARGS_FILE" should include "--insecure-ignore-tlog=true"
    End

    It "propagates a cosign verification failure (fail-closed)"
      cosign() { return 1; }
      When call attest.verify "$REF" --identity 'x' --issuer 'y'
      The status should be failure
      The stderr should include "did not verify"
    End
  End
End

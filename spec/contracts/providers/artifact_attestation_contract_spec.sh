#shellcheck shell=bash
# Conformance for the artifact-attestation/v1 capability contract, cosign
# providers. Two of the three D12 stages live in brik (stage 3, behavioural,
# lives in briklab):
#
#   Stage 1 -- runtime introspection (this file, below): providers.verify_contract
#     proves, fail-closed, that the provider module exposes every operation the
#     contract requires (presence-only; never invokes them).
#   Stage 2 -- unit obligations C1/C4/C8 (Phase 3): added with `brik provider test`.
#
# Mirror: ADR-002 mechanism 2 (declare -f presence check), registry contract
# helpers.

Describe "artifact-attestation/v1 conformance (cosign)"
  BeforeAll '! [[ -f "$BRIK_HOME/lib/registry/cache/registry.json" ]] && "$BRIK_HOME/scripts/compile-registry.sh" >/dev/null 2>&1; true'

  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_HOME/lib/registry/registry.sh"
  Include "$BRIK_HOME/lib/providers/_verify_contract.sh"

  # A 64-hex digest-pinned reference (passes the digest precondition so the
  # later obligations -- not the precondition -- are what gets exercised).
  REF_DIGEST="registry.example.com/app@sha256:1111111111111111111111111111111111111111111111111111111111111111"

  Describe "contract data"
    It "declares the three required operations in order"
      ops_joined() { registry.contract.operations "artifact-attestation/v1" | tr '\n' ',' ; }
      When call ops_joined
      The output should equal "available,sign,verify,"
    End

    It "governs the artifact-attestation capability"
      When call registry.contract.capability "artifact-attestation/v1"
      The output should equal "artifact-attestation"
    End
  End

  Describe "stage 1 -- runtime introspection (providers.verify_contract)"
    It "passes for cosign-key (module exposes available/sign/verify)"
      When call providers.verify_contract cosign-key
      The status should be success
    End

    It "passes for cosign-keyless and cosign-kms-openbao (shared cosign module)"
      verify_both() {
        providers.verify_contract cosign-keyless && providers.verify_contract cosign-kms-openbao
      }
      When call verify_both
      The status should be success
    End

    It "fails (CONFIG_ERROR=7) for an unknown provider"
      When call providers.verify_contract ghost-signing
      The status should equal 7
      The stderr should include "unknown provider"
    End

    It "rejects an empty provider id (INVALID_INPUT=2)"
      When call providers.verify_contract ""
      The status should equal 2
      The stderr should include "provider id required"
    End

    It "fails (CONFIG_ERROR=7) when the module is amputated of a required operation"
      # Load the real module, drop one operation, then introspect. The internal
      # brik.use is guarded, so the unset sticks -- proving fail-closed.
      amputate_verify() {
        brik.use providers.cosign
        unset -f providers.cosign.verify
        providers.verify_contract cosign-key
      }
      When call amputate_verify
      The status should equal 7
      The stderr should include "missing required operation: verify"
    End
  End

  Describe "stage 2 -- unit obligations (infra-free)"
    It "C1: signing a mutable (non-digest) tag is refused (INVALID_INPUT=2)"
      # The digest precondition fires before any tool / registry / Signing
      # dependency, so no infrastructure is needed.
      sign_tag() { brik.use providers.cosign; providers.cosign.sign "registry.test/app:latest" --sbom /dev/null; }
      When call sign_tag
      The status should equal 2
      The stderr should include "digest-pinned"
    End

    It "C1 via the cosign capability conformance hook reports ok (rc 0)"
      run_hook() { brik.use providers.cosign; providers.cosign.conformance_unit; }
      When call run_hook
      The status should be success
      The output should include "C1 ok"
    End

    It "C8: an unknown provider is a CONFIG_ERROR (mirrored as an obligation)"
      When call providers.verify_contract not-a-provider
      The status should equal 7
      The stderr should include "unknown provider"
    End
  End

  Describe "stage 2 -- C4 keyless verify obligation (keyless Signing fixture)"
    # C4 sits AFTER require_tool(cosign) + Signing-referential resolution in
    # attest.verify, so it is a harness obligation (controlled keyless fixture
    # + cosign stub), not a check against a live referential. Mirrors the
    # keyless fixture in spec/unit/transverse/attest_spec.sh.
    setup_keyless() {
      C4_INFRA="$(mktemp -d)"
      mkdir -p "$C4_INFRA/endpoints"
      printf 'apiVersion: brik.dev/referential/v1\nkind: Referential\nprofile: p-lab\n' \
        > "$C4_INFRA/referential.yml"
      cat > "$C4_INFRA/endpoints/signing.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Signing
name: signing
backend: keyless
transparency: rekor-public
YAML
      export BRIK_INFRA_DIR="$C4_INFRA"
      # command -v finds a shell function, so this satisfies require_tool cosign
      # without a real binary; the keyless check returns before cosign is run.
      cosign() { return 0; }
    }
    cleanup_keyless() {
      unset -f cosign 2>/dev/null || true
      [[ -n "${C4_INFRA:-}" ]] && rm -rf "$C4_INFRA"
      unset BRIK_INFRA_DIR
    }
    BeforeEach setup_keyless
    AfterEach cleanup_keyless

    It "C4: keyless verify without identity/issuer is refused (INVALID_INPUT=2)"
      verify_keyless() { brik.use providers.cosign; providers.cosign.verify "$REF_DIGEST"; }
      When call verify_keyless
      The status should equal 2
      The stderr should include "identity"
    End
  End
End

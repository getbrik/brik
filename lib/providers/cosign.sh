#!/usr/bin/env bash
# @module providers/cosign
# @uses transverse.attest
# @description artifact-attestation provider backed by cosign. Thin adapters
# exposing the contract operations (available/sign/verify) as
# providers.cosign.<op> over the existing transverse.attest implementation.
#
# The three cosign-* manifests (key/keyless/kms-openbao) share this single
# module: the implementing tool is the same cosign binary and the operative
# difference (local key vs keyless Fulcio/Rekor vs OpenBAO KMS) is driven by
# the Signing referential that attest.* already reads -- not by the provider
# id. Provider-id-driven selection lands with P-A2/P-B; it is out of D12 scope.
# D12 only proves that this provider satisfies the artifact-attestation/v1
# contract (presence of the required operations + behavioural conformance).

# Guard against double-sourcing.
[[ -n "${_BRIK_PROVIDERS_COSIGN_LOADED:-}" ]] && return 0
_BRIK_PROVIDERS_COSIGN_LOADED=1

# providers.cosign.available - rc 0 when the cosign signer is usable.
providers.cosign.available() {
    brik.use transverse.attest || return $?
    attest.available "$@"
}

# providers.cosign.sign <ref> --sbom <file> [--provenance <file>]
# Attach the signed SBOM (and optional provenance) attestation to a digest.
providers.cosign.sign() {
    brik.use transverse.attest || return $?
    attest.sign "$@"
}

# providers.cosign.verify <ref> [--type <t>] [--identity <re>] [--issuer <re>]
# Verify the attestations attached to a digest, fail-closed.
providers.cosign.verify() {
    brik.use transverse.attest || return $?
    attest.verify "$@"
}

# providers.cosign.conformance_unit - infra-free unit obligations for the
# artifact-attestation contract (D12 stage 2). Run by `brik provider test`.
#
# Covers C1: signing a mutable (non-digest-pinned) tag must be refused with
# INVALID_INPUT -- the digest precondition fires before any tool, registry or
# Signing-endpoint dependency, so this needs no real infrastructure.
#
# Out of scope here (need a controlled fixture or real infra): C4 (keyless
# verify without identity/issuer) is proven by the conformance spec with a
# keyless Signing fixture; C2/C3/C5/C7 are behavioural (briklab, stage 3).
#
# Prints a one-line summary; returns 0 when every covered obligation holds.
providers.cosign.conformance_unit() {
    brik.use transverse.attest || return $?

    local rc
    providers.cosign.sign "registry.invalid/app:latest" --sbom /dev/null >/dev/null 2>&1
    rc=$?
    if [[ "$rc" -ne "$BRIK_EXIT_INVALID_INPUT" ]]; then
        printf 'C1 FAILED: sign on a mutable tag returned %s, expected %s (INVALID_INPUT)' \
            "$rc" "$BRIK_EXIT_INVALID_INPUT"
        return 1
    fi
    printf 'C1 ok (sign on a mutable tag refused, INVALID_INPUT)'
    return 0
}

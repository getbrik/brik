#!/usr/bin/env bash
# @module transverse.attest
# @requires cosign jq
# @description Sign and verify supply-chain evidence on a published image digest.
#
# After the image is pushed, CI attaches its SBOM and SLSA provenance to the
# image digest as signed OCI 1.1 referrers (cosign attestations). Before a
# deploy, CD verifies those attestations and refuses an image whose evidence
# does not verify -- the digest is the subject, so a tampered image yields a
# different digest and fails the gate.
#
# Two signing modes, selected by BRIK_COSIGN_KEY:
#   keyless (default) - Fulcio short-lived cert from the platform OIDC token,
#                       transparency via Rekor. Use in hosted CI.
#   key               - BRIK_COSIGN_KEY (e.g. env://COSIGN_PRIVATE_KEY or a
#                       file path) for air-gapped runners with no OIDC.
#
# Functions:
#   attest.mode                  - echo "keyless" | "key"
#   attest.available             - rc 0 when cosign is on PATH
#   attest.provenance_predicate  - emit an in-toto SLSA provenance predicate
#   attest.sign <ref> --sbom F   - attach signed SBOM (+ provenance) to a digest
#   attest.verify <ref>          - verify the attestations, fail-closed

# Guard against double-sourcing
[[ -n "${_BRIK_MODULE_TRANSVERSE_ATTEST_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_ATTEST_LOADED=1

# Signing mode: local key when BRIK_COSIGN_KEY is set, keyless otherwise.
attest.mode() {
    if [[ -n "${BRIK_COSIGN_KEY:-}" ]]; then
        printf 'key'
    else
        printf 'keyless'
    fi
}

# Return 0 when the cosign signer is available on this runner.
attest.available() {
    command -v cosign >/dev/null 2>&1
}

# Reject a reference that is not pinned to a digest. Signing or verifying a
# mutable tag would attach/verify evidence against whatever the tag points to
# at the time, defeating the content-addressing guarantee.
# Usage: _attest._require_digest <ref>
_attest._require_digest() {
    local ref="$1"
    if [[ "$ref" != *@sha256:* ]]; then
        log.error "attest: reference is not digest-pinned (need name@sha256:...): ${ref}"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    return 0
}

# Emit an in-toto SLSA provenance predicate body (the document cosign wraps as
# a slsaprovenance attestation). Captures the version, source commit, builder
# identity and CI run id so a deploy can trace an image back to its build.
# Usage: attest.provenance_predicate --version V --commit C --repo R
#                                    --builder B --run-id ID
attest.provenance_predicate() {
    local version="" commit="" repo="" builder="" run_id=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version) version="$2"; shift 2 ;;
            --commit)  commit="$2";  shift 2 ;;
            --repo)    repo="$2";    shift 2 ;;
            --builder) builder="$2"; shift 2 ;;
            --run-id)  run_id="$2";  shift 2 ;;
            *) log.error "attest.provenance_predicate: unknown option: $1"
               return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    # KCOV_EXCL_START -- inline jq document body, not bash code
    jq -n \
        --arg version "$version" \
        --arg commit "$commit" \
        --arg repo "$repo" \
        --arg builder "$builder" \
        --arg run_id "$run_id" \
        '{
          buildDefinition: {
            buildType: "https://brik.sh/ci/v1",
            externalParameters: { version: $version, commit: $commit },
            internalParameters: {},
            resolvedDependencies: [ { uri: $repo, digest: { sha1: $commit } } ]
          },
          runDetails: {
            builder: { id: $builder },
            metadata: { invocationId: $run_id }
          }
        }'
    # KCOV_EXCL_STOP
}

# Attach a signed attestation to the image digest. The SBOM is required; an
# optional provenance predicate is attached as a second attestation. In keyless
# mode cosign signs with a Fulcio cert from the ambient OIDC token; in key mode
# it signs with BRIK_COSIGN_KEY.
# Usage: attest.sign <ref> --sbom <file> [--provenance <file>]
#        [--sbom-type <t>] [--dry-run]
attest.sign() {
    local ref="${1:-}"
    [[ $# -ge 1 ]] && shift
    local sbom="" provenance="" sbom_type="cyclonedx" dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sbom)       sbom="$2";       shift 2 ;;
            --provenance) provenance="$2"; shift 2 ;;
            --sbom-type)  sbom_type="$2";  shift 2 ;;
            --dry-run)    dry_run="true";  shift ;;
            *) log.error "attest.sign: unknown option: $1"
               return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$ref" ]]; then
        log.error "attest.sign: image reference is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    _attest._require_digest "$ref" || return $?
    if [[ -z "$sbom" ]]; then
        log.error "attest.sign: --sbom is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    pipeline.require_tool cosign || return "$BRIK_EXIT_MISSING_DEP"

    # Key flag plus transparency-log policy, shared by every attestation.
    # Local-key signing targets environments without Sigstore infrastructure, so
    # it does not publish to the public Rekor transparency log; keyless keeps the
    # tlog (public transparency is the point of keyless).
    local -a key_args=()
    [[ "$(attest.mode)" == "key" ]] && key_args=(--key "$BRIK_COSIGN_KEY" --tlog-upload=false)

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would attest (${sbom_type}$([[ -n "$provenance" ]] && printf ' + provenance')) on ${ref} [$(attest.mode)]"
        return 0
    fi

    if [[ ! -f "$sbom" ]]; then
        log.error "attest.sign: SBOM file not found: ${sbom}"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    log.info "attesting ${sbom_type} SBOM on ${ref} [$(attest.mode)]"
    if ! cosign attest "${key_args[@]}" --predicate "$sbom" --type "$sbom_type" -y "$ref"; then
        log.error "attest.sign: cosign failed to attach the SBOM attestation"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    if [[ -n "$provenance" ]]; then
        if [[ ! -f "$provenance" ]]; then
            log.error "attest.sign: provenance file not found: ${provenance}"
            return "$BRIK_EXIT_IO_FAILURE"
        fi
        log.info "attesting SLSA provenance on ${ref} [$(attest.mode)]"
        if ! cosign attest "${key_args[@]}" --predicate "$provenance" --type slsaprovenance -y "$ref"; then
            log.error "attest.sign: cosign failed to attach the provenance attestation"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        fi
    fi
    return 0
}

# Verify the signed attestations on an image digest. Fail-closed: any missing
# or unverifiable attestation returns non-zero so the caller refuses the deploy.
# Keyless verification pins the expected signer identity and OIDC issuer; key
# verification uses BRIK_COSIGN_KEY.
# Usage: attest.verify <ref> [--type <t>] [--identity <re>] [--issuer <re>]
#        [--dry-run]
attest.verify() {
    local ref="${1:-}"
    [[ $# -ge 1 ]] && shift
    local att_type="cyclonedx" identity="" issuer="" dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)     att_type="$2"; shift 2 ;;
            --identity) identity="$2"; shift 2 ;;
            --issuer)   issuer="$2";   shift 2 ;;
            --dry-run)  dry_run="true"; shift ;;
            *) log.error "attest.verify: unknown option: $1"
               return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$ref" ]]; then
        log.error "attest.verify: image reference is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    _attest._require_digest "$ref" || return $?

    pipeline.require_tool cosign || return "$BRIK_EXIT_MISSING_DEP"

    local -a args=(verify-attestation --type "$att_type")
    if [[ "$(attest.mode)" == "key" ]]; then
        # Local key: signing created no public tlog entry, so do not require one.
        args+=(--key "$BRIK_COSIGN_KEY" --insecure-ignore-tlog=true)
    else
        # Keyless: the signer identity and issuer are the residual root of
        # trust (who is allowed to sign). Without them the verification would
        # accept any Fulcio cert, so leaving them empty is itself a failure.
        if [[ -z "$identity" || -z "$issuer" ]]; then
            log.error "attest.verify: keyless verification requires --identity and --issuer"
            return "$BRIK_EXIT_INVALID_INPUT"
        fi
        args+=(--certificate-identity-regexp "$identity" --certificate-oidc-issuer-regexp "$issuer")
    fi
    args+=("$ref")

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would verify ${att_type} attestation on ${ref} [$(attest.mode)]"
        return 0
    fi

    log.info "verifying ${att_type} attestation on ${ref} [$(attest.mode)]"
    if ! cosign "${args[@]}"; then
        log.error "attest.verify: attestation did not verify for ${ref} (fail-closed)"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi
    return 0
}

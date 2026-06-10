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
# The signing backend comes from the Signing endpoint the infrastructure
# referential declares (one per instance):
#   keyless - Fulcio short-lived cert from the platform OIDC token,
#             transparency via Rekor. P-open default.
#   key     - a referenced local key (env:// or file://), for runners
#             without OIDC or Sigstore infrastructure.
#   kms     - a key held by OpenBAO Transit (openbao:// / hashivault://),
#             never exported to the runner. P-entreprise default.
# The endpoint's transparency stance (rekor-public, rekor-private, none)
# governs the transparency-log flags on both sign and verify.
#
# Functions:
#   attest.mode                  - echo "keyless" | "key" | "kms"
#   attest.available             - rc 0 when cosign is on PATH
#   attest.provenance_predicate  - emit an in-toto SLSA provenance predicate
#   attest.sign <ref> --sbom F   - attach signed SBOM (+ provenance) to a digest
#   attest.verify <ref>          - verify the attestations, fail-closed

# Guard against double-sourcing
[[ -n "${_BRIK_MODULE_TRANSVERSE_ATTEST_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_ATTEST_LOADED=1

# _attest._signing - echo (as JSON) the Signing endpoint of the referential.
_attest._signing() {
    brik.use transverse.infra
    infra.endpoint_of_kind Signing
}

# Signing backend declared by the referential: keyless, key or kms.
attest.mode() {
    local sig
    sig="$(_attest._signing)" || return "$?"
    printf '%s' "$sig" | jq -rj '.backend'
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

# _attest._key_arg - translate a Signing key reference into the value cosign
# accepts as --key: env:// passes through (cosign resolves it natively),
# file:// becomes a path (relative paths resolve against the referential
# root). A bao:// reference is a configuration error: OpenBAO-held keys go
# through the kms backend so the key never leaves the secret manager.
_attest._key_arg() {
    local ref="$1"
    case "$ref" in
        env://*)
            printf '%s' "$ref"
            ;;
        file://*)
            local path="${ref#file://}"
            if [[ "$path" != /* ]]; then
                local root
                root="$(infra.root)" || return "$?"
                path="${root}/${path}"
            fi
            printf '%s' "$path"
            ;;
        bao://*)
            log.error "attest: a bao:// key reference is not a file key - use the kms backend (openbao://) instead"
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
        *)
            log.error "attest: unsupported key reference '${ref}' (expected env:// or file://)"
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac
}

# _attest._kms_env - export the connection environment the cosign KMS driver
# reads: BAO_ADDR/BAO_TOKEN for openbao://, VAULT_ADDR/VAULT_TOKEN for the
# hashivault:// alias, TRANSIT_SECRET_ENGINE_PATH for a non-default Transit
# mount. Values come from the SecretManager endpoint and its referenced
# credential; the signing key itself never leaves OpenBAO.
_attest._kms_env() {
    local sig="$1"
    local uri sm url token
    uri="$(printf '%s' "$sig" | jq -r '.kms_uri')"

    brik.use transverse.infra
    sm="$(infra.endpoint_of_kind SecretManager)" || return "$?"
    url="$(printf '%s' "$sm" | jq -r '.url')"
    token="$(infra.resolve_ref "$(printf '%s' "$sm" | jq -r '.auth.ref')")" || return "$?"

    case "$uri" in
        openbao://*)    export BAO_ADDR="$url" BAO_TOKEN="$token" ;;
        hashivault://*) export VAULT_ADDR="$url" VAULT_TOKEN="$token" ;;
        *)
            log.error "attest: unsupported KMS URI '${uri}' (expected openbao:// or hashivault://)"
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac

    local mount
    mount="$(printf '%s' "$sm" | jq -r '.transit_mount // ""')"
    [[ -n "$mount" ]] && export TRANSIT_SECRET_ENGINE_PATH="$mount"
    return 0
}

# _attest._backend_args - append the cosign flags the declared backend and
# transparency stance require. <op> is sign or verify (the transparency
# flags differ between the two).
# Usage: _attest._backend_args <array_name> <signing_json> <op>
_attest._backend_args() {
    local -n _bargv="$1"
    local _sig="$2" _op="$3"

    # Loaded here, in the CALLING shell: the helpers that resolved the
    # signing endpoint ran in command substitutions, whose brik.use loads
    # the infra module in a subshell only. The file:// and trusted_root
    # branches below resolve paths against infra.root in this shell.
    brik.use transverse.infra
    local _backend _transparency
    _backend="$(printf '%s' "$_sig" | jq -r '.backend')"
    _transparency="$(printf '%s' "$_sig" | jq -r '.transparency')"

    case "$_backend" in
        keyless) ;;
        key)
            # cosign only accepts a PUBLIC key on verify: a verifying
            # environment declares verification_key so the private key
            # never has to reach it. Absent, the single key reference
            # serves both operations (it must then point at a public key
            # wherever only verification happens).
            local _key_ref _key
            if [[ "$_op" == "verify" ]]; then
                _key_ref="$(printf '%s' "$_sig" | jq -r '.verification_key // .key')"
            else
                _key_ref="$(printf '%s' "$_sig" | jq -r '.key')"
            fi
            _key="$(_attest._key_arg "$_key_ref")" || return "$?"
            _bargv+=(--key "$_key")
            ;;
        kms)
            _bargv+=(--key "$(printf '%s' "$_sig" | jq -r '.kms_uri')")
            _attest._kms_env "$_sig" || return "$?"
            ;;
        *)
            log.error "attest: unknown signing backend '${_backend}' in the referential"
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac

    case "$_transparency" in
        none)
            if [[ "$_op" == "sign" ]]; then
                # --tlog-upload=false requires --use-signing-config=false on
                # cosign v3: the default signing config mandates a Rekor
                # service, contradicting the no-transparency stance.
                _bargv+=(--use-signing-config=false --tlog-upload=false)
            else
                _bargv+=(--insecure-ignore-tlog=true)
            fi
            ;;
        rekor-private)
            [[ "$_op" == "sign" ]] && _bargv+=(--rekor-url "$(printf '%s' "$_sig" | jq -r '.rekor_url')")
            ;;
    esac

    if [[ "$_op" == "verify" ]]; then
        local _troot
        _troot="$(printf '%s' "$_sig" | jq -r '.trusted_root // ""')"
        if [[ -n "$_troot" ]]; then
            local _iroot
            _iroot="$(infra.root)" || return "$?"
            [[ "$_troot" != /* ]] && _troot="${_iroot}/${_troot}"
            _bargv+=(--trusted-root "$_troot")
        fi
    fi
    return 0
}

# Append cosign registry-connection flags to the named argv array, derived
# from the Registry endpoint the referential declares for the ref's host:
# a declared http:// URL maps to --allow-http-registry, a declared
# tls.trust: insecure maps to --allow-insecure-registry, and an undeclared
# host fails closed. Basic auth comes from the canonical
# BRIK_REGISTRY_USER/PASSWORD when present (attaching a referrer is a
# registry write).
# Usage: _attest._registry_args <array_name> <ref>
_attest._registry_args() {
    local -n _argv="$1"
    local _ref="$2"
    local _host="${_ref%%/*}"

    brik.use transverse.infra
    local _endpoint _url
    _endpoint="$(infra.registry_for "$_host")" || return "$?"
    _url="$(printf '%s' "$_endpoint" | jq -r '.url')"
    if [[ "$_url" == http://* ]]; then
        _argv+=(--allow-http-registry)
    elif [[ "$(printf '%s' "$_endpoint" | jq -r '.tls.trust')" == "insecure" ]]; then
        _argv+=(--allow-insecure-registry)
    fi
    if [[ -n "${BRIK_REGISTRY_USER:-}" && -n "${BRIK_REGISTRY_PASSWORD:-}" ]]; then
        _argv+=(--registry-username "$BRIK_REGISTRY_USER" --registry-password "$BRIK_REGISTRY_PASSWORD")
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
# it signs with the key the referential's Signing endpoint references.
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

    local sig backend
    sig="$(_attest._signing)" || return "$?"
    backend="$(printf '%s' "$sig" | jq -r '.backend')"

    local -a key_args=()
    _attest._backend_args key_args "$sig" sign || return "$?"

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would attest (${sbom_type}$([[ -n "$provenance" ]] && printf ' + provenance')) on ${ref} [${backend}]"
        return 0
    fi

    if [[ ! -f "$sbom" ]]; then
        log.error "attest.sign: SBOM file not found: ${sbom}"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    _attest._registry_args key_args "$ref" || return "$?"

    log.info "attesting ${sbom_type} SBOM on ${ref} [${backend}]"
    if ! cosign attest "${key_args[@]}" --predicate "$sbom" --type "$sbom_type" -y "$ref"; then
        log.error "attest.sign: cosign failed to attach the SBOM attestation"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    if [[ -n "$provenance" ]]; then
        if [[ ! -f "$provenance" ]]; then
            log.error "attest.sign: provenance file not found: ${provenance}"
            return "$BRIK_EXIT_IO_FAILURE"
        fi
        log.info "attesting SLSA provenance on ${ref} [${backend}]"
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
# verification uses the Signing endpoint's verification_key (or key).
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

    local sig backend
    sig="$(_attest._signing)" || return "$?"
    backend="$(printf '%s' "$sig" | jq -r '.backend')"

    local -a args=(verify-attestation --type "$att_type")
    if [[ "$backend" == "keyless" ]]; then
        # Keyless: the signer identity and issuer are the residual root of
        # trust (who is allowed to sign). Without them the verification would
        # accept any Fulcio cert, so leaving them empty is itself a failure.
        if [[ -z "$identity" || -z "$issuer" ]]; then
            log.error "attest.verify: keyless verification requires --identity and --issuer"
            return "$BRIK_EXIT_INVALID_INPUT"
        fi
        args+=(--certificate-identity-regexp "$identity" --certificate-oidc-issuer-regexp "$issuer")
    fi
    _attest._backend_args args "$sig" verify || return "$?"

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would verify ${att_type} attestation on ${ref} [${backend}]"
        return 0
    fi

    _attest._registry_args args "$ref" || return "$?"
    args+=("$ref")

    log.info "verifying ${att_type} attestation on ${ref} [${backend}]"
    if ! cosign "${args[@]}"; then
        log.error "attest.verify: attestation did not verify for ${ref} (fail-closed)"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi
    return 0
}

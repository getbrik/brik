#!/usr/bin/env bash
# @module transverse.evidence
# @requires jq git
# @description BuildEvidence store: a file-per-digest record of what CI built.
#
# After CI signs the image (transverse.attest), it records a BuildEvidence
# document in the state-repo at evidence/<version>/sha256-<digest>.json. The
# image digest is the subject and is encoded in the path; the document carries
# the version, the source commit, the CI run id and the references to the SBOM
# and provenance attestations, plus the frozen Layer V refs (the version-pinned,
# environment-agnostic definition the artifact was built from).
#
# Integrity comes from the signed attestations on the digest plus the signed,
# append-only git commit -- never from a self-hash written back into the file.
#
# Functions:
#   evidence.relpath <version> <digest>  - the digest-addressed store path
#   evidence.build   --version ... --digest ...  - emit the JSON document
#   evidence.publish --repo ... --version ... --digest ...  - commit it (stdin)

# Guard against double-sourcing
[[ -n "${_BRIK_MODULE_TRANSVERSE_EVIDENCE_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_EVIDENCE_LOADED=1

# Store path for a (version, digest) pair. The digest sha256:HEX becomes the
# OCI referrer tag form sha256-HEX so the path is a valid filename.
# Usage: evidence.relpath <version> <digest>
evidence.relpath() {
    local version="$1" digest="$2"
    printf 'evidence/%s/%s.json' "$version" "${digest/:/-}"
}

# Build the BuildEvidence JSON document on stdout.
# Usage: evidence.build --version V --digest D --commit C --run-id ID
#        [--platform P] [--sbom-ref R] [--provenance-ref R]
#        [--version-ref VR] [--env-config-ref ER]
evidence.build() {
    local version="" digest="" commit="" run_id="" platform=""
    local sbom_ref="" provenance_ref="" version_ref="" env_config_ref=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)        version="$2";        shift 2 ;;
            --digest)         digest="$2";         shift 2 ;;
            --commit)         commit="$2";         shift 2 ;;
            --run-id)         run_id="$2";         shift 2 ;;
            --platform)       platform="$2";       shift 2 ;;
            --sbom-ref)       sbom_ref="$2";       shift 2 ;;
            --provenance-ref) provenance_ref="$2"; shift 2 ;;
            --version-ref)    version_ref="$2";    shift 2 ;;
            --env-config-ref) env_config_ref="$2"; shift 2 ;;
            *) log.error "evidence.build: unknown option: $1"
               return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$version" || -z "$digest" ]]; then
        log.error "evidence.build: --version and --digest are required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    # KCOV_EXCL_START -- inline jq document body, not bash code
    jq -n \
        --arg version "$version" \
        --arg digest "$digest" \
        --arg commit "$commit" \
        --arg run_id "$run_id" \
        --arg platform "$platform" \
        --arg sbom "$sbom_ref" \
        --arg provenance "$provenance_ref" \
        --arg version_ref "$version_ref" \
        --arg env_config_ref "$env_config_ref" \
        '{
          schema: "brik.evidence/v1",
          version: $version,
          digest: $digest,
          commit: $commit,
          ci_run_id: $run_id,
          platform: $platform,
          artifact: { sbom: $sbom, provenance: $provenance },
          layer_v: { version_ref: $version_ref, env_config_ref: $env_config_ref }
        }'
    # KCOV_EXCL_STOP
}

# Commit a BuildEvidence document (read from stdin) to the state-repo at the
# digest-addressed path. The append is append-only (state_repo refuses an
# overwrite), the commit is optionally signed and the working clone is removed.
# Usage: <doc> | evidence.publish --repo <url> --version V --digest D
#        [--branch B] [--token-var VAR] [--sign] [--dry-run]
evidence.publish() {
    local repo="" version="" digest="" branch="" token_var=""
    local sign="" dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)      repo="$2";      shift 2 ;;
            --version)   version="$2";   shift 2 ;;
            --digest)    digest="$2";    shift 2 ;;
            --branch)    branch="$2";    shift 2 ;;
            --token-var) token_var="$2"; shift 2 ;;
            --sign)      sign="true";    shift ;;
            --dry-run)   dry_run="true"; shift ;;
            *) log.error "evidence.publish: unknown option: $1"
               return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$repo" || -z "$version" || -z "$digest" ]]; then
        log.error "evidence.publish: --repo, --version and --digest are required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local relpath
    relpath="$(evidence.relpath "$version" "$digest")"

    if [[ "$dry_run" == "true" ]]; then
        cat >/dev/null   # consume the document so the producer does not block
        log.info "[dry-run] would publish evidence at ${relpath}"
        return 0
    fi

    local doc
    doc="$(cat)"

    brik.use transverse.state_repo

    local dest
    dest="$(mktemp -d)" || { log.error "evidence.publish: mktemp failed"; return "$BRIK_EXIT_IO_FAILURE"; }

    local -a clone_args=("$repo" "$dest")
    [[ -n "$branch" ]]    && clone_args+=(--branch "$branch")
    [[ -n "$token_var" ]] && clone_args+=(--token-var "$token_var")

    local rc=0
    if ! transverse.state_repo.clone "${clone_args[@]}"; then
        rm -rf "$dest"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    # Idempotent re-entry: a reproducible build re-runs CI on the same commit
    # and produces the SAME digest, so the digest-addressed record already
    # exists -- the store already vouches for the artifact, converge as a
    # no-op (only ci_run_id would differ). The same digest claimed by a
    # DIFFERENT commit is a conflict surfaced fail-closed, never silently
    # kept: append-only means history is never rewritten, not that a re-run
    # fails.
    if [[ -e "${dest}/${relpath}" ]]; then
        local new_commit old_commit
        new_commit="$(printf '%s' "$doc" | jq -r '.commit // ""' 2>/dev/null)"
        old_commit="$(jq -r '.commit // ""' "${dest}/${relpath}" 2>/dev/null)"
        rm -rf "$dest"
        if [[ -n "$new_commit" && "$new_commit" == "$old_commit" ]]; then
            log.info "evidence already recorded for ${digest} (${version}, commit ${new_commit}) -- converged"
            return 0
        fi
        log.error "evidence conflict: ${relpath} already records commit '${old_commit}' but this run builds from '${new_commit}'"
        return "$BRIK_EXIT_CHECK_FAILED"
    fi

    if ! printf '%s' "$doc" | transverse.state_repo.append "$dest" "$relpath"; then
        rm -rf "$dest"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    local -a commit_args=("$dest" "evidence: ${version} ${digest}")
    [[ "$sign" == "true" ]] && commit_args+=(--sign)
    if ! transverse.state_repo.commit "${commit_args[@]}"; then
        rm -rf "$dest"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    transverse.state_repo.push "$dest" || rc="$BRIK_EXIT_EXTERNAL_FAIL"

    rm -rf "$dest"
    return "$rc"
}

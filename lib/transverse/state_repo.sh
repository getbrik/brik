#!/usr/bin/env bash
# @module transverse.state_repo
# @requires git
# @description Append-only, token-aware git accessor for brik state stores.
#
# A "state-repo" is a git repository -- distinct from the application source
# repo -- that holds deployment intent and signed evidence as append-only,
# file-per-event commits (evidence/, promotions/, deployments/, plus GitOps
# manifests). It is the single git primitive shared by the evidence store, the
# promotion journal and the deployment journal; deployments/gitops.sh is its
# first consumer.
#
# Integrity: commits may be ssh-signed (--sign, the evidence-commit-signing
# provider) with the key the referential's 'evidence-signing' credential
# references, and verified against the referential's trust/allowed_signers;
# the host enforces write-ACL / branch-protection. This module never writes a
# self-hash back into the file it describes; tamper-evidence comes from the
# signature plus the append-only git commit chain, not from an embedded digest.
#
# Functions:
#   transverse.state_repo.clone  - inject an indirect token, clone a branch shallow
#   transverse.state_repo.append - write an append-only event file (refuses overwrite)
#   transverse.state_repo.commit - stage all and commit (idempotent, optional ssh --sign)
#   transverse.state_repo.verify_head - verify HEAD's ssh signature (fail-closed)
#   transverse.state_repo.push   - push HEAD, credentials redacted from errors

# Guard against double-sourcing
[[ -n "${_BRIK_MODULE_TRANSVERSE_STATE_REPO_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_STATE_REPO_LOADED=1

# Internal helper: inject a git token into a repo URL via variable indirection.
# Usage: _transverse.state_repo._inject_token <repo_url> <token_var_name>
# stdout: URL with token injected, or original URL when no token var is given.
_transverse.state_repo._inject_token() {
    local repo="$1" token_var="$2"
    if [[ -z "$token_var" ]]; then
        printf '%s' "$repo"
        return 0
    fi
    brik.use transverse.env
    local token
    token="$(transverse.env.resolve_indirect "$token_var")"
    if [[ -z "$token" ]]; then
        log.error "token variable is empty: ${token_var}"
        return "$BRIK_EXIT_INVALID_ENV"
    fi
    # Prefix the host with the token so git authenticates (the token becomes
    # the URL userinfo). Plain-http is injected too: whether an endpoint may
    # be cleartext is the referential's TLS posture, not this helper's call.
    printf '%s' "$repo" | sed -E "s|^(https?://)|\\1${token}@|"
}

# Internal helper: mask credentials in a URL for safe logging.
# Usage: _transverse.state_repo._safe_url <url>
_transverse.state_repo._safe_url() {
    printf '%s' "$1" | sed 's|://[^@]*@|://***@|'
}

# Internal helper: echo the CA bundle for a repo URL when the referential's
# GitHost declares the URL's hostname with tls.trust: custom-ca. Any other
# posture (no referential, no GitHost, another host, system/insecure trust)
# echoes nothing; a declared custom-ca with a missing bundle fails closed
# (infra.tls_ca). TLS trust is per-hostname, so the port is ignored.
# Usage: ca="$(_transverse.state_repo._ca_for_url <repo_url>)" || return $?
_transverse.state_repo._ca_for_url() {
    local url="$1" host ghost ghost_url ghost_host
    host="${url#*://}"; host="${host%%/*}"; host="${host##*@}"; host="${host%%:*}"
    [[ -n "$host" ]] || return 0

    brik.use transverse.infra
    ghost="$(infra.endpoint_of_kind GitHost 2>/dev/null)" || return 0
    ghost_url="$(printf '%s' "$ghost" | jq -r '.git_url // .api_url // ""')"
    ghost_host="${ghost_url#*://}"; ghost_host="${ghost_host%%/*}"; ghost_host="${ghost_host%%:*}"
    [[ "$host" == "$ghost_host" ]] || return 0

    infra.tls_ca "$ghost"
}

# Clone a state-repo branch (shallow), injecting an indirect token when given.
# Credentials are masked in all log output.
# Usage: transverse.state_repo.clone <repo_url> <dest>
#        [--branch <b>] [--token-var <VAR>] [--depth <n>] [--dry-run]
transverse.state_repo.clone() {
    local repo="${1:-}" dest="${2:-}"
    [[ $# -ge 1 ]] && shift
    [[ $# -ge 1 ]] && shift
    local branch="" token_var="" depth="1" dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --branch)    branch="$2";    shift 2 ;;
            --token-var) token_var="$2"; shift 2 ;;
            --depth)     depth="$2";     shift 2 ;;
            --dry-run)   dry_run="true"; shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$repo" ]]; then
        log.error "repo is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -z "$dest" ]]; then
        log.error "dest is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    pipeline.require_tool git || return "$BRIK_EXIT_MISSING_DEP"

    local clone_url
    clone_url="$(_transverse.state_repo._inject_token "$repo" "$token_var")" || return $?

    local safe_url
    safe_url="$(_transverse.state_repo._safe_url "$clone_url")"

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would clone state-repo ${safe_url}${branch:+ (branch: ${branch})}"
        return 0
    fi

    log.info "cloning state-repo: ${safe_url}${branch:+ (branch: ${branch})}"
    brik.use transverse.git
    local ca
    ca="$(_transverse.state_repo._ca_for_url "$repo")" || return "$?"
    local -a args=("$clone_url" "$dest" --depth "$depth")
    [[ -n "$branch" ]] && args+=(--branch "$branch")
    if [[ -n "$ca" ]]; then
        GIT_SSL_CAINFO="$ca" transverse.git.clone_shallow "${args[@]}" \
            || return "$BRIK_EXIT_EXTERNAL_FAIL"
    elif ! transverse.git.clone_shallow "${args[@]}"; then
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi
    return 0
}

# Write an append-only event file under the state-repo working tree.
# Content is read from stdin. Parent directories are created. The file must NOT
# already exist (file-per-event invariant: events are immutable). Absolute and
# path-traversal targets are rejected so events stay under the repo root.
# Usage: <producer> | transverse.state_repo.append <repo_dir> <relpath>
transverse.state_repo.append() {
    local repo_dir="$1" relpath="$2"

    if [[ -z "$repo_dir" ]]; then
        log.error "repo_dir is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -z "$relpath" ]]; then
        log.error "relpath is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ ! -d "$repo_dir" ]]; then
        log.error "state-repo dir not found: $repo_dir"
        return "$BRIK_EXIT_IO_FAILURE"
    fi
    if [[ "$relpath" == /* || "$relpath" == *..* ]]; then
        log.error "invalid event path (absolute or traversal): $relpath"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local dest="${repo_dir}/${relpath}"
    if [[ -e "$dest" ]]; then
        log.error "append-only violation: event already exists: $relpath"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    mkdir -p "$(dirname "$dest")" || {
        log.error "cannot create event directory for: $relpath"
        return "$BRIK_EXIT_IO_FAILURE"
    }
    cat > "$dest" || {
        log.error "cannot write event file: $relpath"
        return "$BRIK_EXIT_IO_FAILURE"
    }
    return 0
}

# _transverse.state_repo._signing_key - resolve the private key of the
# referential's 'evidence-signing' credential (method ssh-key) into a path
# usable as git user.signingKey. file:// references resolve in place
# (relative to the referential root); other references (env://, later bao://)
# are materialized into a 0600 transient file the caller removes after the
# commit. Writes the path into <path_var> and the transient file (when one
# was created) into <tmp_var> -- namerefs, so no subshell loses the state.
# Usage: _transverse.state_repo._signing_key <path_var> <tmp_var>
_transverse.state_repo._signing_key() {
    local -n _key_path="$1" _key_tmp="$2"

    brik.use transverse.infra

    local cred method
    if ! cred="$(infra.credential evidence-signing 2>/dev/null)"; then
        log.error "commit signing requires an 'evidence-signing' credential (method: ssh-key) in the referential"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    method="$(printf '%s' "$cred" | jq -r '.method')"
    if [[ "$method" != "ssh-key" ]]; then
        log.error "credential 'evidence-signing' has method '${method}' (expected ssh-key)"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    local ref
    ref="$(printf '%s' "$cred" | jq -r '.private_key')"
    case "$ref" in
        file://*)
            local path="${ref#file://}"
            if [[ "$path" != /* ]]; then
                local root
                root="$(infra.root)" || return "$?"
                path="${root}/${path}"
            fi
            if [[ ! -r "$path" ]]; then
                log.error "evidence-signing key not readable: ${path}"
                return "$BRIK_EXIT_IO_FAILURE"
            fi
            _key_path="$path"
            ;;
        *)
            local value tmp
            value="$(infra.resolve_ref "$ref")" || return "$?"
            tmp="$(mktemp)" || return "$BRIK_EXIT_IO_FAILURE"
            chmod 600 "$tmp"
            printf '%s\n' "$value" > "$tmp"
            _key_path="$tmp"
            _key_tmp="$tmp"
            ;;
    esac
    return 0
}

# Stage all changes and commit. Idempotent: a clean tree returns 0 with a log
# message unless --fail-if-empty is set. --sign produces an ssh-signed commit
# (gpg.format=ssh) with the key the referential's 'evidence-signing'
# credential references; no referential or no usable key fails closed.
# The default committer identity is the brik-ci robot.
# The clean-tree case is detected via `git status --porcelain` so real commit
# failures surface cleanly rather than being guessed from exit codes.
# Usage: transverse.state_repo.commit <repo_dir> <message>
#        [--email <e>] [--name <n>] [--sign] [--fail-if-empty]
transverse.state_repo.commit() {
    local repo_dir="${1:-}" message="${2:-}"
    [[ $# -ge 1 ]] && shift
    [[ $# -ge 1 ]] && shift
    local email="brik-ci@noreply" name="Brik CI" sign=false fail_if_empty=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --email) email="$2"; shift 2 ;;
            --name)  name="$2";  shift 2 ;;
            --sign)  sign=true;  shift ;;
            --fail-if-empty) fail_if_empty=true; shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$repo_dir" ]]; then
        log.error "repo_dir is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -z "$message" ]]; then
        log.error "message is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local git_base=(git -C "$repo_dir")

    "${git_base[@]}" add -A >/dev/null 2>&1 || {
        log.error "git add failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    if [[ -z "$("${git_base[@]}" status --porcelain 2>/dev/null)" ]]; then
        if [[ "$fail_if_empty" == "true" ]]; then
            log.error "git commit failed: working tree has no changes"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        fi
        log.info "no changes to commit"
        return 0
    fi

    local commit_cmd=("${git_base[@]}" -c "user.email=${email}" -c "user.name=${name}")
    local key_path="" key_tmp=""
    if [[ "$sign" == "true" ]]; then
        _transverse.state_repo._signing_key key_path key_tmp || return "$?"
        commit_cmd+=(-c gpg.format=ssh -c "user.signingKey=${key_path}")
    fi
    commit_cmd+=(commit -q)
    [[ "$sign" == "true" ]] && commit_cmd+=(-S)
    commit_cmd+=(-m "$message")

    local commit_err rc=0
    commit_err="$("${commit_cmd[@]}" 2>&1 >/dev/null)" || rc=$?
    [[ -n "$key_tmp" ]] && rm -f "$key_tmp"
    if [[ "$rc" -ne 0 ]]; then
        log.error "git commit failed: ${commit_err}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi
    return 0
}

# Verify the ssh signature on a state-repo HEAD against the referential's
# trust/allowed_signers. Principals are verified in the 'git' namespace (the
# namespace git uses for commits and tags). Fail-closed: an unsigned HEAD, a
# signer absent from allowed_signers or a missing trust file all refuse.
# Usage: transverse.state_repo.verify_head <repo_dir>
transverse.state_repo.verify_head() {
    local repo_dir="${1:-}"
    if [[ -z "$repo_dir" ]]; then
        log.error "repo_dir is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    brik.use transverse.infra

    local root allowed
    root="$(infra.root)" || return "$?"
    allowed="${root}/trust/allowed_signers"
    if [[ ! -f "$allowed" ]]; then
        log.error "no trust/allowed_signers in the referential: cannot verify evidence commits"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    if ! git -C "$repo_dir" -c gpg.ssh.allowedSignersFile="$allowed" verify-commit HEAD; then
        log.error "evidence commit signature did not verify for HEAD (fail-closed)"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi
    return 0
}

# _transverse.state_repo._repo_path - strip scheme, userinfo, host and the
# .git suffix from an http(s) repo URL, leaving the host-side project path
# (owner/repo, possibly nested on GitLab).
_transverse.state_repo._repo_path() {
    local url="$1" path
    path="${url#*://}"
    path="${path#*@}"
    case "$path" in
        */*) path="${path#*/}" ;;
        *)
            log.error "state-repo URL carries no project path: ${url}"
            return "$BRIK_EXIT_INVALID_INPUT"
            ;;
    esac
    printf '%s' "${path%.git}"
}

# Ask the GitHost API whether <branch> of the state repo is protected. The
# append-only guarantee of the evidence store rests on host-side write-ACL /
# branch-protection, so CD init checks it. Gitea/GitLab rules are matched by
# exact name (glob rules are not evaluated); GitHub answers on the protection
# endpoint itself. Until the referential's Policy kind sets the gate
# semantics per profile, callers treat "unprotected" as a loud warning.
# Usage: transverse.state_repo.check_protection <repo_url> <branch>
#        --environment <env>
# Returns: 0 protected; 10 unprotected; 7 referential gaps (no GitHost, no
#          bound credential); 5 API failure; 2 invalid input.
transverse.state_repo.check_protection() {
    local repo_url="${1:-}" branch="${2:-}"
    [[ $# -ge 1 ]] && shift
    [[ $# -ge 1 ]] && shift
    local environment=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --environment) environment="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$repo_url" || -z "$branch" || -z "$environment" ]]; then
        log.error "check_protection: <repo_url>, <branch> and --environment are required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    brik.use transverse.infra

    local githost product api_url gh_name
    githost="$(infra.endpoint_of_kind GitHost)" || return "$?"
    product="$(printf '%s' "$githost" | jq -r '.product')"
    api_url="$(printf '%s' "$githost" | jq -r '.api_url')"
    gh_name="$(printf '%s' "$githost" | jq -r '.name')"

    local cred token
    cred="$(infra.credential_for "$environment" "$gh_name")" || return "$?"
    if [[ "$(printf '%s' "$cred" | jq -r '.method')" != "token" ]]; then
        log.error "check_protection: the '${gh_name}' credential must be a token to call the host API"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    token="$(infra.resolve_ref "$(printf '%s' "$cred" | jq -r '.token')")" || return "$?"

    local path
    path="$(_transverse.state_repo._repo_path "$repo_url")" || return "$?"

    local -a curl_args=(-sS --max-time 30)
    [[ "$(printf '%s' "$githost" | jq -r '.tls.trust // ""')" == "insecure" ]] && curl_args+=(-k)
    local gh_ca
    gh_ca="$(infra.tls_ca "$githost")" || return "$?"
    [[ -n "$gh_ca" ]] && curl_args+=(--cacert "$gh_ca")

    local body code matched
    body="$(mktemp)" || return "$BRIK_EXIT_IO_FAILURE"

    case "$product" in
        gitea)
            code="$(curl "${curl_args[@]}" -o "$body" -w '%{http_code}' \
                -H "Authorization: token ${token}" \
                "${api_url}/api/v1/repos/${path}/branch_protections")" || { rm -f "$body"; return "$BRIK_EXIT_EXTERNAL_FAIL"; }
            if [[ "$code" != "200" ]]; then
                log.error "check_protection: ${product} API answered ${code} for ${path}"
                rm -f "$body"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            fi
            matched="$(jq -e --arg b "$branch" 'any(.[]; (.branch_name // .rule_name // "") == $b)' "$body" 2>/dev/null)" || matched="false"
            ;;
        gitlab)
            local path_enc
            path_enc="$(jq -rn --arg p "$path" '$p|@uri')"
            code="$(curl "${curl_args[@]}" -o "$body" -w '%{http_code}' \
                -H "PRIVATE-TOKEN: ${token}" \
                "${api_url}/api/v4/projects/${path_enc}/protected_branches")" || { rm -f "$body"; return "$BRIK_EXIT_EXTERNAL_FAIL"; }
            if [[ "$code" != "200" ]]; then
                log.error "check_protection: ${product} API answered ${code} for ${path}"
                rm -f "$body"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            fi
            matched="$(jq -e --arg b "$branch" 'any(.[]; .name == $b)' "$body" 2>/dev/null)" || matched="false"
            ;;
        github)
            code="$(curl "${curl_args[@]}" -o "$body" -w '%{http_code}' \
                -H "Authorization: Bearer ${token}" \
                "${api_url}/repos/${path}/branches/${branch}/protection")" || { rm -f "$body"; return "$BRIK_EXIT_EXTERNAL_FAIL"; }
            case "$code" in
                200) matched="true" ;;
                404) matched="false" ;;
                *)
                    log.error "check_protection: ${product} API answered ${code} for ${path}"
                    rm -f "$body"
                    return "$BRIK_EXIT_EXTERNAL_FAIL"
                    ;;
            esac
            ;;
        *)
            log.error "check_protection: unsupported git host product '${product}'"
            rm -f "$body"
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac
    rm -f "$body"

    if [[ "$matched" == "true" ]]; then
        log.info "state-repo branch '${branch}' is protected on ${gh_name} (${product})"
        return 0
    fi
    log.warn "state-repo branch '${branch}' is NOT protected on ${gh_name} (${product}): the append-only guarantee relies on it"
    return "$BRIK_EXIT_CHECK_FAILED"
}

# Push the current HEAD of a state-repo working tree to its upstream.
# Always sets GIT_TERMINAL_PROMPT=0; credentials embedded in the remote URL are
# redacted from error logs.
# Usage: transverse.state_repo.push <repo_dir> [--dry-run]
transverse.state_repo.push() {
    local repo_dir="${1:-}"
    [[ $# -ge 1 ]] && shift
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run="true"; shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$repo_dir" ]]; then
        log.error "repo_dir is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] would push state-repo"
        return 0
    fi

    # The remote may live behind the referential's custom CA: resolve the
    # bundle from the origin URL the clone recorded.
    local remote_url ca
    remote_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || printf '')"
    ca="$(_transverse.state_repo._ca_for_url "$remote_url")" || return "$?"

    local push_err rc=0
    if [[ -n "$ca" ]]; then
        push_err="$(GIT_TERMINAL_PROMPT=0 GIT_SSL_CAINFO="$ca" git -C "$repo_dir" push 2>&1)" || rc=$?
    else
        push_err="$(GIT_TERMINAL_PROMPT=0 git -C "$repo_dir" push 2>&1)" || rc=$?
    fi
    if [[ "$rc" -ne 0 ]]; then
        local safe_err
        safe_err="$(printf '%s' "$push_err" | sed 's|://[^@]*@|://***@|')"
        log.error "git push failed: $safe_err"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi
    return 0
}

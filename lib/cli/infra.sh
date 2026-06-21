#!/usr/bin/env bash
# @module cli.infra
# @description CLI entrypoint for "brik infra". Scaffolds an infrastructure
#   referential instance (init) and validates one (validate). The scaffolds
#   are the reference instances of the referential spec: each profile must
#   pass `brik infra validate` unchanged.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_INFRA_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_INFRA_LOADED=1

# cli.infra.run - dispatch the infra subcommands.
# Usage: cli.infra.run <init|validate> [options]
cli.infra.run() {
    brik.use cli.helpers

    local sub="${1:-}"
    case "$sub" in
        -h|--help)
            brik_print_verb_help infra
            return 0
            ;;
        init)
            shift
            _cli.infra._init "$@"
            ;;
        validate)
            shift
            _cli.infra._validate "$@"
            ;;
        secrets)
            shift
            _cli.infra._secrets "$@"
            ;;
        "")
            brik_usage_error "infra requires a subcommand: init, validate or secrets"
            ;;
        *)
            brik_usage_error "unknown infra subcommand: ${sub} (expected init, validate or secrets)"
            ;;
    esac
}

# _cli.infra._init - scaffold a referential instance for a profile.
# Usage: brik infra init [--profile p-open|p-entreprise|p-lab|local] [--dir <d>]
# Default --dir is a dedicated subdir (.brik/infra) so the instance never
# pollutes the project root.
_cli.infra._init() {
    local profile="p-open"
    local target_dir=".brik/infra"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile)
                brik_require_arg "--profile" "${2-}" || return "$?"
                profile="$2"
                shift 2
                ;;
            --dir)
                brik_require_arg "--dir" "${2-}" || return "$?"
                target_dir="$2"
                shift 2
                ;;
            -h|--help)
                brik_print_verb_help "infra init"
                return 0
                ;;
            *)
                brik_usage_error "unknown option: $1" || return "$?"
                ;;
        esac
    done

    case "$profile" in
        p-open|p-entreprise|p-lab|p-local) ;;
        *)
            brik_usage_error "unknown profile: ${profile} (expected p-open, p-entreprise, p-lab or p-local)" || return "$?"
            ;;
    esac

    if ! mkdir -p "$target_dir"; then
        brik_error "cannot create referential directory: ${target_dir}"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -f "${target_dir}/referential.yml" ]]; then
        brik_error "a referential instance already exists in ${target_dir}"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    mkdir -p "${target_dir}/endpoints" "${target_dir}/credentials" \
             "${target_dir}/bindings" "${target_dir}/trust" "${target_dir}/schemas"

    cp "${BRIK_HOME}/schemas/referential/v1/"*.schema.json "${target_dir}/schemas/"

    "_cli.infra._scaffold_${profile//-/_}" "$target_dir"

    brik_print "Created a ${profile} referential instance in ${target_dir}"
    brik_print "Review the endpoints, then point BRIK_INFRA_DIR (or BRIK_INFRA_REPO) at it"
    return "$BRIK_EXIT_OK"
}

# _cli.infra._validate - validate a referential instance.
# Usage: brik infra validate [--dir <d>]  (falls back to BRIK_INFRA_DIR/_REPO)
_cli.infra._validate() {
    local dir=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dir)
                brik_require_arg "--dir" "${2-}" || return "$?"
                dir="$2"
                shift 2
                ;;
            -h|--help)
                brik_print_verb_help "infra validate"
                return 0
                ;;
            *)
                brik_usage_error "unknown option: $1" || return "$?"
                ;;
        esac
    done

    brik.use transverse.infra

    [[ -n "$dir" ]] && export BRIK_INFRA_DIR="$dir"

    local root rc=0
    root="$(infra.root)" || return "$?"
    infra.validate "$root" || rc="$?"
    if [[ "$rc" -ne 0 ]]; then
        log.error "${root} is invalid"
        return "$rc"
    fi

    printf '%s\n' "${root} is valid"
    return "$BRIK_EXIT_OK"
}

# _cli.infra._secrets - list the environment variables an operator must
# provision for this referential, derived BY TARGET (the operated endpoints'
# credentials), not by --environment (PD3): at CI time no deploy environment is
# selected. Default lists them grouped (pipeline-side vs infra-side bootstrap);
# --json emits the machine-readable object; --check verifies each is set and
# fails closed (4) on the first missing one (a preflight gate).
# Usage: brik infra secrets [--dir <d>] [--json|--check]
_cli.infra._secrets() {
    local dir="" mode="list"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dir)
                brik_require_arg "--dir" "${2-}" || return "$?"
                dir="$2"
                shift 2
                ;;
            --json)  mode="json";  shift ;;
            --check) mode="check"; shift ;;
            -h|--help)
                brik_print_verb_help "infra secrets"
                return 0
                ;;
            *)
                brik_usage_error "unknown option: $1" || return "$?"
                ;;
        esac
    done

    brik.use transverse.infra

    [[ -n "$dir" ]] && export BRIK_INFRA_DIR="$dir"

    local data
    data="$(infra.secret_vars)" || return "$?"

    case "$mode" in
        json)
            printf '%s\n' "$data"
            ;;
        check)
            local missing="" var
            while IFS= read -r var; do
                [[ -z "$var" ]] && continue
                [[ -n "${!var:-}" ]] || missing="${missing}${var} "
            done < <(printf '%s' "$data" | jq -r '.pipeline[], .infra[]')
            if [[ -n "$missing" ]]; then
                brik_error "missing required secret variable(s): ${missing% }"
                return "$BRIK_EXIT_INVALID_ENV"
            fi
            brik_print "all required secret variables are set"
            ;;
        *)
            local var
            brik_print "Pipeline-side secrets (operated endpoint credentials):"
            while IFS= read -r var; do
                [[ -n "$var" ]] && brik_print "  - ${var}"
            done < <(printf '%s' "$data" | jq -r '.pipeline[]')
            [[ "$(printf '%s' "$data" | jq -r '.pipeline | length')" == "0" ]] \
                && brik_print "  (none)"
            brik_print "Infra-side secrets (bootstrap):"
            while IFS= read -r var; do
                [[ -n "$var" ]] && brik_print "  - ${var}"
            done < <(printf '%s' "$data" | jq -r '.infra[]')
            [[ "$(printf '%s' "$data" | jq -r '.infra | length')" == "0" ]] \
                && brik_print "  (none)"
            ;;
    esac
    return "$BRIK_EXIT_OK"
}

# ---------------------------------------------------------------------------
# Profile scaffolds. Placeholder hosts use .example / .lab names; secret
# material is referenced (env://, bao://, file://), never inlined.
# ---------------------------------------------------------------------------

# p-local: the containerized-local posture. No endpoints, no credentials, no
# signing - a plain CI run (build/lint/test) needs nothing. This is the
# materializable twin of the built-in default Brik falls back to on a bare
# host; extend it (add a Registry, a Signing key backend...) to opt into
# package/promote/deploy/signing locally.
_cli.infra._scaffold_p_local() {
    local dir="$1"

    cat > "${dir}/referential.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Referential
profile: p-local
description: Containerized local execution - no endpoints, no credentials, no signing. Add endpoints/credentials/bindings to opt into package, promote, deploy or signing.
YAML
}

_cli.infra._scaffold_p_open() {
    local dir="$1"

    cat > "${dir}/referential.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Referential
profile: p-open
description: Public open-source posture - public registry, keyless signing, public transparency log.
YAML

    cat > "${dir}/endpoints/registry-candidate.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Registry
name: registry-candidate
url: https://ghcr.io
tls:
  trust: system
zone: candidate
YAML

    cat > "${dir}/endpoints/registry-release.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Registry
name: registry-release
url: https://ghcr.io
tls:
  trust: system
zone: release
YAML

    cat > "${dir}/endpoints/git-host.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: GitHost
name: git-host
product: github
api_url: https://api.github.com
git_url: https://github.com
tls:
  trust: system
YAML

    cat > "${dir}/endpoints/signing.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Signing
name: signing
backend: keyless
transparency: rekor-public
YAML

    cat > "${dir}/credentials/registry-push.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: registry-push
method: token
token: env://BRIK_REGISTRY_TOKEN
YAML

    cat > "${dir}/credentials/git-api.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: git-api
method: token
token: env://BRIK_GIT_TOKEN
YAML

    cat > "${dir}/credentials/evidence-signing.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: evidence-signing
method: ssh-key
private_key: env://BRIK_EVIDENCE_SIGNING_KEY
YAML

    cat > "${dir}/bindings/default.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Binding
name: default
endpoints:
  registry-candidate: registry-push
  registry-release: registry-push
  git-host: git-api
capabilities:
  artifact-attestation: cosign-keyless
  evidence-commit-signing: ssh-signing
YAML
}

_cli.infra._scaffold_p_entreprise() {
    local dir="$1"

    cat > "${dir}/referential.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Referential
profile: p-entreprise
description: Self-hosted enterprise posture - internal registry behind a corporate CA, OpenBAO-held key material, no public transparency log.
YAML

    cat > "${dir}/endpoints/registry-candidate.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Registry
name: registry-candidate
url: https://harbor.internal.example
tls:
  trust: custom-ca
referrers: true
zone: candidate
YAML

    cat > "${dir}/endpoints/registry-release.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Registry
name: registry-release
url: https://harbor.internal.example
tls:
  trust: custom-ca
referrers: true
zone: release
YAML

    cat > "${dir}/endpoints/git-host.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: GitHost
name: git-host
product: gitlab
api_url: https://gitlab.internal.example
git_url: https://gitlab.internal.example
tls:
  trust: custom-ca
YAML

    cat > "${dir}/endpoints/secret-manager.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: SecretManager
name: secret-manager
url: https://bao.internal.example:8200
auth:
  method: token
  ref: env://BAO_TOKEN
tls:
  trust: custom-ca
YAML

    cat > "${dir}/endpoints/signing.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Signing
name: signing
backend: kms
kms_uri: openbao://brik-signing
transparency: none
YAML

    cat > "${dir}/credentials/registry-push.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: registry-push
method: basic
username: ci-push
password: bao://secret/ci/registry#password
YAML

    cat > "${dir}/credentials/git-api.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: git-api
method: token
token: bao://secret/ci/git#token
YAML

    cat > "${dir}/credentials/evidence-signing.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: evidence-signing
method: ssh-key
private_key: bao://secret/ci/evidence#ssh_key
YAML

    cat > "${dir}/bindings/production.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Binding
name: production
endpoints:
  registry-candidate: registry-push
  registry-release: registry-push
  git-host: git-api
capabilities:
  artifact-attestation: cosign-kms-openbao
  evidence-commit-signing: ssh-signing
YAML
}

_cli.infra._scaffold_p_lab() {
    local dir="$1"

    cat > "${dir}/referential.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Referential
profile: p-lab
description: Test-lab posture - plain-HTTP services and a declared passphrase-less file key. Legal but noisy; never a production reference.
YAML

    cat > "${dir}/endpoints/registry-candidate.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Registry
name: registry-candidate
url: http://nexus.lab:8082
tls:
  trust: insecure
zone: candidate
YAML

    cat > "${dir}/endpoints/registry-release.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Registry
name: registry-release
url: http://nexus.lab:8083
tls:
  trust: insecure
zone: release
YAML

    cat > "${dir}/endpoints/git-host.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: GitHost
name: git-host
product: gitea
api_url: http://gitea.lab:3000
git_url: http://gitea.lab:3000
tls:
  trust: insecure
YAML

    cat > "${dir}/endpoints/signing.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Signing
name: signing
backend: key
key: file://trust/cosign.key
verification_key: file://trust/cosign.pub
transparency: none
YAML

    cat > "${dir}/credentials/registry-push.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: registry-push
method: basic
username: env://BRIK_REGISTRY_USER
password: env://BRIK_REGISTRY_PASSWORD
YAML

    cat > "${dir}/credentials/git-api.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: git-api
method: token
token: env://BRIK_GIT_TOKEN
YAML

    cat > "${dir}/credentials/evidence-signing.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: evidence-signing
method: ssh-key
private_key: file://trust/evidence_signing_key
YAML

    cat > "${dir}/bindings/e2e.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Binding
name: e2e
endpoints:
  registry-candidate: registry-push
  registry-release: registry-push
  git-host: git-api
capabilities:
  artifact-attestation: cosign-key
  evidence-commit-signing: ssh-signing
YAML
}

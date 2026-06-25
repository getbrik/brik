#!/usr/bin/env bash
# @module transverse.infra
# @description Infrastructure referential: the mounted, versioned directory
#   that declares WHERE the platform services live (endpoints), WHO
#   authenticates against them (credentials, by reference only) and WHICH
#   credential/provider an environment binds (bindings). brik.yml declares
#   requirements; this referential declares the infrastructure that meets
#   them. Absence is an error: every consumer fails closed instead of
#   falling back to ad-hoc BRIK_* infrastructure variables.
#
# Bootstrap (mutually exclusive):
#   BRIK_INFRA_DIR  - path to a referential instance on disk
#   BRIK_INFRA_REPO - git URL of a referential repo, optionally '#<ref>'
#                     pinned; cloned under the log dir at first use

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_TRANSVERSE_INFRA_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_INFRA_LOADED=1

_BRIK_INFRA_API_VERSION="brik.dev/referential/v1"

# Kinds legal per category directory. trust/ holds raw material (CA certs,
# allowed_signers) and schemas/ the editor copies: neither holds documents.
_BRIK_INFRA_ENDPOINT_KINDS="Registry GitHost Signing SecretManager K8sTarget ArgoCD SshTarget PackageRegistry Notification"

# infra.root - resolve and echo the referential instance directory.
# Usage: infra.root
# Returns: 4 when unconfigured or ambiguous (fail closed); 7 when the
#          directory is not a referential instance; 5 when the clone fails.
infra.root() {
    local dir="${BRIK_INFRA_DIR:-}" repo="${BRIK_INFRA_REPO:-}"

    if [[ -n "$dir" && -n "$repo" ]]; then
        log.error "BRIK_INFRA_DIR and BRIK_INFRA_REPO are mutually exclusive"
        return "$BRIK_EXIT_INVALID_ENV"
    fi
    if [[ -z "$dir" && -z "$repo" ]]; then
        log.error "no infrastructure referential configured: set BRIK_INFRA_DIR or BRIK_INFRA_REPO (scaffold one with 'brik infra init')"
        return "$BRIK_EXIT_INVALID_ENV"
    fi

    if [[ -n "$repo" ]]; then
        dir="$(_infra._clone "$repo")" || return "$?"
    fi

    if [[ ! -d "$dir" ]]; then
        log.error "referential directory not found: ${dir}"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    if [[ ! -f "${dir}/referential.yml" ]]; then
        log.error "${dir} is not a referential instance (no referential.yml)"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    (cd "$dir" && pwd)
}

# _infra._clone - materialize BRIK_INFRA_REPO under the log dir and echo the
# clone path. An existing clone is reused as-is: one referential state per
# run, no mid-run refresh. A '#<ref>' URL fragment pins the checkout.
_infra._clone() {
    local spec="$1"
    local dest="${BRIK_LOG_DIR:-.brik-logs}/infra-referential"

    if [[ -d "${dest}/.git" ]]; then
        printf '%s' "$dest"
        return 0
    fi

    local url="${spec%%#*}" ref="" out
    [[ "$spec" == *'#'* ]] && ref="${spec#*#}"

    mkdir -p "$(dirname "$dest")"
    # Redact any embedded credential (https://token@host) from the URL and the
    # git output before logging, the way state_repo does for push errors.
    local safe_url
    safe_url="$(printf '%s' "$url" | sed -E 's#://[^@/]*@#://***@#')"
    if ! out="$(git clone --quiet "$url" "$dest" 2>&1)"; then
        log.error "failed to clone referential repo ${safe_url}: $(printf '%s' "$out" | sed -E 's#://[^@/]*@#://***@#')"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi
    if [[ -n "$ref" ]]; then
        if ! out="$(git -C "$dest" checkout --quiet --detach "$ref" 2>&1)"; then
            log.error "failed to checkout referential ref '${ref}': $(printf '%s' "$out" | sed -E 's#://[^@/]*@#://***@#')"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        fi
    else
        # The referential is the trust material (allowed_signers, policies,
        # endpoints). An unpinned clone can change between two deploys of the
        # same version; the plan.json fingerprint records the drift but cannot
        # prevent it -- pin the ref ('#<ref>') for a reproducible referential.
        log.warn "BRIK_INFRA_REPO carries no pinned ref (append '#<ref>'): using the default branch, unpinned -- the trust material can change between runs"
    fi

    printf '%s' "$dest"
}

# infra.validate - eager, fail-closed validation of a referential instance:
# every document must carry the expected apiVersion, a kind known to the
# schema set, a unique name within its category, and pass its kind schema;
# binding references must resolve within the instance.
# Usage: infra.validate [root]
# Returns: 0 valid; 7 on any violation; infra.root codes when unconfigured.
infra.validate() {
    local root
    if [[ -n "${1:-}" ]]; then
        root="$1"
    else
        root="$(infra.root)" || return "$?"
    fi

    brik.use transverse.config

    _infra._validate_doc "${root}/referential.yml" "Referential" >/dev/null || return "$?"

    # Unsupported category directories are an error: failing closed beats
    # silently skipping documents the operator believes are enforced.
    local dir base
    for dir in "$root"/*/; do
        [[ -d "$dir" ]] || continue
        base="$(basename "$dir")"
        case "$base" in
            endpoints|credentials|bindings|policies|trust|schemas) ;;
            *)
                if compgen -G "${dir}*.yml" >/dev/null || compgen -G "${dir}*.yaml" >/dev/null; then
                    log.error "unsupported referential category '${base}/' (supported: endpoints/, credentials/, bindings/, policies/)"
                    return "$BRIK_EXIT_CONFIG_ERROR"
                fi
                ;;
        esac
    done

    _infra._validate_category "$root" endpoints "$_BRIK_INFRA_ENDPOINT_KINDS" || return "$?"
    _infra._validate_category "$root" credentials "Credential" || return "$?"
    _infra._validate_category "$root" bindings "Binding" || return "$?"
    _infra._validate_category "$root" policies "Policy" || return "$?"
    _infra._validate_bindings "$root" || return "$?"
    _infra._validate_endpoint_credentials "$root" || return "$?"
}

# _infra._validate_endpoint_credentials - an endpoint declaring an inline
# credential reference (PackageRegistry.credential) must reference an
# existing Credential document; a dangling name fails validation here, not
# the publish that would have consumed it.
_infra._validate_endpoint_credentials() {
    local root="$1"
    local dir="${root}/endpoints"
    [[ -d "$dir" ]] || return 0

    local file cred
    for file in "$dir"/*.yml "$dir"/*.yaml; do
        [[ -f "$file" ]] || continue
        cred="$(yq '.credential // ""' "$file")"
        [[ -n "$cred" ]] || continue
        if ! _infra._find_doc "$root" credentials "$cred" >/dev/null; then
            log.error "${file}: endpoint references unknown credential '${cred}'"
            return "$BRIK_EXIT_CONFIG_ERROR"
        fi
    done
}

# _infra._validate_doc - validate one document: apiVersion, known kind within
# the allowed set, schema conformance. Echoes the document name (empty for
# the root Referential manifest) so the caller can detect duplicates.
_infra._validate_doc() {
    local file="$1" allowed="$2"
    local api kind name

    api="$(yq '.apiVersion // ""' "$file")"
    if [[ "$api" != "$_BRIK_INFRA_API_VERSION" ]]; then
        log.error "${file}: unexpected apiVersion '${api}' (expected ${_BRIK_INFRA_API_VERSION})"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    kind="$(yq '.kind // ""' "$file")"
    local schema
    schema="${BRIK_HOME}/schemas/referential/v1/$(printf '%s' "$kind" | tr '[:upper:]' '[:lower:]').schema.json"
    if [[ -z "$kind" || ! -f "$schema" ]]; then
        log.error "${file}: unknown kind '${kind}'"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    case " ${allowed} " in
        *" ${kind} "*) ;;
        *)
            log.error "${file}: kind ${kind} does not belong in this category (allowed: ${allowed})"
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac

    if [[ "$kind" != "Referential" ]]; then
        name="$(yq '.name // ""' "$file")"
        if [[ -z "$name" ]]; then
            log.error "${file}: missing required 'name'"
            return "$BRIK_EXIT_CONFIG_ERROR"
        fi
    fi

    if ! config.validate_schema "$file" "$schema"; then
        log.error "${file}: schema validation failed (kind ${kind})"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    printf '%s' "${name:-}"
}

# _infra._validate_category - validate every document of a category directory
# and enforce name uniqueness (names are the reference keys).
_infra._validate_category() {
    local root="$1" category="$2" allowed="$3"
    local dir="${root}/${category}"
    [[ -d "$dir" ]] || return 0

    local file name seen=" "
    for file in "$dir"/*.yml "$dir"/*.yaml; do
        [[ -f "$file" ]] || continue
        name="$(_infra._validate_doc "$file" "$allowed")" || return "$?"
        if [[ "$seen" == *" ${name} "* ]]; then
            log.error "${file}: duplicate name '${name}' in ${category}/"
            return "$BRIK_EXIT_CONFIG_ERROR"
        fi
        seen="${seen}${name} "
    done
}

# _infra._validate_bindings - every endpoint/credential name a binding
# references must exist in the instance (eager reference check; secret
# RESOLUTION stays lazy, per stage).
_infra._validate_bindings() {
    local root="$1"
    local dir="${root}/bindings"
    [[ -d "$dir" ]] || return 0

    local file pair ep cred
    for file in "$dir"/*.yml "$dir"/*.yaml; do
        [[ -f "$file" ]] || continue
        while IFS= read -r pair; do
            [[ -n "$pair" ]] || continue
            ep="${pair%% *}"
            cred="${pair#* }"
            if ! _infra._find_doc "$root" endpoints "$ep" >/dev/null; then
                log.error "${file}: binding references unknown endpoint '${ep}'"
                return "$BRIK_EXIT_CONFIG_ERROR"
            fi
            if ! _infra._find_doc "$root" credentials "$cred" >/dev/null; then
                log.error "${file}: binding references unknown credential '${cred}'"
                return "$BRIK_EXIT_CONFIG_ERROR"
            fi
        done < <(yq '.endpoints // {} | to_entries | .[] | .key + " " + .value' "$file")
    done
}

# _infra._find_doc - echo the file path of the document named <name> in
# <category>; non-zero when absent.
_infra._find_doc() {
    local root="$1" category="$2" name="$3" file
    for file in "${root}/${category}"/*.yml "${root}/${category}"/*.yaml; do
        [[ -f "$file" ]] || continue
        if [[ "$(yq '.name // ""' "$file")" == "$name" ]]; then
            printf '%s' "$file"
            return 0
        fi
    done
    return 1
}

# _infra._doc_json - echo a named document as JSON.
_infra._doc_json() {
    local category="$1" name="$2" label="$3"
    if [[ -z "$name" ]]; then
        log.error "infra.${label}: a name is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local root file
    root="$(infra.root)" || return "$?"
    if ! file="$(_infra._find_doc "$root" "$category" "$name")"; then
        log.error "no ${label} named '${name}' in ${root}/${category}"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    yq -o json '.' "$file"
}

# infra.endpoint - echo the endpoint document <name> as JSON.
# Returns: 2 no name; 7 unknown; infra.root codes when unconfigured.
infra.endpoint() { _infra._doc_json endpoints "$1" "endpoint"; }

# infra.credential - echo the credential document <name> as JSON.
infra.credential() { _infra._doc_json credentials "$1" "credential"; }

# infra.binding - echo the binding document for environment <name> as JSON.
infra.binding() { _infra._doc_json bindings "$1" "binding"; }

# infra.policy - echo the policy document <name> as JSON.
infra.policy() { _infra._doc_json policies "$1" "policy"; }

# infra.policy_names - echo the names of the declared policy documents, one
# per line (empty output when the instance declares none).
infra.policy_names() {
    local root file
    root="$(infra.root)" || return "$?"
    for file in "${root}/policies"/*.yml "${root}/policies"/*.yaml; do
        [[ -f "$file" ]] || continue
        yq '.name // ""' "$file"
    done
    return 0
}

# infra.capability_norm - normalize one Binding capability value to the single
# internal shape {provider, endpoint}. A bare provider string and the object
# form {provider, endpoint?} both collapse here, so a future consumer reads
# one shape, never two. No runtime consumes it
# yet; this is the read path, not the binding.
# Usage: infra.capability_norm '<json-value>'
# Returns: 2 empty; 7 not a provider string or {provider, ...} object.
infra.capability_norm() {
    local value="$1"
    if [[ -z "$value" ]]; then
        log.error "infra.capability_norm: a capability value is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if ! printf '%s' "$value" | jq -ec '
        if type == "string" then {provider: ., endpoint: null}
        elif type == "object" and (.provider | type) == "string"
        then {provider: .provider, endpoint: (.endpoint // null)}
        else error("not a provider string or {provider, endpoint?} object") end
    ' 2>/dev/null; then
        log.error "infra.capability_norm: capability must be a provider string or {provider, endpoint?} object (got: ${value})"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
}

# infra.capability_provider - echo (as JSON) the {provider, endpoint} an
# environment binds for a capability. Reads the Binding's .capabilities[<cap>]
# (scalar provider or {provider, endpoint?} object) and collapses both forms to
# the single {provider, endpoint} shape via infra.capability_norm. An unbound
# capability fails closed: a deliberately absent capability is a missing
# binding, never an implicit default.
# Usage: infra.capability_provider <environment> <capability>
# Returns: 2 missing argument; 7 no binding or capability unbound; infra.root
#          codes when unconfigured.
infra.capability_provider() {
    local env="$1" capability="$2"
    if [[ -z "$env" || -z "$capability" ]]; then
        log.error "infra.capability_provider: <environment> and <capability> are required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local root file
    root="$(infra.root)" || return "$?"
    if ! file="$(_infra._find_doc "$root" bindings "$env")"; then
        log.error "no binding for environment '${env}'"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    local value
    value="$(capability="$capability" yq -o json '.capabilities[strenv(capability)]' "$file")"
    if [[ -z "$value" || "$value" == "null" ]]; then
        log.error "environment '${env}' binds no provider for capability '${capability}'"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    infra.capability_norm "$value"
}

# infra.endpoint_for_capability - echo (as JSON) the endpoint a capability
# resolves to in an environment, closing the chain the provider manifest
# documents: capability -> provider -> endpoint_kind -> endpoint. The binding
# selects the provider; an endpoint named explicitly in the binding wins,
# otherwise the provider manifest's endpoint_kind resolves the single endpoint
# of that kind. A provider unknown to the registry, or one implementing a
# different capability than the one bound, is a configuration error and fails
# closed.
# Usage: infra.endpoint_for_capability <environment> <capability>
# Returns: 2 missing argument; 7 unknown/mismatched provider or unresolved
#          endpoint; infra.root codes when unconfigured.
infra.endpoint_for_capability() {
    local env="$1" capability="$2"
    if [[ -z "$env" || -z "$capability" ]]; then
        log.error "infra.endpoint_for_capability: <environment> and <capability> are required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local norm provider endpoint
    norm="$(infra.capability_provider "$env" "$capability")" || return "$?"
    provider="$(printf '%s' "$norm" | jq -r '.provider')"
    endpoint="$(printf '%s' "$norm" | jq -r '.endpoint // ""')"

    brik.use registry.registry || return "$?"

    if ! registry.provider.exists "$provider" >/dev/null 2>&1; then
        log.error "capability '${capability}' in environment '${env}' binds unknown provider '${provider}'"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    local provider_cap
    provider_cap="$(registry.provider.capability "$provider")" || return "$?"
    if [[ "$provider_cap" != "$capability" ]]; then
        log.error "provider '${provider}' implements capability '${provider_cap}', not '${capability}' as bound in environment '${env}'"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    # An explicit endpoint in the binding wins; otherwise resolve the single
    # endpoint of the provider's declared kind.
    if [[ -n "$endpoint" ]]; then
        infra.endpoint "$endpoint"
        return "$?"
    fi

    local kind
    kind="$(registry.provider.endpoint_kind "$provider")" || return "$?"
    if [[ -z "$kind" ]]; then
        log.error "provider '${provider}' declares no endpoint_kind; capability '${capability}' cannot resolve an endpoint"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    infra.endpoint_of_kind "$kind"
}

# infra.credential_for - echo (as JSON) the credential an environment binds
# for an endpoint. Unbound is an error: a deliberately anonymous endpoint
# binds a credential with method 'none'.
# Usage: infra.credential_for <environment> <endpoint>
infra.credential_for() {
    local env="$1" endpoint="$2"
    if [[ -z "$env" || -z "$endpoint" ]]; then
        log.error "infra.credential_for: <environment> and <endpoint> are required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local root file cred
    root="$(infra.root)" || return "$?"
    if ! file="$(_infra._find_doc "$root" bindings "$env")"; then
        log.error "no binding for environment '${env}'"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    cred="$(endpoint="$endpoint" yq '.endpoints[strenv(endpoint)] // ""' "$file")"
    if [[ -z "$cred" ]]; then
        log.error "environment '${env}' binds no credential for endpoint '${endpoint}'"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    infra.credential "$cred"
}

# infra.credential_for_endpoint - echo (as JSON) the credential bound to an
# endpoint, INDEPENDENTLY of any environment. CI-time consumers (docker push,
# promote, channel, evidence) operate with no deploy environment selected, but
# the credential must still come from the referential (no *_var in brik.yml).
# Every binding that maps the endpoint must agree on the credential: a single
# coherent name resolves, divergence across environments is a genuine CI-time
# ambiguity and fails closed (never a guess). Unbound is an error.
# Usage: infra.credential_for_endpoint <endpoint>
# Returns: 2 no endpoint; 7 unbound or divergent; infra.root codes unconfigured.
infra.credential_for_endpoint() {
    local endpoint="$1"
    if [[ -z "$endpoint" ]]; then
        log.error "infra.credential_for_endpoint: an endpoint name is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local root file cred creds=" "
    root="$(infra.root)" || return "$?"
    for file in "${root}/bindings"/*.yml "${root}/bindings"/*.yaml; do
        [[ -f "$file" ]] || continue
        cred="$(endpoint="$endpoint" yq '.endpoints[strenv(endpoint)] // ""' "$file")"
        [[ -n "$cred" ]] || continue
        [[ "$creds" == *" ${cred} "* ]] && continue
        creds="${creds}${cred} "
    done

    # creds is " a b " for divergent, " a " for coherent, " " for unbound.
    creds="${creds# }"; creds="${creds% }"
    if [[ -z "$creds" ]]; then
        log.error "no binding maps endpoint '${endpoint}' to a credential (CI-time resolution needs one)"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    if [[ "$creds" == *" "* ]]; then
        log.error "endpoint '${endpoint}' is bound to divergent credentials across environments (${creds// /, }) -- CI-time resolution is ambiguous; unify the binding or operate it per environment"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    infra.credential "$creds"
}

# infra.endpoint_of_kind - echo (as JSON) the single endpoint of <kind>
# declared by the instance. Capabilities that consume platform-wide services
# (Signing, SecretManager) resolve their endpoint by kind: zero is a missing
# declaration, several an ambiguity; both fail closed.
# Usage: infra.endpoint_of_kind <kind>
# Returns: 2 no kind; 7 none or several; infra.root codes when unconfigured.
infra.endpoint_of_kind() {
    local kind="$1"
    if [[ -z "$kind" ]]; then
        log.error "infra.endpoint_of_kind: a kind is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local root file found=""
    root="$(infra.root)" || return "$?"
    for file in "${root}/endpoints"/*.yml "${root}/endpoints"/*.yaml; do
        [[ -f "$file" ]] || continue
        [[ "$(yq '.kind // ""' "$file")" == "$kind" ]] || continue
        if [[ -n "$found" ]]; then
            log.error "multiple ${kind} endpoints declared in the referential (expected exactly one)"
            return "$BRIK_EXIT_CONFIG_ERROR"
        fi
        found="$file"
    done
    if [[ -z "$found" ]]; then
        log.error "no ${kind} endpoint declared in the referential"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    yq -o json '.' "$found"
}

# infra.registry_for - echo (as JSON) the Registry endpoint whose URL
# authority matches <host> (host[:port]). The declared scheme and TLS trust
# govern how every registry consumer (digest resolution, cosign referrers)
# reaches the service: http:// and tls.trust: insecure are legal but noisy,
# an undeclared host fails closed.
# Usage: infra.registry_for <host>
# Returns: 2 no host; 7 undeclared; infra.root codes when unconfigured.
infra.registry_for() {
    local host="$1"
    if [[ -z "$host" ]]; then
        log.error "infra.registry_for: a registry host is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local root file url authority
    root="$(infra.root)" || return "$?"
    for file in "${root}/endpoints"/*.yml "${root}/endpoints"/*.yaml; do
        [[ -f "$file" ]] || continue
        [[ "$(yq '.kind // ""' "$file")" == "Registry" ]] || continue
        url="$(yq '.url // ""' "$file")"
        authority="${url#*://}"
        authority="${authority%%/*}"
        [[ "$authority" == "$host" ]] || continue

        if [[ "$url" == http://* ]]; then
            log.warn "registry '${host}' is declared over plain http (legal but insecure)"
        elif [[ "$(yq '.tls.trust // ""' "$file")" == "insecure" ]]; then
            log.warn "registry '${host}' is declared with tls.trust: insecure (legal but insecure)"
        fi
        yq -o json '.' "$file"
        return 0
    done

    log.error "registry host '${host}' is not declared in the referential (add a Registry endpoint)"
    return "$BRIK_EXIT_CONFIG_ERROR"
}

# infra.evidence_token_var - echo the environment-variable NAME of the GitHost
# token that authenticates against the evidence state-repo, resolved BY TARGET
# (the repo's host) and INDEPENDENTLY of any deploy environment. The state-repo
# is one per project and consumed from both CI (recording evidence) and CD
# (reading journals/eligibility), so resolution must not depend on an
# --environment selection (PD3). Matching is by hostname: a GitHost git_url is
# often ssh:// while the repo URL is https://, and the port differs across
# transports, so scheme, userinfo and port are stripped on both sides.
#
# Non-breaking: when no referential is configured, or no declared GitHost
# serves the repo's host, this echoes nothing and returns 0 so the caller
# keeps its legacy .artifacts.evidence.token_var. A declared GitHost whose
# credential is unbound or divergent fails closed (the operator opted into
# referential-managed credentials for this host). A credential with no token
# (method none) also echoes nothing.
# Usage: var="$(infra.evidence_token_var "$repo_url")" || return $?
# Returns: 2 no repo URL; 7 unbound/divergent credential or non-env:// token.
infra.evidence_token_var() {
    local repo="$1"
    if [[ -z "$repo" ]]; then
        log.error "infra.evidence_token_var: an evidence repo URL is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    # Unconfigured referential: caller keeps the legacy token_var.
    infra.root >/dev/null 2>&1 || return 0

    # Hostname of the evidence repo: scheme, userinfo, port and path stripped.
    local host="${repo#*://}"; host="${host##*@}"; host="${host%%/*}"; host="${host%%:*}"
    [[ -n "$host" ]] || return 0

    # Find the single GitHost whose api_url or git_url hostname matches.
    local root file ghname="" url uhost
    root="$(infra.root)" || return "$?"
    for file in "${root}/endpoints"/*.yml "${root}/endpoints"/*.yaml; do
        [[ -f "$file" ]] || continue
        [[ "$(yq '.kind // ""' "$file")" == "GitHost" ]] || continue
        for url in "$(yq '.api_url // ""' "$file")" "$(yq '.git_url // ""' "$file")"; do
            [[ -n "$url" ]] || continue
            uhost="${url#*://}"; uhost="${uhost##*@}"; uhost="${uhost%%/*}"; uhost="${uhost%%:*}"
            if [[ "$uhost" == "$host" ]]; then
                ghname="$(yq '.name // ""' "$file")"
                break
            fi
        done
        [[ -n "$ghname" ]] && break
    done
    # No declared GitHost for this host: caller keeps the legacy token_var.
    [[ -n "$ghname" ]] || return 0

    # Credential by target, environment-independent (fail-closed on a declared
    # but unbound/divergent endpoint).
    local cred tok
    cred="$(infra.credential_for_endpoint "$ghname")" || return "$?"
    tok="$(printf '%s' "$cred" | jq -r '.token // ""')"
    # method none (or no token): nothing to forward.
    [[ -n "$tok" ]] || return 0
    infra.env_var_of_ref "$tok"
}

# infra.tls_ca - echo the CA bundle path for an endpoint (JSON document)
# declaring tls.trust: custom-ca, resolved by the trust/ca/<hostname>/ca.crt
# convention of the referential. Any other trust value echoes nothing. The
# hostname comes from the endpoint's url (api_url for GitHost), port and
# path stripped. Fail-closed: a declared custom-ca whose bundle is absent
# is CONFIG_ERROR, never a silent fallback to the system pool.
# Usage: ca="$(infra.tls_ca "$endpoint_json")" || return $?
infra.tls_ca() {
    local endpoint="$1"
    [[ "$(printf '%s' "$endpoint" | jq -r '.tls.trust // ""')" == "custom-ca" ]] \
        || return 0

    local url host root ca
    url="$(printf '%s' "$endpoint" | jq -r '.url // .api_url // ""')"
    host="${url#*://}"
    host="${host%%/*}"
    host="${host%%:*}"
    if [[ -z "$host" ]]; then
        log.error "infra.tls_ca: the endpoint declares custom-ca but carries no url to derive the hostname from"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    root="$(infra.root)" || return "$?"
    ca="${root}/trust/ca/${host}/ca.crt"
    if [[ ! -f "$ca" ]]; then
        log.error "endpoint '${host}' declares tls.trust: custom-ca but the bundle is absent at trust/ca/${host}/ca.crt"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
    printf '%s' "$ca"
}

# infra.ssh_target_for - echo (as JSON) the SshTarget endpoint declaring
# <host> in its hosts list. Host keys and the strict-host-key stance come
# from this declaration; an undeclared host fails closed (no env override).
# Usage: infra.ssh_target_for <host>
# Returns: 2 no host; 7 undeclared; infra.root codes when unconfigured.
infra.ssh_target_for() {
    local host="$1"
    if [[ -z "$host" ]]; then
        log.error "infra.ssh_target_for: a host is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    local root file
    root="$(infra.root)" || return "$?"
    for file in "${root}/endpoints"/*.yml "${root}/endpoints"/*.yaml; do
        [[ -f "$file" ]] || continue
        [[ "$(yq '.kind // ""' "$file")" == "SshTarget" ]] || continue
        if [[ "$(host="$host" yq '.hosts // [] | contains([strenv(host)])' "$file")" == "true" ]]; then
            yq -o json '.' "$file"
            return 0
        fi
    done

    log.error "ssh host '${host}' is not declared in the referential (add an SshTarget endpoint)"
    return "$BRIK_EXIT_CONFIG_ERROR"
}

# infra.env_var_of_ref - echo the environment-variable NAME behind an env://
# reference. Deploy/publish consumers hand a variable NAME to their tool (the
# tool reads the value from the environment), so a file:// or bao:// secret -
# which has no such name - fails closed rather than being silently dropped.
# Usage: var="$(infra.env_var_of_ref "$ref")" || return $?
# Returns: 2 empty; 7 non-env:// reference.
infra.env_var_of_ref() {
    local ref="$1"
    if [[ -z "$ref" ]]; then
        log.error "infra.env_var_of_ref: a reference is required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    case "$ref" in
        env://*) printf '%s' "${ref#env://}" ;;
        *)
            log.error "infra.env_var_of_ref: '${ref}' must be an env:// reference (a variable name is needed; file:// and bao:// have none)"
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac
}

# infra.resolve_ref - resolve a by-reference value. References are the only
# way the referential carries secret material; values never appear inline.
#   env://VAR        - environment variable (error when unset or empty)
#   file://path      - file content; relative paths resolve against the
#                      referential root (portable instances)
#   bao://m/path#key - OpenBAO KV; requires the secret-manager provider
# Usage: infra.resolve_ref <ref>
# Returns: 2 unknown scheme; 4 unset variable; 6 unreadable file; 3 bao://
#          until the OpenBAO provider is wired.
infra.resolve_ref() {
    local ref="$1"
    case "$ref" in
        env://*)
            brik.use transverse.env
            local var="${ref#env://}" value
            value="$(transverse.env.resolve_indirect "$var")"
            if [[ -z "$value" ]]; then
                log.error "reference ${ref}: variable ${var} is unset or empty"
                return "$BRIK_EXIT_INVALID_ENV"
            fi
            printf '%s' "$value"
            ;;
        file://*)
            local path="${ref#file://}"
            if [[ "$path" != /* ]]; then
                local root
                root="$(infra.root)" || return "$?"
                path="${root}/${path}"
            fi
            if [[ ! -r "$path" ]]; then
                log.error "reference ${ref}: file not readable: ${path}"
                return "$BRIK_EXIT_IO_FAILURE"
            fi
            cat "$path"
            ;;
        bao://*)
            log.error "reference ${ref}: bao:// resolution requires the OpenBAO secret-manager provider (not wired yet)"
            return "$BRIK_EXIT_MISSING_DEP"
            ;;
        *)
            log.error "unknown reference scheme: ${ref} (supported: env://, file://, bao://)"
            return "$BRIK_EXIT_INVALID_INPUT"
            ;;
    esac
}

# infra.fingerprint - echo a sha256 over the relative paths and contents of
# the instance, so plan.json can pin the environment the plan was derived
# from. Location-independent: the same instance hashes identically wherever
# it is mounted or cloned.
# Usage: infra.fingerprint [root]
infra.fingerprint() {
    local root
    if [[ -n "${1:-}" ]]; then
        root="$1"
    else
        root="$(infra.root)" || return "$?"
    fi

    (cd "$root" && find . -type f ! -path './.git/*' -print0 \
        | LC_ALL=C sort -z \
        | xargs -0 sha256sum) \
        | sha256sum | cut -d' ' -f1
}

# infra.secret_vars - emit, as JSON {pipeline:[...], infra:[...]}, the names of
# the environment variables an operator must provision for this referential,
# derived BY TARGET (the operated endpoints' credentials) and INDEPENDENTLY of
# any deploy environment (PD3): at CI time no environment is selected.
#   pipeline-side - every env:// reference held by a Credential document (the
#                   registry/git/signing credentials the pipeline consumes).
#   infra-side    - the SecretManager bootstrap token (the env:// it
#                   authenticates with): the one secret needed to reach the
#                   manager that resolves every bao:// reference.
# file:// references carry no variable; bao:// resolves through the manager and
# is not an env var (both are skipped). Names are sorted and de-duplicated; a
# name on the infra side is never repeated on the pipeline side.
# Usage: infra.secret_vars
# Returns: infra.root codes when unconfigured.
infra.secret_vars() {
    local root file ref
    root="$(infra.root)" || return "$?"

    local pipeline="" infra_side=""
    # pipeline-side: every env:// scalar across the credential documents.
    for file in "${root}/credentials"/*.yml "${root}/credentials"/*.yaml; do
        [[ -f "$file" ]] || continue
        while IFS= read -r ref; do
            [[ "$ref" == env://* ]] && pipeline="${pipeline}${ref#env://}"$'\n'
        done < <(yq -r '.. | select(tag == "!!str")' "$file" 2>/dev/null)
    done
    # infra-side: the SecretManager auth token, when it is an env:// reference.
    for file in "${root}/endpoints"/*.yml "${root}/endpoints"/*.yaml; do
        [[ -f "$file" ]] || continue
        [[ "$(yq -r '.kind // ""' "$file")" == "SecretManager" ]] || continue
        ref="$(yq -r '.auth.ref // ""' "$file")"
        [[ "$ref" == env://* ]] && infra_side="${infra_side}${ref#env://}"$'\n'
    done

    jq -n --arg p "$pipeline" --arg i "$infra_side" '
        ($i | split("\n") | map(select(length > 0)) | unique) as $ia |
        ($p | split("\n") | map(select(length > 0)) | unique) as $pa |
        { pipeline: ($pa - $ia), infra: $ia }'
}

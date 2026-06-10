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
_BRIK_INFRA_ENDPOINT_KINDS="Registry GitHost Signing SecretManager K8sTarget ArgoCD SshTarget"

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
    if ! out="$(git clone --quiet "$url" "$dest" 2>&1)"; then
        log.error "failed to clone referential repo ${url}: ${out}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi
    if [[ -n "$ref" ]]; then
        if ! out="$(git -C "$dest" checkout --quiet --detach "$ref" 2>&1)"; then
            log.error "failed to checkout referential ref '${ref}': ${out}"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        fi
    else
        log.warn "BRIK_INFRA_REPO carries no pinned ref (append '#<ref>'): using the default branch, unpinned"
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
            endpoints|credentials|bindings|trust|schemas) ;;
            *)
                if compgen -G "${dir}*.yml" >/dev/null || compgen -G "${dir}*.yaml" >/dev/null; then
                    log.error "unsupported referential category '${base}/' (supported: endpoints/, credentials/, bindings/)"
                    return "$BRIK_EXIT_CONFIG_ERROR"
                fi
                ;;
        esac
    done

    _infra._validate_category "$root" endpoints "$_BRIK_INFRA_ENDPOINT_KINDS" || return "$?"
    _infra._validate_category "$root" credentials "Credential" || return "$?"
    _infra._validate_category "$root" bindings "Binding" || return "$?"
    _infra._validate_bindings "$root" || return "$?"
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

    cred="$(yq ".endpoints.\"${endpoint}\" // \"\"" "$file")"
    if [[ -z "$cred" ]]; then
        log.error "environment '${env}' binds no credential for endpoint '${endpoint}'"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    infra.credential "$cred"
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

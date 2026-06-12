#!/usr/bin/env bash
# @module deployments.readback
# @description Post-deploy read-back of the live image digest. Records the
#   resolved digest and, where the target exposes a live query, the
#   actually-deployed digest + a match flag into the deploy stage report. This
#   is observability: a mismatch warns but does not fail the deploy by itself.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_DEPLOYMENTS_READBACK_LOADED:-}" ]] && return 0
_BRIK_MODULE_DEPLOYMENTS_READBACK_LOADED=1

# _deploy.readback._resolve <var_name> - indirect env read via the centralized
# helper, loading it only when absent (keeps unit specs hermetic).
_deploy.readback._resolve() {
    declare -f transverse.env.resolve_indirect >/dev/null 2>&1 || brik.use transverse.env
    transverse.env.resolve_indirect "$1"
}

# _deploy.readback._k8s_deployment_name <manifest> - echo the first Deployment's
# metadata.name found in the manifest, or nothing.
_deploy.readback._k8s_deployment_name() {
    local manifest="$1"
    [[ -n "$manifest" && -f "$manifest" ]] || return 0
    command -v yq >/dev/null 2>&1 || return 0
    yq e 'select(.kind == "Deployment") | .metadata.name' "$manifest" 2>/dev/null \
        | grep -v '^null$' | head -1
}

# _deploy.readback._live <target> <controller> <upper_env> - echo the live
# digest ("sha256:..." | "unknown" | "unsupported"). Never returns non-zero.
_deploy.readback._live() {
    local target="$1" controller="$2" upper_env="$3"
    case "$target" in
        gitops)
            [[ "$controller" != "argocd" ]] && { printf 'unsupported'; return 0; }
            local app auth
            app="$(_deploy.readback._resolve "BRIK_DEPLOY_${upper_env}_APP_NAME")"
            auth="$(_deploy.readback._resolve "BRIK_DEPLOY_${upper_env}_AUTH_TOKEN_VAR")"
            [[ -z "$app" ]] && { printf 'unknown'; return 0; }
            declare -f deploy.argocd.get_deployed_digest >/dev/null 2>&1 \
                || brik.use deployments.argocd
            local -a a=(--app "$app")
            [[ -n "$auth" ]] && a+=(--auth-token-var "$auth")
            deploy.argocd.get_deployed_digest "${a[@]}" 2>/dev/null || printf 'unknown'
            ;;
        k8s)
            local manifest ns dep
            manifest="$(_deploy.readback._resolve "BRIK_DEPLOY_${upper_env}_MANIFEST")"
            ns="$(_deploy.readback._resolve "BRIK_DEPLOY_${upper_env}_NAMESPACE")"
            dep="$(_deploy.readback._k8s_deployment_name "$manifest")"
            [[ -z "$dep" ]] && { printf 'unknown'; return 0; }
            declare -f deploy.k8s.get_deployed_digest >/dev/null 2>&1 \
                || brik.use deployments.k8s
            local -a a=(--deployment "$dep")
            [[ -n "$ns" ]] && a+=(--namespace "$ns")
            deploy.k8s.get_deployed_digest "${a[@]}" 2>/dev/null || printf 'unknown'
            ;;
        helm)
            local release ns
            release="$(_deploy.readback._resolve "BRIK_DEPLOY_${upper_env}_RELEASE_NAME")"
            ns="$(_deploy.readback._resolve "BRIK_DEPLOY_${upper_env}_NAMESPACE")"
            [[ -z "$release" ]] && { printf 'unknown'; return 0; }
            declare -f deploy.helm.get_deployed_digest >/dev/null 2>&1 \
                || brik.use deployments.helm
            local -a a=(--release "$release")
            [[ -n "$ns" ]] && a+=(--namespace "$ns")
            deploy.helm.get_deployed_digest "${a[@]}" 2>/dev/null || printf 'unknown'
            ;;
        compose)
            local service project
            service="$(_deploy.readback._resolve "BRIK_DEPLOY_${upper_env}_SERVICE")"
            # compose deploys use the env namespace as the compose project name.
            project="$(_deploy.readback._resolve "BRIK_DEPLOY_${upper_env}_NAMESPACE")"
            [[ -z "$service" ]] && { printf 'unknown'; return 0; }
            declare -f deploy.compose.get_deployed_digest >/dev/null 2>&1 \
                || brik.use deployments.compose
            local -a a=(--service "$service")
            [[ -n "$project" ]] && a+=(--project "$project")
            deploy.compose.get_deployed_digest "${a[@]}" 2>/dev/null || printf 'unknown'
            ;;
        ssh)
            # rsync+restart exposes no live image query: the primitive reports
            # "unsupported" rather than a circular read of the local payload.
            declare -f deploy.ssh.get_deployed_digest >/dev/null 2>&1 \
                || brik.use deployments.ssh
            deploy.ssh.get_deployed_digest 2>/dev/null || printf 'unsupported'
            ;;
        *)
            printf 'unsupported'
            ;;
    esac
}

# deploy.readback.live_digest --env <name> --target <t> [--controller <c>]
# Echo the live digest ("sha256:..." | "unknown" | "unsupported"). Public
# query for callers that need the CURRENT live state -- the stage-side
# record() snapshot can lag a reconciling controller; the validates_for
# producer re-reads through this until the rollout converges.
deploy.readback.live_digest() {
    local env="" target="" controller=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --env)        env="$2";        shift 2 ;;
            --target)     target="$2";     shift 2 ;;
            --controller) controller="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    local upper_env
    upper_env="$(printf '%s' "$env" | tr '[:lower:]-' '[:upper:]_')"
    _deploy.readback._live "$target" "$controller" "$upper_env"
}

# deploy.readback.record --env <name> --target <t> [--controller <c>]
# Records deploy.tech.digest (resolved) and deploy.tech.deployed
# {resolved, live, match}. Always returns 0.
deploy.readback.record() {
    declare -f deploy.image_ref.extract_digest >/dev/null 2>&1 \
        || brik.use deployments._image_ref

    local env="" target="" controller=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --env)        env="$2";        shift 2 ;;
            --target)     target="$2";     shift 2 ;;
            --controller) controller="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local upper_env
    upper_env="$(printf '%s' "$env" | tr '[:lower:]-' '[:upper:]_')"

    local resolved live="unknown" match="false"
    resolved="$(deploy.image_ref.extract_digest "${BRIK_DEPLOY_IMAGE_REF:-}")"

    if [[ "${BRIK_DRY_RUN:-}" == "true" ]]; then
        live="skipped"
    else
        live="$(_deploy.readback._live "$target" "$controller" "$upper_env")"
    fi

    [[ "$resolved" != "unknown" && "$resolved" == "$live" ]] && match="true"

    report.record "deploy" "tech" "digest" "$resolved" 2>/dev/null || true
    if command -v jq >/dev/null 2>&1; then
        local obj
        obj="$(jq -nc --arg r "$resolved" --arg l "$live" --argjson m "$match" \
            '{resolved: $r, live: $l, match: $m}')"
        report.record_object "deploy" "tech" "deployed" "$obj" 2>/dev/null || true
    fi

    if [[ "$resolved" != "unknown" && "$live" != "unknown" \
          && "$live" != "skipped" && "$live" != "unsupported" \
          && "$resolved" != "$live" ]]; then
        log.warn "deployed digest mismatch for '${env}': resolved=${resolved} live=${live}"
    fi
    return 0
}

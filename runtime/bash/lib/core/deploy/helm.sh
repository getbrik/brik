#!/usr/bin/env bash
# @module deploy.helm
# @requires helm
# @description Deploy to Kubernetes via Helm upgrade --install.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_DEPLOY_HELM_LOADED:-}" ]] && return 0
_BRIK_CORE_DEPLOY_HELM_LOADED=1

# Deploy a Helm chart via helm upgrade --install.
# Usage: deploy.helm.run --chart <chart> [--release-name <name>]
#        [--namespace <ns>] [--values <file>] [--env <env>] [--dry-run]
deploy.helm.run() {
    local chart="" release_name="" namespace="" values="" environment=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --chart)        chart="$2";        shift 2 ;;
            --release-name) release_name="$2"; shift 2 ;;
            --namespace)    namespace="$2";    shift 2 ;;
            --values)       values="$2";       shift 2 ;;
            --dry-run)      dry_run="true";    shift ;;
            # Ignore deploy.run passthrough options
            --target)       shift 2 ;;
            --env)          environment="$2";  shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$chart" ]]; then
        log.error "chart is required (--chart)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    runtime.require_tool helm || return "$BRIK_EXIT_MISSING_DEP"

    # Resolve image tag from environment
    local tag="${BRIK_TAG:-${BRIK_COMMIT_SHA:-}}"

    # Derive release name: --release-name > BRIK_DEPLOY_{ENV}_RELEASE_NAME > chart basename
    if [[ -z "$release_name" && -n "$environment" ]]; then
        local upper_env
        upper_env="$(printf '%s' "$environment" | tr '[:lower:]' '[:upper:]')"
        local env_release_var="BRIK_DEPLOY_${upper_env}_RELEASE_NAME"
        release_name="${!env_release_var:-}"
    fi
    if [[ -z "$release_name" ]]; then
        release_name="$(basename "$chart")"
    fi

    # Build helm command
    local -a cmd=(helm upgrade --install "$release_name" "$chart")

    [[ -n "$namespace" ]] && cmd+=(--namespace "$namespace")
    if [[ -n "$values" ]]; then
        if [[ ! -f "$values" ]]; then
            log.error "values file not found: $values"
            return "$BRIK_EXIT_INVALID_INPUT"
        fi
        cmd+=(--values "$values")
    fi
    if [[ -n "$tag" ]]; then
        if ! [[ "$tag" =~ ^[a-zA-Z0-9._+-]+$ ]]; then
            log.error "invalid image tag format: $tag"
            return "$BRIK_EXIT_INVALID_INPUT"
        fi
        cmd+=(--set "image.tag=${tag}")
    fi

    if [[ "$dry_run" == "true" ]]; then
        cmd+=(--dry-run)
        log.info "[dry-run] ${cmd[*]}"
    else
        # Note: command logged in full -- do not add --set with secret values here.
        # Use --values with a file or Helm secrets plugin for sensitive configuration.
        log.info "running: ${cmd[*]}"
    fi

    "${cmd[@]}" || {
        log.error "helm upgrade failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "helm deployment completed successfully"
    return 0
}

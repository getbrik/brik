#!/usr/bin/env bash
# @module deploy.helm
# @requires helm
# @description Deploy to Kubernetes via Helm upgrade --install.

# Guard against double-sourcing
[[ -n "${_BRIK_DEPLOYMENTS_HELM_LOADED:-}" ]] && return 0
_BRIK_DEPLOYMENTS_HELM_LOADED=1

# Deploy a Helm chart via helm upgrade --install.
# Usage: deploy.helm.run --chart <chart> [--release <name>]
#        [--namespace <ns>] [--values <file>] [--env <env>] [--dry-run]
deploy.helm.run() {
    local chart="" release_name="" namespace="" values="" environment="" image_ref=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --chart)        chart="$2";        shift 2 ;;
            --release)      release_name="$2"; shift 2 ;;
            --namespace)    namespace="$2";    shift 2 ;;
            --values)       values="$2";       shift 2 ;;
            --image-ref)    image_ref="$2";    shift 2 ;;
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

    pipeline.require_tool helm || return "$BRIK_EXIT_MISSING_DEP"

    # Resolve image tag from environment
    local tag="${BRIK_TAG:-${BRIK_COMMIT_SHA:-}}"

    # Derive release name: --release-name > BRIK_DEPLOY_{ENV}_RELEASE_NAME > chart basename
    if [[ -z "$release_name" && -n "$environment" ]]; then
        local upper_env
        upper_env="$(printf '%s' "$environment" | tr '[:lower:]' '[:upper:]')"
        local env_release_var="BRIK_DEPLOY_${upper_env}_RELEASE_NAME"
        brik.use transverse.env
        release_name="$(transverse.env.resolve_indirect "$env_release_var")"
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
    if [[ -n "$image_ref" ]]; then
        # Digest-pinned deploy: set repository + digest and clear the tag so
        # the chart renders registry/app@sha256:X. The chart's image template
        # must honor .Values.image.digest (the conventional values contract).
        brik.use deployments._image_ref
        if ! deploy.image_ref.is_pinned "$image_ref"; then
            log.error "refusing a non-digest-pinned image ref: ${image_ref}"
            return "$BRIK_EXIT_INVALID_INPUT"
        fi
        local _img_repo="${image_ref%@*}" _img_digest="${image_ref#*@}"
        cmd+=(--set "image.repository=${_img_repo}"
              --set "image.digest=${_img_digest}"
              --set "image.tag=")
    elif [[ -n "$tag" ]]; then
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

# Read back the live image digest of a Helm release: render its live manifests
# with `helm get manifest`, take the first Deployment container image, and
# reduce it to its digest. Lets the deploy stage confirm the running image is
# the digest we deployed.
# Usage: deploy.helm.get_deployed_digest --release <name>
#        [--namespace <ns>] [--kube-context <ctx>]
# stdout: "sha256:..." | "unknown"
deploy.helm.get_deployed_digest() {
    local release="" namespace="" kube_context=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --release)      release="$2";      shift 2 ;;
            --namespace)    namespace="$2";    shift 2 ;;
            --kube-context) kube_context="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$release" ]]; then
        log.error "release name is required (--release)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    pipeline.require_tool helm || return "$BRIK_EXIT_MISSING_DEP"
    brik.use deployments._image_ref

    local -a cmd=(helm get manifest "$release")
    [[ -n "$namespace" ]]    && cmd+=(--namespace "$namespace")
    [[ -n "$kube_context" ]] && cmd+=(--kube-context "$kube_context")

    local manifests
    manifests="$("${cmd[@]}" 2>/dev/null)" || {
        log.error "helm get manifest failed for release: ${release}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    local image=""
    if command -v yq >/dev/null 2>&1; then
        image="$(printf '%s\n' "$manifests" \
            | yq e 'select(.kind == "Deployment") | .spec.template.spec.containers[0].image' - 2>/dev/null \
            | grep -v '^null$' | head -1)"
    fi
    if [[ -z "$image" ]]; then
        printf 'unknown'
        return 0
    fi
    deploy.image_ref.extract_digest "$image"
}

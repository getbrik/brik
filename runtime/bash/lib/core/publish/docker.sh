#!/usr/bin/env bash
# @module publish.docker
# @requires docker
# @description Push Docker images to a container registry.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_PUBLISH_DOCKER_LOADED:-}" ]] && return 0
_BRIK_CORE_PUBLISH_DOCKER_LOADED=1

# Push Docker image to a container registry.
# Usage: publish.docker.run [--image <name>] [--registry <url>]
#        [--tags <tag1,tag2>] [--username-var <VAR>] [--password-var <VAR>]
#        [--dry-run]
# Reads defaults from BRIK_PUBLISH_DOCKER_* environment variables.
publish.docker.run() {
    local image="${BRIK_PUBLISH_DOCKER_IMAGE:-}"
    local registry="${BRIK_PUBLISH_DOCKER_REGISTRY:-}"
    local tags="${BRIK_PUBLISH_DOCKER_TAGS:-}"
    local username_var="${BRIK_PUBLISH_DOCKER_USERNAME_VAR:-}"
    local password_var="${BRIK_PUBLISH_DOCKER_PASSWORD_VAR:-}"
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image) image="$2"; shift 2 ;;
            --registry) registry="$2"; shift 2 ;;
            --tags) tags="$2"; shift 2 ;;
            --username-var) username_var="$2"; shift 2 ;;
            --password-var) password_var="$2"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            --target) shift 2 ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    if [[ -z "$image" ]]; then
        log.error "docker image name is required (--image or publish.docker.image in brik.yml)"
        return 2
    fi

    runtime.require_tool docker || return 3

    # Default tags to BRIK_VERSION if not specified
    if [[ -z "$tags" ]]; then
        tags="${BRIK_VERSION:-latest}"
    fi

    # Isolate credentials in a temporary directory
    local _docker_config_dir=""
    if [[ -n "$username_var" && -n "$password_var" ]]; then
        _docker_config_dir="$(mktemp -d)"
        export DOCKER_CONFIG="$_docker_config_dir"

        _publish._require_secret_var "$username_var" "docker username" || return $?
        _publish._require_secret_var "$password_var" "docker password" || return $?

        local login_registry="${registry:-}"

        if [[ "$dry_run" == "true" ]]; then
            log.info "[dry-run] docker login ${login_registry:+"$login_registry"}"
        else
            log.info "logging in to registry${registry:+: $registry}"
            printf '%s' "${!password_var}" | docker login ${login_registry:+"$login_registry"} \
                --username "${!username_var}" --password-stdin || {
                log.error "docker login failed"
                rm -rf "$_docker_config_dir"
                unset DOCKER_CONFIG
                return 5
            }
        fi
    fi

    # Tag and push for each tag
    local old_ifs="${IFS}"
    IFS=','
    local tag
    for tag in $tags; do
        IFS="${old_ifs}"
        local full_image="${image}:${tag}"

        if [[ "$dry_run" == "true" ]]; then
            log.info "[dry-run] docker push $full_image"
        else
            log.info "pushing image: $full_image"
            docker push "$full_image" || {
                log.error "docker push failed for $full_image"
                return 5
            }
        fi
    done
    IFS="${old_ifs}"

    # Clean up credentials
    if [[ -n "$_docker_config_dir" ]]; then
        docker logout ${registry:+"$registry"} >/dev/null 2>&1 || true
        rm -rf "$_docker_config_dir"
        unset DOCKER_CONFIG
    fi

    log.info "docker publish completed successfully"
    return 0
}

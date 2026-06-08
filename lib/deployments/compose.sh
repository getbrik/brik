#!/usr/bin/env bash
# @module deploy.compose
# @requires docker
# @description Deploy via Docker Compose, locally or remotely over SSH.

# Guard against double-sourcing
[[ -n "${_BRIK_DEPLOYMENTS_COMPOSE_LOADED:-}" ]] && return 0
_BRIK_DEPLOYMENTS_COMPOSE_LOADED=1

# Deploy using Docker Compose.
# Usage: deploy.compose.run [--namespace <project>] [--file <compose_file>]
#        [--host <host>] [--path <path>] [--dry-run]
deploy.compose.run() {
    local namespace="" compose_file="" host="" remote_path="" image_ref=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --namespace)    namespace="$2";    shift 2 ;;
            --file)         compose_file="$2"; shift 2 ;;
            --host)         host="$2";         shift 2 ;;
            --path)         remote_path="$2";  shift 2 ;;
            --image-ref)    image_ref="$2";    shift 2 ;;
            --dry-run)      dry_run="true";    shift ;;
            # Ignore deploy.run passthrough options
            --target|--env) shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -n "$remote_path" && "$remote_path" =~ \.\. ]]; then
        log.error "remote-path must not contain '..': $remote_path"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    pipeline.require_tool docker || return "$BRIK_EXIT_MISSING_DEP"

    # Authenticate to container registry if credentials are provided
    if [[ -n "${BRIK_REGISTRY_HOST:-}" && -n "${BRIK_REGISTRY_USER:-}" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            log.info "[dry-run] docker login ${BRIK_REGISTRY_HOST}"
        else
            log.info "logging in to registry: ${BRIK_REGISTRY_HOST}"
            printf '%s' "${BRIK_REGISTRY_PASSWORD:-}" | docker login "$BRIK_REGISTRY_HOST" \
                -u "$BRIK_REGISTRY_USER" --password-stdin || {
                log.warn "docker login failed for ${BRIK_REGISTRY_HOST} (continuing anyway)"
            }
        fi
    fi

    # Determine compose file: --file or auto-detect (compose.yaml > docker-compose.yml)
    if [[ -z "$compose_file" ]]; then
        if [[ -f "compose.yaml" ]]; then
            compose_file="compose.yaml"
        else
            compose_file="docker-compose.yml"
        fi
    fi

    # Use namespace as project name
    local project_name="${namespace:-}"

    # Make image tag available for compose variable substitution
    export IMAGE_TAG="${BRIK_APP_VERSION:-${BRIK_COMMIT_SHORT_SHA:-latest}}"

    # When a digest-pinned ref is supplied, expose it as IMAGE_REF so a compose
    # file written as `image: ${IMAGE_REF}` pulls exactly that digest.
    if [[ -n "$image_ref" ]]; then
        brik.use deployments._image_ref
        if ! deploy.image_ref.is_pinned "$image_ref"; then
            log.error "refusing a non-digest-pinned image ref: ${image_ref}"
            return "$BRIK_EXIT_INVALID_INPUT"
        fi
        # compose substitutes IMAGE_REF at runtime; it does not rewrite the
        # file. If the file never references it, the resolved digest would be
        # silently dropped and a mutable tag deployed instead. Fail closed so a
        # pinned deploy never degrades into an unpinned one.
        if ! grep -q 'IMAGE_REF' "$compose_file" 2>/dev/null; then
            log.error "compose file '${compose_file}' does not reference \${IMAGE_REF}; the pinned digest would be ignored"
            return "$BRIK_EXIT_INVALID_INPUT"
        fi
        export IMAGE_REF="$image_ref"
    fi

    if [[ -n "$host" ]]; then
        # Reuse SSH agent setup from transverse helper
        brik.use transverse.ssh
        transverse.ssh.setup_agent
        local strict_host="${BRIK_SSH_STRICT_HOST_KEY:-yes}"
        local -a ssh_opts=(-o BatchMode=yes -o "StrictHostKeyChecking=${strict_host}")
        # Remote deploy via SSH
        if [[ "$dry_run" == "true" ]]; then
            log.info "[dry-run] would scp ${compose_file} to ${host}:${remote_path}/"
            log.info "[dry-run] would ssh $host: cd $remote_path && docker compose -p $project_name up -d"
        else
            log.info "copying compose file to remote: ${host}:${remote_path}/"
            scp "${ssh_opts[@]}" "$compose_file" "${host}:${remote_path}/" || {
                log.error "scp failed"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
            log.info "running docker compose on remote: $host"
            local _ssh_exit=0
            ssh "${ssh_opts[@]}" "$host" bash -s -- "$remote_path" "$project_name" "$IMAGE_TAG" "${IMAGE_REF:-}" <<'ENDSSH' || _ssh_exit=$?
set -euo pipefail
export IMAGE_TAG="$3"
[ -n "$4" ] && export IMAGE_REF="$4"
cd "$1" || exit 1
docker compose -p "$2" up -d
ENDSSH
            if [[ "$_ssh_exit" -ne 0 ]]; then
                log.error "remote docker compose failed"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            fi
        fi
    else
        # Local deploy
        local -a cmd=(docker compose -f "$compose_file")
        [[ -n "$project_name" ]] && cmd+=(-p "$project_name")
        cmd+=(up -d)

        if [[ "$dry_run" == "true" ]]; then
            log.info "[dry-run] ${cmd[*]}"
        else
            log.info "running: ${cmd[*]}"
            "${cmd[@]}" || {
                log.error "docker compose failed"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
        fi
    fi

    log.info "compose deployment completed successfully"
    return 0
}

# Read back the digest of the image a running compose service was created from.
# Reads the container's Config.Image, which preserves the exact ref used to
# create it (so a service started from registry/app@sha256:X reports that ref).
# Usage: deploy.compose.get_deployed_digest --service <name> [--project <name>]
# Output: "sha256:<hex>" when pinned, else "unknown" (also when not running).
# Returns: 2 invalid input; 3 docker missing; 5 docker query failed.
deploy.compose.get_deployed_digest() {
    local service="" project=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --service) service="$2"; shift 2 ;;
            --project) project="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$service" ]]; then
        log.error "service name is required (--service)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    pipeline.require_tool docker || return "$BRIK_EXIT_MISSING_DEP"
    brik.use deployments._image_ref

    local -a psc=(docker compose)
    [[ -n "$project" ]] && psc+=(-p "$project")
    psc+=(ps -q "$service")

    local cid
    cid="$("${psc[@]}" 2>/dev/null)" || {
        log.error "docker compose ps failed for service: ${service}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }
    if [[ -z "$cid" ]]; then
        printf 'unknown'
        return 0
    fi

    local image
    image="$(docker inspect --format '{{.Config.Image}}' "$cid" 2>/dev/null)" || {
        log.error "docker inspect failed for container: ${cid}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }
    deploy.image_ref.extract_digest "$image"
}

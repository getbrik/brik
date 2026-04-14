#!/usr/bin/env bash
# @module deploy.compose
# @requires docker
# @description Deploy via Docker Compose, locally or remotely over SSH.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_DEPLOY_COMPOSE_LOADED:-}" ]] && return 0
_BRIK_CORE_DEPLOY_COMPOSE_LOADED=1

# Deploy using Docker Compose.
# Usage: deploy.compose.run [--namespace <project>] [--file <compose_file>]
#        [--host <host>] [--path <path>] [--dry-run]
deploy.compose.run() {
    local namespace="" compose_file="" host="" remote_path=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --namespace)    namespace="$2";    shift 2 ;;
            --file)         compose_file="$2"; shift 2 ;;
            --host)         host="$2";         shift 2 ;;
            --path)         remote_path="$2";  shift 2 ;;
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

    runtime.require_tool docker || return "$BRIK_EXIT_MISSING_DEP"

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

    if [[ -n "$host" ]]; then
        # Reuse SSH agent setup from ssh module
        if declare -f _deploy.ssh.setup_agent >/dev/null 2>&1; then
            _deploy.ssh.setup_agent
        fi
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
            ssh "${ssh_opts[@]}" "$host" bash -s -- "$remote_path" "$project_name" "$IMAGE_TAG" <<'ENDSSH' || _ssh_exit=$?
set -euo pipefail
export IMAGE_TAG="$3"
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

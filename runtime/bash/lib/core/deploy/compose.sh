#!/usr/bin/env bash
# @module deploy.compose
# @requires docker
# @description Deploy via Docker Compose, locally or remotely over SSH.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_DEPLOY_COMPOSE_LOADED:-}" ]] && return 0
_BRIK_CORE_DEPLOY_COMPOSE_LOADED=1

# Deploy using Docker Compose.
# Usage: deploy.compose.run [--namespace <project>] [--compose-file <file>]
#        [--host <host>] [--remote-path <path>] [--dry-run]
deploy.compose.run() {
    local namespace="" compose_file="" host="" remote_path=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --namespace)    namespace="$2";    shift 2 ;;
            --compose-file) compose_file="$2"; shift 2 ;;
            --host)         host="$2";         shift 2 ;;
            --remote-path)  remote_path="$2";  shift 2 ;;
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

    # Determine compose file: --compose-file or default
    if [[ -z "$compose_file" ]]; then
        compose_file="docker-compose.yml"
    fi

    # Use namespace as project name
    local project_name="${namespace:-}"

    if [[ -n "$host" ]]; then
        local -a ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=yes)
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
            ssh "${ssh_opts[@]}" "$host" bash -s -- "$remote_path" "$project_name" <<'ENDSSH' || _ssh_exit=$?
set -euo pipefail
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

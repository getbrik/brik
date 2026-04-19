#!/usr/bin/env bash
# @module deploy.ssh
# @requires rsync ssh
# @description Deploy via rsync over SSH, with optional remote restart command.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_DEPLOY_SSH_LOADED:-}" ]] && return 0
_BRIK_CORE_DEPLOY_SSH_LOADED=1

# Deploy files via rsync over SSH.
# Usage: deploy.ssh.run --host <host> --path <remote_path>
#        [--source <local_path>] [--restart-cmd <cmd>] [--dry-run]
deploy.ssh.run() {
    local host="" remote_path="" restart_cmd="" source=""
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host)         host="$2";         shift 2 ;;
            --path)         remote_path="$2";  shift 2 ;;
            --restart-cmd)  restart_cmd="$2";  shift 2 ;;
            --source)       source="$2";       shift 2 ;;
            --dry-run)      dry_run="true";    shift ;;
            # Ignore deploy.run passthrough options
            --target|--env) shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    if [[ -z "$host" ]]; then
        log.error "host is required (--host)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ -z "$remote_path" ]]; then
        log.error "path is required (--path)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    runtime.require_tool rsync || return "$BRIK_EXIT_MISSING_DEP"
    runtime.require_tool ssh   || return "$BRIK_EXIT_MISSING_DEP"

    # Setup SSH agent with key from SSH_PRIVATE_KEY if available
    _deploy.ssh.setup_agent

    local strict_host="${BRIK_SSH_STRICT_HOST_KEY:-yes}"
    local -a ssh_opts=(-o BatchMode=yes -o "StrictHostKeyChecking=${strict_host}")

    # Determine source files: --source or current directory
    local src="${source:-.}"

    # Build rsync command
    local -a rsync_cmd=(rsync -avz --delete -e "ssh ${ssh_opts[*]}")
    [[ "$dry_run" == "true" ]] && rsync_cmd+=(--dry-run)
    rsync_cmd+=("${src}/" "${host}:${remote_path}/")

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] ${rsync_cmd[*]}"
    else
        log.info "running: ${rsync_cmd[*]}"
    fi

    "${rsync_cmd[@]}" || {
        log.error "rsync failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    # Execute restart command via ssh if provided
    if [[ -n "$restart_cmd" ]]; then
        # restart_cmd is trusted input from brik.yml - validated for basic safety
        local _unsafe_chars
        _unsafe_chars="$(printf '%s' "$restart_cmd" | tr -d "[:alnum:][:blank:]._/='\"\\-")"
        if [[ -n "$_unsafe_chars" ]] || [[ "$restart_cmd" =~ $'\n'|$'\r' ]]; then
            log.error "restart-cmd contains unsafe characters: use simple commands only"
            return "$BRIK_EXIT_INVALID_INPUT"
        fi
        if [[ "$dry_run" == "true" ]]; then
            log.info "[dry-run] would ssh ${host} -- ${restart_cmd}"
        else
            log.info "restarting service on ${host}: ${restart_cmd}"
            ssh "${ssh_opts[@]}" "$host" "$restart_cmd" || {
                log.error "remote restart command failed"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
        fi
    fi

    log.info "ssh deployment completed successfully"
    return 0
}

# Setup ssh-agent with SSH_PRIVATE_KEY if available.
# SSH_PRIVATE_KEY can be a file path (GitLab file variable) or inline key content.
# Idempotent: skips if agent is already running with identities.
_deploy.ssh.setup_agent() {
    # Skip if no key configured
    [[ -z "${SSH_PRIVATE_KEY:-}" ]] && return 0

    # Skip if agent already has identities
    if ssh-add -l &>/dev/null; then
        return 0
    fi

    # Start agent if not running
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        eval "$(ssh-agent -s 2>/dev/null)"
        log.info "ssh-agent started"
    fi

    # Add the key: SSH_PRIVATE_KEY may be a file path (GitLab file variable)
    if [[ -f "$SSH_PRIVATE_KEY" ]]; then
        local _key_file
        _key_file="$(mktemp)"
        cp "$SSH_PRIVATE_KEY" "$_key_file"
        # Ensure trailing newline (required by OpenSSH)
        [[ -s "$_key_file" && "$(tail -c1 "$_key_file" | wc -l)" -eq 0 ]] && printf '\n' >> "$_key_file"
        chmod 600 "$_key_file"
        ssh-add "$_key_file" 2>/dev/null || {
            log.warn "failed to add SSH key from file: $(ssh-add "$_key_file" 2>&1)"
            rm -f "$_key_file"
            return 0
        }
        rm -f "$_key_file"
    else
        # Inline key content
        ssh-add - <<< "$SSH_PRIVATE_KEY" 2>/dev/null || {
            log.warn "failed to add inline SSH key"
            return 0
        }
    fi
    log.info "SSH key loaded into agent"
}

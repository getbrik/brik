#!/usr/bin/env bash
# @module transverse.ssh
# @description SSH agent setup and per-host transport options shared between
#   deploy targets. Host keys and the strict-host-key stance come from the
#   SshTarget the referential declares for the host, never from an env flag.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_SSH_LOADED:-}" ]] && return 0
_BRIK_MODULE_SSH_LOADED=1

# transverse.ssh.host_opts - append the transport options the referential's
# SshTarget declares for <host> to the named ssh-options array. Strict
# host-key checking is the default; opting out requires an explicit
# strict_host_key: false declaration (legal but noisy). A declared
# known_hosts reference is materialized under the log dir when it is not
# already a file. An undeclared host fails closed.
# Usage: transverse.ssh.host_opts <array_name> <host>
transverse.ssh.host_opts() {
    local -n _ssh_opts="$1"
    local host="$2"

    brik.use transverse.infra

    local target
    target="$(infra.ssh_target_for "$host")" || return "$?"

    # Connection identity declared on the SshTarget. Applied as ssh -o options
    # (so they reach both the rsync transport and a direct ssh restart) and
    # before the host-key stance below, so they hold even when strict checking
    # is opted out. Absent fields leave ssh's own defaults in place.
    local _user _port
    _user="$(printf '%s' "$target" | jq -r '.user // ""')"
    _port="$(printf '%s' "$target" | jq -r '.port // ""')"
    [[ -n "$_user" ]] && _ssh_opts+=(-o "User=${_user}")
    [[ -n "$_port" ]] && _ssh_opts+=(-o "Port=${_port}")

    # jq's // treats false as empty, so probe the opt-out with an explicit
    # equality test instead of a default.
    if [[ "$(printf '%s' "$target" | jq -r 'if .strict_host_key == false then "false" else "true" end')" == "false" ]]; then
        log.warn "ssh host '${host}' is declared with strict_host_key: false (legal but insecure)"
        _ssh_opts+=(-o StrictHostKeyChecking=no)
        return 0
    fi

    _ssh_opts+=(-o StrictHostKeyChecking=yes)

    local kh_ref
    kh_ref="$(printf '%s' "$target" | jq -r '.known_hosts // ""')"
    if [[ -n "$kh_ref" ]]; then
        local kh_path
        case "$kh_ref" in
            file://*)
                kh_path="${kh_ref#file://}"
                if [[ "$kh_path" != /* ]]; then
                    local root
                    root="$(infra.root)" || return "$?"
                    kh_path="${root}/${kh_path}"
                fi
                ;;
            *)
                local value
                value="$(infra.resolve_ref "$kh_ref")" || return "$?"
                kh_path="${BRIK_LOG_DIR:-.brik-logs}/ssh_known_hosts"
                mkdir -p "$(dirname "$kh_path")" || return "$BRIK_EXIT_IO_FAILURE"
                printf '%s\n' "$value" > "$kh_path"
                ;;
        esac
        _ssh_opts+=(-o "UserKnownHostsFile=${kh_path}")
    fi
    return 0
}

# transverse.ssh.setup_agent - start ssh-agent and load SSH_PRIVATE_KEY.
# Reads SSH_PRIVATE_KEY from the environment. The value may be either a path
# to a file (GitLab file variable pattern) or inline key material.
# Idempotent: returns 0 if no key is configured, if the agent already has
# identities, or after successfully loading the key.
# Usage: transverse.ssh.setup_agent
transverse.ssh.setup_agent() {
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
        # Guarantee deletion even if the process is interrupted after mktemp
        # but before the explicit rm below (key material would otherwise leak).
        trap 'rm -f "$_key_file"' EXIT INT TERM
        cp "$SSH_PRIVATE_KEY" "$_key_file"
        # Ensure trailing newline (required by OpenSSH)
        [[ -s "$_key_file" && "$(tail -c1 "$_key_file" | wc -l)" -eq 0 ]] && printf '\n' >> "$_key_file"
        chmod 600 "$_key_file"
        ssh-add "$_key_file" 2>/dev/null || {
            log.warn "failed to add SSH key from file: $(ssh-add "$_key_file" 2>&1)"
            rm -f "$_key_file"
            trap - EXIT INT TERM
            return 0
        }
        rm -f "$_key_file"
        trap - EXIT INT TERM
    else
        # Inline key content
        ssh-add - <<< "$SSH_PRIVATE_KEY" 2>/dev/null || {
            log.warn "failed to add inline SSH key"
            return 0
        }
    fi
    log.info "SSH key loaded into agent"
}

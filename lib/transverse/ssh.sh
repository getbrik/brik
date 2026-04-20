#!/usr/bin/env bash
# @module transverse.ssh
# @description SSH agent setup helper shared between deploy targets.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_SSH_LOADED:-}" ]] && return 0
_BRIK_MODULE_SSH_LOADED=1

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

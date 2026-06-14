#!/usr/bin/env bash
# @module cli.self_update
# @description CLI entrypoint for "brik self-update". Delegates to brew or git
#   depending on install method; refuses when the tree is dirty.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_SELF_UPDATE_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_SELF_UPDATE_LOADED=1

# cli.self_update.run - parse CLI args and run the update.
# Usage: cli.self_update.run [--channel stable|edge] [--version <tag>]
cli.self_update.run() {
    brik.use cli.helpers

    local channel="stable"
    local target_version=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --channel)
                brik_require_arg "--channel" "${2-}" || return "$?"
                channel="$2"
                shift 2
                ;;
            --version)
                brik_require_arg "--version" "${2-}" || return "$?"
                target_version="$2"
                shift 2
                ;;
            -h|--help)
                brik_print_verb_help self-update
                return 0
                ;;
            *)
                brik_usage_error "unknown option: $1" || return "$?"
                ;;
        esac
    done

    case "${channel}" in
        stable|edge) ;;
        *)
            brik_error "invalid channel: ${channel}"
            brik_error "Supported channels: stable, edge"
            return "${BRIK_EXIT_INVALID_INPUT}"
            ;;
    esac

    local method=""
    method="$(_brik_detect_install_method)"

    case "${method}" in
        git)
            _cli.self_update._git "${channel}" "${target_version}"
            ;;
        brew)
            brik_print "updating via Homebrew..."
            brew upgrade getbrik/tap/brik
            ;;
        *)
            brik_error "cannot self-update: unknown installation method"
            brik_error "reinstall with: curl -fsSL https://raw.githubusercontent.com/getbrik/brik/main/scripts/install.sh | bash"
            return "${BRIK_EXIT_INVALID_INPUT}"
            ;;
    esac

    brik_print ""
    brik_print "update complete"
    local new_version=""
    new_version="$("${BRIK_HOME}/bin/brik" version 2>/dev/null | head -n 1)" || true
    if [[ -n "${new_version}" ]]; then
        brik_print "${new_version}"
    fi
}

# Git-based update: fetch + checkout tag/branch. Refuses if tree is dirty.
_cli.self_update._git() {
    local channel="$1"
    local target_version="$2"

    if [[ ! -d "${BRIK_HOME}/.git" ]]; then
        brik_error "not a git installation: ${BRIK_HOME}"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi

    if [[ -n "$(git -C "${BRIK_HOME}" status --porcelain 2>/dev/null)" ]]; then
        brik_error "working tree is dirty in ${BRIK_HOME}"
        brik_hint "do not modify files in ${BRIK_HOME} manually"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi

    local git_output=""

    brik_print "fetching updates..."
    if ! git_output="$(git -C "${BRIK_HOME}" fetch --tags origin 2>&1)"; then
        brik_error "failed to fetch from remote"
        printf '%s\n' "${git_output}" >&2
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi

    if [[ -n "${target_version}" ]]; then
        brik_print "switching to ${target_version}..."
        if ! git_output="$(git -C "${BRIK_HOME}" checkout "${target_version}" 2>&1)"; then
            brik_error "version ${target_version} not found"
            printf '%s\n' "${git_output}" >&2
            return "${BRIK_EXIT_INVALID_INPUT}"
        fi
    elif [[ "${channel}" == "edge" ]]; then
        brik_print "switching to edge (main branch)..."
        git -C "${BRIK_HOME}" checkout main 2>/dev/null || true
        if ! git_output="$(git -C "${BRIK_HOME}" pull --ff-only origin main 2>&1)"; then
            brik_error "failed to pull latest changes"
            printf '%s\n' "${git_output}" >&2
            return "${BRIK_EXIT_INVALID_INPUT}"
        fi
    else
        local latest=""
        latest="$(git -C "${BRIK_HOME}" describe --tags --abbrev=0 origin/main 2>/dev/null)" || true
        if [[ -z "${latest}" ]]; then
            brik_error "no tags found - try: brik self-update --channel edge"
            return "${BRIK_EXIT_INVALID_INPUT}"
        fi
        brik_print "switching to ${latest}..."
        if ! git_output="$(git -C "${BRIK_HOME}" checkout "${latest}" 2>&1)"; then
            brik_error "failed to checkout ${latest}"
            printf '%s\n' "${git_output}" >&2
            return "${BRIK_EXIT_INVALID_INPUT}"
        fi
    fi
}

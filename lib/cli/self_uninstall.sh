#!/usr/bin/env bash
# @module cli.self_uninstall
# @description CLI entrypoint for "brik self-uninstall". Removes shims from
#   /usr/local/bin and ~/.local/bin, then rm -rf's $BRIK_HOME with guards.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_SELF_UNINSTALL_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_SELF_UNINSTALL_LOADED=1

# cli.self_uninstall.run - parse CLI args and uninstall.
# Usage: cli.self_uninstall.run [--force]
cli.self_uninstall.run() {
    brik.use cli.helpers

    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=true; shift ;;
            *) brik_usage_error "unknown option: $1" || return "$?" ;;
        esac
    done

    if [[ "${force}" != true ]]; then
        printf 'Are you sure? This will remove Brik from your system. [y/N] '
        local answer=""
        read -r answer
        case "${answer}" in
            y|Y|yes|YES) ;;
            *)
                brik_print "cancelled"
                return "${BRIK_EXIT_OK}"
                ;;
        esac
    fi

    for candidate in "/usr/local/bin/brik" "${HOME}/.local/bin/brik"; do
        if [[ -f "${candidate}" || -L "${candidate}" ]]; then
            brik_print "removing: ${candidate}"
            rm -f "${candidate}" 2>/dev/null || {
                brik_error "failed to remove ${candidate} - try with sudo"
            }
        fi
    done

    local home_to_remove="${BRIK_HOME}"
    if [[ -z "${home_to_remove}" || "${home_to_remove}" == "/" ]]; then
        brik_error "refusing to remove suspicious path: ${home_to_remove}"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi
    if [[ ! -f "${home_to_remove}/bin/brik" ]]; then
        brik_error "path does not look like a brik installation: ${home_to_remove}"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi

    brik_print "removing runtime: ${home_to_remove}"
    rm -rf "${home_to_remove}"
    brik_print ""
    brik_print "brik has been removed"
}

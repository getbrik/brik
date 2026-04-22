#!/usr/bin/env bash
# @module cli.version
# @description CLI entrypoint for "brik version".

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_VERSION_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_VERSION_LOADED=1

# cli.version.run - print Brik version info.
# Usage: cli.version.run [--verbose]
cli.version.run() {
    brik.use cli.helpers

    local verbose=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose) verbose=true; shift ;;
            *) brik_usage_error "unknown option: $1" || return "$?" ;;
        esac
    done

    brik_print "brik ${BRIK_VERSION}"
    brik_print "schema: ${BRIK_SCHEMA_VERSION}"
    brik_print "runtime: ${BRIK_RUNTIME}"

    if [[ "${verbose}" == true ]]; then
        brik_print "home: ${BRIK_HOME}"
        brik_print "install: $(_brik_detect_install_method)"
        local commit_sha=""
        commit_sha="$(git -C "${BRIK_HOME}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
        brik_print "commit: ${commit_sha}"
    fi
}

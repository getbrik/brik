#!/usr/bin/env bash
# @module git
# @requires git
# @description Git automation functions for brik-lib.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_GIT_LOADED:-}" ]] && return 0
_BRIK_CORE_GIT_LOADED=1

# Create a git tag.
# Usage: git.tag <tag_name> [--message <msg>] [--push] [--dry-run]
git.tag() {
    local tag_name="$1"
    shift
    local message="" push=false dry_run="${BRIK_DRY_RUN:-false}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --message) message="$2"; shift 2 ;;
            --push) push=true; shift ;;
            --dry-run) dry_run=true; shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    runtime.require_tool git || return "$BRIK_EXIT_MISSING_DEP"

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] git tag ${message:+-m \"$message\"} \"$tag_name\""
        [[ "$push" == "true" ]] && log.info "[dry-run] git push origin \"$tag_name\""
        return 0
    fi

    if [[ -n "$message" ]]; then
        git tag -a "$tag_name" -m "$message" || {
            log.error "failed to create tag: $tag_name"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        }
    else
        git tag "$tag_name" || {
            log.error "failed to create tag: $tag_name"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        }
    fi

    if [[ "$push" == "true" ]]; then
        git push origin "$tag_name" || {
            log.error "failed to push tag: $tag_name"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        }
    fi

    log.info "tag created: $tag_name"
    return 0
}

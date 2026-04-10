#!/usr/bin/env bash
# @module git
# @requires git
# @description Git automation functions for brik-lib.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_GIT_LOADED:-}" ]] && return 0
_BRIK_CORE_GIT_LOADED=1

# Configure git user identity. Idempotent.
# Usage: git.configure [--name <name>] [--email <email>]
git.configure() {
    local name="" email=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --email) email="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    runtime.require_tool git || return "$BRIK_EXIT_MISSING_DEP"

    if [[ "${BRIK_DRY_RUN:-false}" == "true" ]]; then
        [[ -n "$name" ]] && log.info "[dry-run] git config user.name '$name'"
        [[ -n "$email" ]] && log.info "[dry-run] git config user.email '$email'"
        return 0
    fi

    if [[ -n "$name" ]]; then
        git config user.name "$name" || {
            log.error "failed to set git user.name"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        }
    fi
    if [[ -n "$email" ]]; then
        git config user.email "$email" || {
            log.error "failed to set git user.email"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        }
    fi
    return 0
}

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

# Output git repository information as JSON.
# Usage: git.info
git.info() {
    runtime.require_tool git || return "$BRIK_EXIT_MISSING_DEP"

    local sha short_sha branch author message timestamp
    sha="$(git rev-parse HEAD 2>/dev/null)" || { log.error "not a git repository"; return "$BRIK_EXIT_EXTERNAL_FAIL"; }
    short_sha="$(git rev-parse --short HEAD 2>/dev/null)" || short_sha=""
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || branch=""
    author="$(git log -1 --format='%an' 2>/dev/null)" || author=""
    message="$(git log -1 --format='%s' 2>/dev/null)" || message=""
    timestamp="$(git log -1 --format='%aI' 2>/dev/null)" || timestamp=""

    if command -v jq >/dev/null 2>&1; then
        jq -n \
            --arg sha "$sha" \
            --arg short_sha "$short_sha" \
            --arg branch "$branch" \
            --arg author "$author" \
            --arg message "$message" \
            --arg timestamp "$timestamp" \
            '{sha: $sha, short_sha: $short_sha, branch: $branch, author: $author, message: $message, timestamp: $timestamp}'
    else
        printf '{"sha":"%s","short_sha":"%s","branch":"%s","author":"%s","message":"%s","timestamp":"%s"}\n' \
            "$sha" "$short_sha" "$branch" "$author" "$message" "$timestamp"
    fi
    return 0
}

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

    pipeline.require_tool git || return "$BRIK_EXIT_MISSING_DEP"

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

# transverse.git.commit_all - stage all changes and commit with a message.
# By default returns 0 with a log message when the working tree is clean
# (callers typically want idempotent GitOps commits). Pass --fail-if-empty to
# treat a clean tree as an error (release pipelines, etc.).
# The "no changes" case is detected via git status --porcelain rather than
# guessing at git commit exit codes, so real commit failures surface cleanly.
# Usage: transverse.git.commit_all <message>
#        [-C <dir>] [--email <email>] [--name <name>] [--fail-if-empty]
transverse.git.commit_all() {
    local message="$1"
    shift
    local dir="" email="" name="" fail_if_empty=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -C) dir="$2"; shift 2 ;;
            --email) email="$2"; shift 2 ;;
            --name) name="$2"; shift 2 ;;
            --fail-if-empty) fail_if_empty=true; shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    local git_base=(git)
    [[ -n "$dir" ]] && git_base=(git -C "$dir")

    "${git_base[@]}" add -A >/dev/null 2>&1 || {
        log.error "git add failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    if [[ -z "$("${git_base[@]}" status --porcelain 2>/dev/null)" ]]; then
        if [[ "$fail_if_empty" == "true" ]]; then
            log.error "git commit failed: working tree has no changes"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        fi
        log.info "no changes to commit"
        return 0
    fi

    local commit_cmd=("${git_base[@]}")
    [[ -n "$email" ]] && commit_cmd+=(-c "user.email=$email")
    [[ -n "$name" ]] && commit_cmd+=(-c "user.name=$name")
    commit_cmd+=(commit -q -m "$message")

    local commit_err rc=0
    commit_err="$("${commit_cmd[@]}" 2>&1 >/dev/null)" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        log.error "git commit failed: ${commit_err}"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi
    return 0
}

# transverse.git.clone_shallow - clone a repository with a bounded history.
# Always sets GIT_TERMINAL_PROMPT=0 to fail fast on auth prompts.
# Usage: transverse.git.clone_shallow <url> <dest> [--branch <b>] [--depth <n>]
transverse.git.clone_shallow() {
    local url="$1" dest="$2"
    shift 2
    local branch="" depth="1"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --branch) branch="$2"; shift 2 ;;
            --depth) depth="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    local args=(clone --depth "$depth")
    [[ -n "$branch" ]] && args+=(--branch "$branch")
    args+=("$url" "$dest")

    GIT_TERMINAL_PROMPT=0 git "${args[@]}" >/dev/null 2>&1 || {
        log.error "git clone failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }
    return 0
}

# transverse.git.push_branch - push a branch (current by default) to origin.
# Sets GIT_TERMINAL_PROMPT=0. Credentials embedded in the remote URL are
# redacted from error logs.
# Usage: transverse.git.push_branch [<branch>] [-C <dir>] [--force] [--dry-run]
transverse.git.push_branch() {
    local branch="" dir="" force=false dry_run="${BRIK_DRY_RUN:-false}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -C) dir="$2"; shift 2 ;;
            --force) force=true; shift ;;
            --dry-run) dry_run=true; shift ;;
            --) shift; break ;;
            -*) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
            *) branch="$1"; shift ;;
        esac
    done

    local git_base=(git)
    [[ -n "$dir" ]] && git_base=(git -C "$dir")

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] git push ${force:+--force }origin ${branch:-HEAD}"
        return 0
    fi

    local push_cmd=("${git_base[@]}" push)
    [[ "$force" == "true" ]] && push_cmd+=(--force)
    if [[ -n "$branch" ]]; then
        push_cmd+=(origin "$branch")
    else
        push_cmd+=(origin HEAD)
    fi

    local push_err
    if ! push_err="$(GIT_TERMINAL_PROMPT=0 "${push_cmd[@]}" 2>&1)"; then
        local safe_err
        safe_err="$(printf '%s' "$push_err" | sed 's|://[^@]*@|://***@|')"
        log.error "git push failed: $safe_err"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi
    return 0
}

# transverse.git.latest_tag - print the most recent tag (reachable from HEAD).
# Optionally filter by a glob pattern. Returns non-zero when no tag matches
# or when the current directory is not a git repo. Underlying git stderr is
# logged at debug level so callers can distinguish "no tags" from other
# failure modes (e.g. not a git repo).
# Usage: transverse.git.latest_tag [--pattern <glob>]
transverse.git.latest_tag() {
    local pattern=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pattern) pattern="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    local args=(describe --tags --abbrev=0)
    [[ -n "$pattern" ]] && args+=(--match "$pattern")

    local tag
    if tag="$(git "${args[@]}" 2>/dev/null)"; then
        printf '%s' "$tag"
        return 0
    fi
    log.debug "latest_tag: $(git "${args[@]}" 2>&1 >/dev/null || true)"
    return 1
}

# transverse.git.current_branch - print the name of the current branch.
# Usage: transverse.git.current_branch
transverse.git.current_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null
}

# transverse.git.short_sha - print the 7-char short SHA of a ref (HEAD default).
# Usage: transverse.git.short_sha [<ref>]
transverse.git.short_sha() {
    local ref="${1:-HEAD}"
    git rev-parse --short=7 "$ref" 2>/dev/null
}

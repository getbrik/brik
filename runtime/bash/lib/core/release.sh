#!/usr/bin/env bash
# @module release
# @requires git
# @description Release orchestration - changelog, version write, git tag.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_RELEASE_LOADED:-}" ]] && return 0
_BRIK_CORE_RELEASE_LOADED=1

# Prepare a release: generate changelog, write version, create commit.
# Usage: release.prepare <version> [--changelog] [--changelog-file <path>]
#        [--dry-run]
release.prepare() {
    local version="$1"
    shift || true
    local generate_changelog="false"
    local changelog_file="${BRIK_RELEASE_CHANGELOG_FILE:-CHANGELOG.md}"
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --changelog) generate_changelog="true"; shift ;;
            --changelog-file) changelog_file="$2"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    if [[ -z "$version" ]]; then
        log.error "version is required"
        return 2
    fi

    brik.use version
    version.validate "$version" || return 2

    runtime.require_tool git || return 3

    # Generate changelog if requested
    if [[ "$generate_changelog" == "true" ]]; then
        brik.use changelog
        if [[ "$dry_run" == "true" ]]; then
            log.info "[dry-run] changelog.generate > $changelog_file"
        else
            log.info "generating changelog to $changelog_file"
            local changelog_content
            changelog_content="$(changelog.generate)" || return $?

            # Prepend to existing changelog or create new
            if [[ -f "$changelog_file" ]]; then
                local tmp
                tmp="$(mktemp)" || return 6
                {
                    printf '# %s\n\n' "$version"
                    printf '%s\n\n' "$changelog_content"
                    cat "$changelog_file"
                } > "$tmp"
                mv "$tmp" "$changelog_file" || return 6
            else
                {
                    printf '# %s\n\n' "$version"
                    printf '%s\n' "$changelog_content"
                } > "$changelog_file" || return 6
            fi
        fi
    fi

    # Write version
    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] version.write $version"
    else
        log.info "writing version: $version"
        version.write "$version" || return $?
    fi

    # Create release commit
    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] git add + commit 'release: $version'"
    else
        git add -A >/dev/null 2>&1 || {
            log.error "git add failed"
            return 5
        }
        git commit -q -m "release: $version" || {
            log.error "git commit failed"
            return 5
        }
    fi

    log.info "release prepared: $version"
    return 0
}

# Finalize a release: create annotated tag and optionally push.
# Usage: release.finalize <version> [--tag-prefix <prefix>] [--push] [--dry-run]
release.finalize() {
    local version="$1"
    shift || true
    local tag_prefix="${BRIK_RELEASE_TAG_PREFIX:-v}"
    local push=false
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tag-prefix) tag_prefix="$2"; shift 2 ;;
            --push) push=true; shift ;;
            --dry-run) dry_run="true"; shift ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    if [[ -z "$version" ]]; then
        log.error "version is required"
        return 2
    fi

    brik.use git

    local tag_name="${tag_prefix}${version}"
    local -a tag_args=("$tag_name" --message "Release $version")
    [[ "$push" == "true" ]] && tag_args+=(--push)
    [[ "$dry_run" == "true" ]] && tag_args+=(--dry-run)

    git.tag "${tag_args[@]}" || return $?

    log.info "release finalized: $tag_name"
    return 0
}

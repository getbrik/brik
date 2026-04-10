#!/usr/bin/env bash
# @module changelog
# @requires git
# @description Changelog generation from conventional commits.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_CHANGELOG_LOADED:-}" ]] && return 0
_BRIK_CORE_CHANGELOG_LOADED=1

# Conventional commit type regex
_CHANGELOG_CC_PATTERN='^(feat|fix|refactor|docs|test|chore|perf|ci|style|build|revert)(\(.+\))?(!)?:[[:space:]]+'

# Map of conventional commit types to display labels
_changelog._type_label() {
    case "$1" in
        feat)     printf 'Features' ;;
        fix)      printf 'Bug Fixes' ;;
        refactor) printf 'Refactoring' ;;
        docs)     printf 'Documentation' ;;
        test)     printf 'Tests' ;;
        chore)    printf 'Chores' ;;
        perf)     printf 'Performance' ;;
        ci)       printf 'CI' ;;
        style)    printf 'Style' ;;
        build)    printf 'Build' ;;
        revert)   printf 'Reverts' ;;
        other)    printf 'Other Changes' ;;
        *)        printf 'Other Changes' ;;
    esac
}

# Generate a changelog from git log between two refs.
# Usage: changelog.generate [--from <ref>] [--to <ref>] [--format conventional]
# Prints Markdown to stdout.
changelog.generate() {
    local from_ref="" to_ref="HEAD"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from) from_ref="$2"; shift 2 ;;
            --to) to_ref="$2"; shift 2 ;;
            --format) shift 2 ;; # accepted but only 'conventional' is supported
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    runtime.require_tool git || return "$BRIK_EXIT_MISSING_DEP"

    # Auto-detect from ref (latest tag)
    if [[ -z "$from_ref" ]]; then
        from_ref="$(git describe --tags --abbrev=0 2>/dev/null)" || {
            # No tags, use initial commit
            from_ref="$(git rev-list --max-parents=0 HEAD 2>/dev/null)" || {
                log.error "cannot determine changelog starting point"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
        }
    fi

    # Get commit log
    local log_output
    log_output="$(git log "${from_ref}..${to_ref}" --format='%H %s' 2>/dev/null)" || {
        log.error "failed to read git log from $from_ref to $to_ref"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    if [[ -z "$log_output" ]]; then
        log.info "no commits found between $from_ref and $to_ref"
        printf '## Changes\n\nNo changes.\n'
        return 0
    fi

    # Parse and group commits by type
    local -a feat_commits=() fix_commits=() refactor_commits=() docs_commits=()
    local -a test_commits=() chore_commits=() perf_commits=() ci_commits=()
    local -a style_commits=() build_commits=() revert_commits=() other_commits=()
    local -a breaking_commits=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local sha="${line%% *}"
        local short_sha="${sha:0:7}"
        local subject="${line#* }"

        # Check for breaking change indicator
        local is_breaking=""
        if [[ "$subject" =~ ^[a-z]+(\(.+\))?!: ]]; then
            is_breaking="true"
        fi

        if [[ "$subject" =~ $_CHANGELOG_CC_PATTERN ]]; then
            local cc_type="${BASH_REMATCH[1]}"
            # Remove type prefix for display
            local msg="${subject#*: }"

            local entry="- ${msg} (${short_sha})"
            [[ -n "$is_breaking" ]] && breaking_commits+=("- **BREAKING**: ${msg} (${short_sha})")

            case "$cc_type" in
                feat)     feat_commits+=("$entry") ;;
                fix)      fix_commits+=("$entry") ;;
                refactor) refactor_commits+=("$entry") ;;
                docs)     docs_commits+=("$entry") ;;
                test)     test_commits+=("$entry") ;;
                chore)    chore_commits+=("$entry") ;;
                perf)     perf_commits+=("$entry") ;;
                ci)       ci_commits+=("$entry") ;;
                style)    style_commits+=("$entry") ;;
                build)    build_commits+=("$entry") ;;
                revert)   revert_commits+=("$entry") ;;
            esac
        else
            other_commits+=("- ${subject} (${short_sha})")
        fi
    done <<< "$log_output"

    # Output Markdown
    printf '## Changes\n\n'

    # Breaking changes first
    if [[ ${#breaking_commits[@]} -gt 0 ]]; then
        printf '### BREAKING CHANGES\n\n'
        printf '%s\n' "${breaking_commits[@]}"
        printf '\n'
    fi

    # Output each section in priority order
    local type
    for type in feat fix perf refactor docs test ci style build revert chore other; do
        local -n arr="${type}_commits"
        if [[ ${#arr[@]} -gt 0 ]]; then
            printf '### %s\n\n' "$(_changelog._type_label "$type")"
            printf '%s\n' "${arr[@]}"
            printf '\n'
        fi
    done

    return 0
}

# Validate that all commits between two refs follow conventional commit format.
# Usage: changelog.validate_commits [--from <ref>] [--to <ref>]
# Returns 0 if all valid, 10 if non-conforming commits found.
changelog.validate_commits() {
    local from_ref="" to_ref="HEAD"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from) from_ref="$2"; shift 2 ;;
            --to) to_ref="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    runtime.require_tool git || return "$BRIK_EXIT_MISSING_DEP"

    if [[ -z "$from_ref" ]]; then
        from_ref="$(git describe --tags --abbrev=0 2>/dev/null)" || {
            from_ref="$(git rev-list --max-parents=0 HEAD 2>/dev/null)" || {
                log.error "cannot determine starting point"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
        }
    fi

    local log_output
    log_output="$(git log "${from_ref}..${to_ref}" --format='%s' 2>/dev/null)" || {
        log.error "failed to read git log"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    if [[ -z "$log_output" ]]; then
        return 0
    fi

    local has_errors=false
    while IFS= read -r subject; do
        [[ -z "$subject" ]] && continue
        if [[ ! "$subject" =~ $_CHANGELOG_CC_PATTERN ]]; then
            log.warn "non-conforming commit: $subject"
            has_errors=true
        fi
    done <<< "$log_output"

    if [[ "$has_errors" == "true" ]]; then
        log.error "non-conforming commits found"
        return "$BRIK_EXIT_CHECK_FAILED"
    fi

    return 0
}

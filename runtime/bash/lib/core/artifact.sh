#!/usr/bin/env bash
# @module artifact
# @requires tar
# @description Archive and extract build artefacts.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_ARTIFACT_LOADED:-}" ]] && return 0
_BRIK_CORE_ARTIFACT_LOADED=1

# Create a tar.gz archive from one or more paths.
# Usage: artifact.archive <paths...> --output <archive_path>
# Returns: 0=success, 2=invalid input, 3=tool missing, 5=command failed, 6=IO error
artifact.archive() {
    local output=""
    local -a paths=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output) output="$2"; shift 2 ;;
            *) paths+=("$1"); shift ;;
        esac
    done

    if [[ ${#paths[@]} -eq 0 ]]; then
        log.error "no paths specified for archiving"
        return 2
    fi

    if [[ -z "$output" ]]; then
        log.error "output path is required (--output)"
        return 2
    fi

    runtime.require_tool tar || return 3

    # Ensure parent directory exists
    local output_dir
    output_dir="$(dirname "$output")"
    if [[ ! -d "$output_dir" ]]; then
        mkdir -p "$output_dir" || {
            log.error "cannot create output directory: $output_dir"
            return 6
        }
    fi

    # Verify all source paths exist
    local p
    for p in "${paths[@]}"; do
        if [[ ! -e "$p" ]]; then
            log.error "source path not found: $p"
            return 6
        fi
    done

    log.info "archiving ${#paths[@]} path(s) to $output"

    tar -czf "$output" "${paths[@]}" 2>/dev/null || {
        log.error "tar archive failed"
        return 5
    }

    log.info "archive created: $output"
    return 0
}

# Extract a tar.gz archive to a destination directory.
# Usage: artifact.extract <archive_path> --output <destination>
# Returns: 0=success, 2=invalid input, 3=tool missing, 5=command failed, 6=IO error
artifact.extract() {
    local archive=""
    local output=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output) output="$2"; shift 2 ;;
            *) archive="$1"; shift ;;
        esac
    done

    if [[ -z "$archive" ]]; then
        log.error "archive path is required"
        return 2
    fi

    if [[ -z "$output" ]]; then
        log.error "output destination is required (--output)"
        return 2
    fi

    runtime.require_tool tar || return 3

    if [[ ! -f "$archive" ]]; then
        log.error "archive not found: $archive"
        return 6
    fi

    # Create destination if needed
    if [[ ! -d "$output" ]]; then
        mkdir -p "$output" || {
            log.error "cannot create destination directory: $output"
            return 6
        }
    fi

    log.info "extracting $archive to $output"

    tar -xzf "$archive" -C "$output" 2>/dev/null || {
        log.error "tar extract failed"
        return 5
    }

    log.info "extraction complete"
    return 0
}

#!/usr/bin/env bash
# @module transverse.yaml
# @requires yq
# @description YAML merge/patch helpers. Factors out the `yq -i` and
# `yq eval-all '* select(...)'` patterns duplicated across profile.merge,
# gitops.render_manifests, and gitops.push_manifests.
#
# All functions accept an optional --output <path> to write the result to a
# file; otherwise merge writes to stdout and patch/set_image_tag edit in place.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_YAML_LOADED:-}" ]] && return 0
_BRIK_MODULE_YAML_LOADED=1

# transverse.yaml.merge - deep merge two YAML files; override wins.
#
# Usage:
#   transverse.yaml.merge <base.yml> <override.yml> [--output <dest.yml>]
#
# Returns: 0 on success, BRIK_EXIT_INVALID_INPUT, BRIK_EXIT_MISSING_DEP,
# BRIK_EXIT_IO_FAILURE, BRIK_EXIT_EXTERNAL_FAIL.
transverse.yaml.merge() {
    local base="" override="" output=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output) output="$2"; shift 2 ;;
            --*)      log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
            *)
                if [[ -z "$base" ]]; then
                    base="$1"
                elif [[ -z "$override" ]]; then
                    override="$1"
                else
                    log.error "unexpected positional argument: $1"
                    return "$BRIK_EXIT_INVALID_INPUT"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$base" || -z "$override" ]]; then
        log.error "base and override files are required"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ ! -f "$base" ]]; then
        log.error "base file not found: $base"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    if [[ ! -f "$override" ]]; then
        log.error "override file not found: $override"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    pipeline.require_tool yq || return "$BRIK_EXIT_MISSING_DEP"

    local yq_rc=0
    if [[ -n "$output" ]]; then
        local yq_stderr
        yq_stderr="$(yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
                "$base" "$override" 2>&1 1>"$output")" || yq_rc=$?
        if [[ "$yq_rc" -ne 0 ]]; then
            log.error "yaml merge failed: $yq_stderr"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        fi
    else
        yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
                "$base" "$override" || yq_rc=$?
        if [[ "$yq_rc" -ne 0 ]]; then
            log.error "yaml merge failed (rc=$yq_rc)"
            return "$BRIK_EXIT_EXTERNAL_FAIL"
        fi
    fi

    return 0
}

# transverse.yaml.patch - set a scalar value at a yq path.
# Edits in place unless --output is given.
#
# Usage:
#   transverse.yaml.patch <file.yml> <path> <value> [--output <dest.yml>]
#
# <path> is a yq expression including the leading dot (e.g. ".spec.replicas").
transverse.yaml.patch() {
    local file="" path="" value="" output=""
    local file_set="" path_set="" value_set=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output) output="$2"; shift 2 ;;
            --*)      log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
            *)
                if [[ -z "$file_set" ]]; then
                    file="$1"; file_set="1"
                elif [[ -z "$path_set" ]]; then
                    path="$1"; path_set="1"
                elif [[ -z "$value_set" ]]; then
                    value="$1"; value_set="1"
                else
                    log.error "unexpected positional argument: $1"
                    return "$BRIK_EXIT_INVALID_INPUT"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$file_set" || -z "$file" ]]; then
        log.error "file is required (first positional)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ -z "$path_set" || -z "$path" ]]; then
        log.error "path is required (second positional)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ -z "$value_set" ]]; then
        log.error "value is required (third positional)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ ! -f "$file" ]]; then
        log.error "file not found: $file"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    pipeline.require_tool yq || return "$BRIK_EXIT_MISSING_DEP"

    local expr="${path} = \"${value}\""
    local yq_stderr yq_rc=0
    if [[ -n "$output" ]]; then
        yq_stderr="$(yq eval "$expr" "$file" 2>&1 1>"$output")" || yq_rc=$?
    else
        yq_stderr="$(yq eval -i "$expr" "$file" 2>&1)" || yq_rc=$?
    fi

    if [[ "$yq_rc" -ne 0 ]]; then
        log.error "yaml patch failed: $yq_stderr"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    return 0
}

# transverse.yaml.set_image_tag - rewrite the tag suffix on images at a given path.
# Uses yq sub() to replace everything after the last colon.
# Edits in place unless --output is given.
#
# Usage:
#   transverse.yaml.set_image_tag <file.yml> <image_path> <tag> [--output <dest>]
#
# <image_path> is a yq selector yielding zero or more image strings,
# e.g. ".spec.template.spec.containers[]?.image".
transverse.yaml.set_image_tag() {
    local file="" image_path="" tag="" tag_set="" output=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output) output="$2"; shift 2 ;;
            --*)      log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
            *)
                if [[ -z "$file" ]]; then
                    file="$1"
                elif [[ -z "$image_path" ]]; then
                    image_path="$1"
                elif [[ -z "$tag_set" ]]; then
                    tag="$1"
                    tag_set="1"
                else
                    log.error "unexpected positional argument: $1"
                    return "$BRIK_EXIT_INVALID_INPUT"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$file" ]]; then
        log.error "file is required (first positional)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ -z "$image_path" ]]; then
        log.error "image_path is required (second positional)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ -z "$tag_set" || -z "$tag" ]]; then
        log.error "tag is required (third positional)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi

    if [[ ! -f "$file" ]]; then
        log.error "file not found: $file"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    pipeline.require_tool yq || return "$BRIK_EXIT_MISSING_DEP"

    local expr="(${image_path}) |= sub(\":[^:]*\$\", \":${tag}\")"
    local yq_stderr yq_rc=0
    if [[ -n "$output" ]]; then
        yq_stderr="$(yq eval "$expr" "$file" 2>&1 1>"$output")" || yq_rc=$?
    else
        yq_stderr="$(yq eval -i "$expr" "$file" 2>&1)" || yq_rc=$?
    fi

    if [[ "$yq_rc" -ne 0 ]]; then
        log.error "yaml set_image_tag failed: $yq_stderr"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    return 0
}

# transverse.yaml.set_image - replace the FULL image ref at a yq path.
# Unlike set_image_tag (which rewrites only the ":tag" suffix), this sets the
# whole value, so a digest-pinned ref (registry/app@sha256:<hex>) can be
# injected. A path matching zero nodes is a no-op (success), so the same call
# is safe across manifests that do not all carry an image field.
#
# Usage:
#   transverse.yaml.set_image <file> <image_path> <ref> [--output <dest>]
#
# <image_path> is a yq selector yielding zero or more image strings,
# e.g. ".spec.template.spec.containers[]?.image".
transverse.yaml.set_image() {
    local file="" image_path="" ref="" ref_set="" output=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output) output="$2"; shift 2 ;;
            --*)      log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
            *)
                if [[ -z "$file" ]]; then
                    file="$1"
                elif [[ -z "$image_path" ]]; then
                    image_path="$1"
                elif [[ -z "$ref_set" ]]; then
                    ref="$1"
                    ref_set="1"
                else
                    log.error "unexpected positional argument: $1"
                    return "$BRIK_EXIT_INVALID_INPUT"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$file" ]]; then
        log.error "file is required (first positional)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -z "$image_path" ]]; then
        log.error "image_path is required (second positional)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ -z "$ref_set" || -z "$ref" ]]; then
        log.error "ref is required (third positional)"
        return "$BRIK_EXIT_INVALID_INPUT"
    fi
    if [[ ! -f "$file" ]]; then
        log.error "file not found: $file"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    pipeline.require_tool yq || return "$BRIK_EXIT_MISSING_DEP"

    local expr="(${image_path}) = \"${ref}\""
    local yq_stderr yq_rc=0
    if [[ -n "$output" ]]; then
        yq_stderr="$(yq eval "$expr" "$file" 2>&1 1>"$output")" || yq_rc=$?
    else
        yq_stderr="$(yq eval -i "$expr" "$file" 2>&1)" || yq_rc=$?
    fi

    if [[ "$yq_rc" -ne 0 ]]; then
        log.error "yaml set_image failed: $yq_stderr"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    return 0
}

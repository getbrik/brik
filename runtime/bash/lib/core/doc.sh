#!/usr/bin/env bash
# @module doc
# @description Generate project documentation using auto-detected or specified tools.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_DOC_LOADED:-}" ]] && return 0
_BRIK_CORE_DOC_LOADED=1

# Generate documentation.
# Usage: doc.generate [--tool <mkdocs|sphinx|javadoc|rustdoc>] [--output <path>] [--dry-run]
# Auto-detects tool from project files if not specified.
# Returns: 0=success, 2=invalid input, 3=tool missing, 5=command failed, 7=no tool detected
doc.generate() {
    local tool="${BRIK_DOC_TOOL:-}"
    local output="${BRIK_DOC_OUTPUT:-}"
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tool) tool="$2"; shift 2 ;;
            --output) output="$2"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    # Auto-detect tool if not specified
    if [[ -z "$tool" ]]; then
        tool="$(_doc._detect_tool)"
        if [[ -z "$tool" ]]; then
            log.error "no documentation tool detected; use --tool to specify"
            return "$BRIK_EXIT_CONFIG_ERROR"
        fi
        log.info "auto-detected documentation tool: $tool"
    fi

    case "$tool" in
        mkdocs)   _doc._run_mkdocs "$output" "$dry_run" ;;
        sphinx)   _doc._run_sphinx "$output" "$dry_run" ;;
        javadoc)  _doc._run_javadoc "$output" "$dry_run" ;;
        rustdoc)  _doc._run_rustdoc "$output" "$dry_run" ;;
        *)
            log.error "unsupported documentation tool: $tool"
            return "$BRIK_EXIT_INVALID_INPUT"
            ;;
    esac
}

# Detect documentation tool from project files.
_doc._detect_tool() {
    if [[ -f "mkdocs.yml" || -f "mkdocs.yaml" ]]; then
        printf 'mkdocs\n'
    elif [[ -f "docs/conf.py" || -f "conf.py" ]]; then
        printf 'sphinx\n'
    elif [[ -f "pom.xml" || -f "build.gradle" || -f "build.gradle.kts" ]]; then
        printf 'javadoc\n'
    elif [[ -f "Cargo.toml" ]]; then
        printf 'rustdoc\n'
    fi
}

_doc._run_mkdocs() {
    local output="$1" dry_run="$2"
    runtime.require_tool mkdocs || return "$BRIK_EXIT_MISSING_DEP"

    local -a cmd=(mkdocs build)
    [[ -n "$output" ]] && cmd+=(--site-dir "$output")

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] ${cmd[*]}"
        return 0
    fi

    log.info "generating docs: ${cmd[*]}"
    "${cmd[@]}" || {
        log.error "mkdocs build failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "documentation generated successfully"
    return 0
}

_doc._run_sphinx() {
    local output="$1" dry_run="$2"
    runtime.require_tool sphinx-build || return "$BRIK_EXIT_MISSING_DEP"

    local source_dir="docs"
    [[ -f "conf.py" ]] && source_dir="."
    local dest="${output:-_build/html}"

    local -a cmd=(sphinx-build -b html "$source_dir" "$dest")

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] ${cmd[*]}"
        return 0
    fi

    log.info "generating docs: ${cmd[*]}"
    "${cmd[@]}" || {
        log.error "sphinx-build failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "documentation generated successfully"
    return 0
}

_doc._run_javadoc() {
    local output="$1" dry_run="$2"

    local -a cmd
    if [[ -f "pom.xml" ]]; then
        runtime.require_tool mvn || return "$BRIK_EXIT_MISSING_DEP"
        cmd=(mvn -B javadoc:javadoc)
        [[ -n "$output" ]] && cmd+=(-Dreportoutputdirectory="$output")
    elif [[ -f "build.gradle" || -f "build.gradle.kts" ]]; then
        runtime.require_tool gradle || return "$BRIK_EXIT_MISSING_DEP"
        cmd=(gradle javadoc)
    else
        log.error "no pom.xml or build.gradle found for javadoc"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] ${cmd[*]}"
        return 0
    fi

    log.info "generating docs: ${cmd[*]}"
    "${cmd[@]}" || {
        log.error "javadoc generation failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "documentation generated successfully"
    return 0
}

_doc._run_rustdoc() {
    local output="$1" dry_run="$2"
    runtime.require_tool cargo || return "$BRIK_EXIT_MISSING_DEP"

    local -a cmd=(cargo doc --no-deps)
    [[ -n "$output" ]] && cmd+=(--target-dir "$output")

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] ${cmd[*]}"
        return 0
    fi

    log.info "generating docs: ${cmd[*]}"
    "${cmd[@]}" || {
        log.error "cargo doc failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    }

    log.info "documentation generated successfully"
    return 0
}

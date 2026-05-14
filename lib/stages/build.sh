#!/usr/bin/env bash
# @module stages/build
# @description Build stage - compile/build via stack-specific modules.

# Build stage: compile/build via brik-lib.
# Usage: stages.build <context_file>
stages.build() {
    # context_file positionally passed by stage.run; unused here after §4.2
    # migration (pipeline.run records tech.status from rc).
    # shellcheck disable=SC2034
    local context_file="$1"

    config.export_build_vars

    local stack="${BRIK_BUILD_STACK:-auto}"
    local result=0

    pipeline.require_dir "${BRIK_WORKSPACE}" || return $?

    # Auto-detect stack if not explicitly set.
    if [[ -z "$stack" || "$stack" == "auto" ]]; then
        brik.use stacks._detect
        stack="$(stacks.detect "${BRIK_WORKSPACE}")" || return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    log.info "running build (stack=$stack)"

    report.record "build" "tech" "stack" "$stack" 2>/dev/null || true
    report.record "build" "tech" "tool" "${BRIK_BUILD_TOOL:-auto}" 2>/dev/null || true
    if [[ -n "${BRIK_BUILD_COMMAND:-}" ]]; then
        report.record "build" "tech" "command" "$BRIK_BUILD_COMMAND" 2>/dev/null || true
    else
        report.record "build" "tech" "command" "<stack-default>" 2>/dev/null || true
    fi

    # cache_hit is opportunistic: stack modules (or the wrapper) export
    # BRIK_BUILD_CACHE_HIT when a cache restore was used. Coerce truthy
    # strings to JSON booleans; omit otherwise so an absent signal is
    # never confused with a cold build.
    case "${BRIK_BUILD_CACHE_HIT:-}" in
        true|1|yes)  report.record_object "build" "tech" "cache_hit" "true"  2>/dev/null || true ;;
        false|0|no)  report.record_object "build" "tech" "cache_hit" "false" 2>/dev/null || true ;;
    esac

    # Custom build command override bypasses the stack module.
    if [[ -n "${BRIK_BUILD_COMMAND:-}" ]]; then
        log.info "using custom build command: $BRIK_BUILD_COMMAND"
        (cd "${BRIK_WORKSPACE}" && eval "$BRIK_BUILD_COMMAND") || result=$?
        if [[ "$result" -eq 0 ]]; then
            _stages.build._record_artifact "${BRIK_WORKSPACE}" "$stack"
        fi
        return "$result"
    fi

    # Load and delegate to the stack-specific module.
    if ! brik.use "stacks.${stack}"; then
        log.error "unsupported build stack: $stack"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    local build_fn="stacks.${stack}.build"
    if ! declare -f "$build_fn" >/dev/null 2>&1; then
        log.error "build function not found: $build_fn"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    # Pass BRIK_BUILD_TOOL to stack module if set and not 'auto'.
    local tool_args=()
    if [[ -n "${BRIK_BUILD_TOOL:-}" && "${BRIK_BUILD_TOOL}" != "auto" ]]; then
        tool_args=(--tool "$BRIK_BUILD_TOOL")
    fi

    "$build_fn" "${BRIK_WORKSPACE}" "${tool_args[@]}"
    result=$?

    if [[ "$result" -eq 0 ]]; then
        _stages.build._record_artifact "${BRIK_WORKSPACE}" "$stack"
    fi
    return "$result"
}

# Locate the conventional build artifact directory and record its summary
# under business.artifact. Skipped silently when no recognized output
# directory exists (libraries, source-only repos, custom output paths).
#
# Probe order is stack-aware so JVM builds don't get caught by an empty
# dist/ left over from prior tooling. For each candidate the directory
# must exist AND contain at least one regular file > 1 byte; otherwise
# the loop continues. If every candidate exists but is empty, the first
# existing one is recorded so users still see "0 B (empty)" in the UI
# rather than nothing.
#
# Usage: _stages.build._record_artifact <workspace> [<stack>]
_stages.build._record_artifact() {
    local _ws="$1"
    local _stack="${2:-${BRIK_BUILD_STACK:-auto}}"

    local -a _candidates
    case "$_stack" in
        java)   _candidates=("target" "build/libs" "build") ;;
        rust)   _candidates=("target/release" "target") ;;
        dotnet)
            # .NET solutions often nest output under src/<project>/bin/<config>/<TFM>/
            # so the workspace-root bin/ stays empty. Expand the multi-project
            # glob before falling back to the conventional single-project paths.
            # Strip trailing slashes so that ${_best#"${_dir}/"} in
            # _find_main_file produces a relative main_file (not absolute).
            _candidates=()
            local _d _rel
            for _d in "$_ws"/src/*/bin/Release/*/; do
                [[ -d "$_d" ]] || continue
                _rel="${_d%/}"
                _candidates+=("${_rel#"$_ws/"}")
            done
            for _d in "$_ws"/src/*/bin/Debug/*/; do
                [[ -d "$_d" ]] || continue
                _rel="${_d%/}"
                _candidates+=("${_rel#"$_ws/"}")
            done
            _candidates+=("bin/Release" "bin/Debug" "out" "build")
            ;;
        node)   _candidates=("dist" "build" "out") ;;
        python) _candidates=("dist" "build") ;;
        docker) return 0 ;;
        *)      _candidates=("dist" "target/release" "target" "build/libs" "build" "bin/Release" "out") ;;
    esac

    local _c _abs _first_existing=""
    for _c in "${_candidates[@]}"; do
        _abs="${_ws}/${_c}"
        [[ -d "$_abs" ]] || continue
        [[ -z "$_first_existing" ]] && _first_existing="$_abs"
        # Skip empty / placeholder-only directories so the loop can fall
        # through to a real artifact dir (e.g. Java's empty dist/ -> target/).
        if [[ -n "$(find "$_abs" -maxdepth 3 -type f -size +1c -print -quit 2>/dev/null)" ]]; then
            brik.use transverse.artifact 2>/dev/null || return 0
            local _summary
            _summary="$(artifact.summarize "$_abs" "$_stack" 2>/dev/null)" || return 0
            [[ -z "$_summary" ]] && return 0
            report.record_object "build" "business" "artifact" "$_summary" 2>/dev/null || true
            return 0
        fi
    done

    # All candidates are empty (or absent). Record the first existing one
    # so the UI surfaces a 0 B warning rather than silently dropping the
    # field. Skipped entirely when nothing exists at all.
    if [[ -n "$_first_existing" ]]; then
        brik.use transverse.artifact 2>/dev/null || return 0
        local _summary
        _summary="$(artifact.summarize "$_first_existing" "$_stack" 2>/dev/null)" || return 0
        [[ -z "$_summary" ]] && return 0
        report.record_object "build" "business" "artifact" "$_summary" 2>/dev/null || true
    fi
    return 0
}

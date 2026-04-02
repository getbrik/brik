#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# @module hooks
# @description Hook system for the Brik runtime stage lifecycle.
#
# Hooks are resolved from (in priority order):
#   1. Project hooks: ${BRIK_PROJECT_DIR}/.brik/hooks/<hook_name>.sh
#   2. brik.yml config hooks: hooks.pre_<stage> / hooks.post_<stage>
#   3. Default hooks: ${BRIK_HOME}/runtime/bash/hooks/<hook_name>.sh
#
# If no hook script is found, the function is a no-op returning 0.

# Guard against double-sourcing
[[ -n "${_BRIK_HOOKS_LOADED:-}" ]] && return 0
_BRIK_HOOKS_LOADED=1

# Source dependencies
# shellcheck source=logging.sh
[[ -z "${_BRIK_LOGGING_LOADED:-}" ]] && . "${BASH_SOURCE[0]%/*}/logging.sh"

# Resolve a hook script path. Prints the path on stdout if found.
# Returns 1 if no hook script exists.
_hook._resolve() {
    local hook_name="$1"
    local project_dir="${BRIK_PROJECT_DIR:-$(pwd)}"
    local project_hook="${project_dir}/.brik/hooks/${hook_name}.sh"
    local default_hook="${BRIK_HOME}/runtime/bash/hooks/${hook_name}.sh"

    # Priority 1: Project hook file
    if [[ -f "$project_hook" ]]; then
        printf '%s' "$project_hook"
        return 0
    fi

    # Priority 3: Default hook
    if [[ -f "$default_hook" ]]; then
        printf '%s' "$default_hook"
        return 0
    fi
    return 1
}

# Resolve a brik.yml inline hook for a stage.
# Returns the inline command on stdout, or returns 1 if not found.
_hook._resolve_config() {
    local hook_type="$1"  # pre or post
    local stage_name="$2"
    local upper_stage
    upper_stage="$(printf '%s' "$stage_name" | tr '[:lower:]' '[:upper:]')"
    local var_name="BRIK_HOOK_${hook_type}_${upper_stage}"

    if [[ -n "${!var_name:-}" ]]; then
        printf '%s' "${!var_name}"
        return 0
    fi
    return 1
}

# Execute a hook by name. Sources the hook script and calls the function
# named <hook_name> if it is defined.
# Returns 0 if no hook found (no-op), or the hook's return code.
_hook._run() {
    local hook_name="$1"
    shift
    local hook_path

    hook_path="$(_hook._resolve "$hook_name")" || {
        log.debug "no hook script found for: $hook_name"
        return 0
    }

    log.debug "loading hook: $hook_path"
    # shellcheck source=/dev/null
    . "$hook_path"

    if declare -f "$hook_name" >/dev/null 2>&1; then
        "$hook_name" "$@"
        return $?
    fi

    log.debug "hook script loaded but function '$hook_name' not defined"
    return 0
}

# Pre-stage hook. Can abort the stage (non-zero return stops execution).
# Checks brik.yml config hooks first, then file-based hooks.
hook.pre_stage() {
    local stage_name="$1"
    local context_file="$2"
    local log_file="$3"

    # Check brik.yml inline hook
    local inline_cmd
    if inline_cmd="$(_hook._resolve_config "PRE" "$stage_name")"; then
        log.debug "running brik.yml pre_${stage_name} hook: $inline_cmd"
        eval "$inline_cmd"
        return $?
    fi

    _hook._run "pre_stage" "$stage_name" "$context_file" "$log_file"
}

# Post-stage hook. Called after success/failure hooks.
# Checks brik.yml config hooks first, then file-based hooks.
hook.post_stage() {
    local stage_name="$1"
    local context_file="$2"
    local log_file="$3"
    local exit_code="$4"

    # Check brik.yml inline hook
    local inline_cmd
    if inline_cmd="$(_hook._resolve_config "POST" "$stage_name")"; then
        log.debug "running brik.yml post_${stage_name} hook: $inline_cmd"
        eval "$inline_cmd"
        return $?
    fi

    _hook._run "post_stage" "$stage_name" "$context_file" "$log_file" "$exit_code"
}

# Success hook. Best effort - errors are suppressed.
hook.on_success() {
    local stage_name="$1"
    local context_file="$2"
    local log_file="$3"
    _hook._run "on_success" "$stage_name" "$context_file" "$log_file"
}

# Failure hook. Best effort - errors are suppressed.
hook.on_failure() {
    local stage_name="$1"
    local context_file="$2"
    local log_file="$3"
    local exit_code="$4"
    _hook._run "on_failure" "$stage_name" "$context_file" "$log_file" "$exit_code"
}

# Cleanup hook. Best effort - errors are suppressed.
hook.on_cleanup() {
    local stage_name="$1"
    local context_file="$2"
    local log_file="$3"
    _hook._run "on_cleanup" "$stage_name" "$context_file" "$log_file"
}

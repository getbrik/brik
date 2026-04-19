#!/usr/bin/env bash
# @module quality._tools
# @description Centralized tool registry for quality/security scanning.
# Provides register/resolve/exec abstraction to decouple modules from specific tools.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_QUALITY_TOOLS_LOADED:-}" ]] && return 0
_BRIK_CORE_QUALITY_TOOLS_LOADED=1

# Registry storage: _BRIK_TOOL_<CATEGORY>_<N>="priority|tool|binary|template"
declare -g _BRIK_TOOL_COUNTER=0

# Register a tool for a scan category.
# Usage: quality.tool.register <category> <tool> <binary> <command_template> [priority]
quality.tool.register() {
    local category="$1" tool="$2" binary="$3" template="$4" priority="${5:-50}"
    _BRIK_TOOL_COUNTER=$((_BRIK_TOOL_COUNTER + 1))
    local key="_BRIK_TOOL_${category}_${_BRIK_TOOL_COUNTER}"
    printf -v "$key" '%s|%s|%s|%s' "$priority" "$tool" "$binary" "$template"
}

# Parse registry entry fields.
# Sets: _t_priority, _t_tool, _t_binary, _t_template
_brik_tool_parse_entry() {
    local val="$1"
    _t_priority="${val%%|*}"
    local rest="${val#*|}"
    _t_tool="${rest%%|*}"
    rest="${rest#*|}"
    _t_binary="${rest%%|*}"
    _t_template="${rest#*|}"
}

# Tier 1: check BRIK_QUALITY_<CAT>_COMMAND or BRIK_SECURITY_<CAT>_COMMAND.
# Returns 0 and echoes "__command__" if found, 1 otherwise.
_brik_tool_resolve_tier1() {
    local category_upper="${1^^}"
    local cmd_var="BRIK_QUALITY_${category_upper}_COMMAND"
    if [[ -n "${!cmd_var:-}" ]]; then echo "__command__"; return 0; fi
    cmd_var="BRIK_SECURITY_${category_upper}_COMMAND"
    if [[ -n "${!cmd_var:-}" ]]; then echo "__command__"; return 0; fi
    return "$BRIK_EXIT_FAILURE"
}

# Tier 2: resolve an explicitly requested tool name from registry.
# Returns 0+tool name, 3 if binary missing, 7 if tool not registered.
_brik_tool_resolve_tier2() {
    local category="$1" requested="$2"
    local var_name var_val _t_priority _t_tool _t_binary _t_template
    for var_name in $(compgen -v _BRIK_TOOL_"${category}"_ 2>/dev/null); do
        var_val="${!var_name}"
        _brik_tool_parse_entry "$var_val"
        if [[ "$_t_tool" == "$requested" ]]; then
            if command -v "$_t_binary" >/dev/null 2>&1; then
                echo "$requested"
                return 0
            else
                return "$BRIK_EXIT_MISSING_DEP"
            fi
        fi
    done
    return "$BRIK_EXIT_CONFIG_ERROR"
}

# Tier 3: auto-detect best available tool by priority.
# Returns 0+tool name, 1 if none available.
_brik_tool_resolve_tier3() {
    local category="$1"
    local best_tool="" best_priority=999999
    local var_name var_val _t_priority _t_tool _t_binary _t_template
    for var_name in $(compgen -v _BRIK_TOOL_"${category}"_ 2>/dev/null); do
        var_val="${!var_name}"
        _brik_tool_parse_entry "$var_val"
        if command -v "$_t_binary" >/dev/null 2>&1; then
            if (( _t_priority < best_priority )); then
                best_priority="$_t_priority"
                best_tool="$_t_tool"
            fi
        fi
    done
    if [[ -n "$best_tool" ]]; then
        echo "$best_tool"
        return 0
    fi
    return "$BRIK_EXIT_FAILURE"
}

# Resolve which tool to use for a category (3-tier resolution).
# Outputs tool name on stdout. Returns 1 if none available, 3 if explicit tool missing, 7 if unknown.
# Usage: quality.tool.resolve <category> [--tool <name>]
quality.tool.resolve() {
    local category="$1"
    shift
    local explicit_tool=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tool) explicit_tool="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Tier 1: command override
    _brik_tool_resolve_tier1 "$category" && return 0

    # Tier 2: explicit tool selection
    local tool_var="BRIK_QUALITY_${category^^}_TOOL"
    local sec_tool_var="BRIK_SECURITY_${category^^}_TOOL"
    local requested="${explicit_tool:-${!tool_var:-${!sec_tool_var:-}}}"
    if [[ -n "$requested" ]]; then
        _brik_tool_resolve_tier2 "$category" "$requested"
        return $?
    fi

    # Tier 3: auto-detect by priority
    _brik_tool_resolve_tier3 "$category"
}

# Execute a resolved tool with variable substitution.
# Usage: quality.tool.exec <category> <resolved_tool> [key=value...]
quality.tool.exec() {
    local category="$1" resolved="$2"
    shift 2

    # Tier 1: command override - execute directly
    if [[ "$resolved" == "__command__" ]]; then
        local cmd_var="BRIK_QUALITY_${category^^}_COMMAND"
        local cmd="${!cmd_var:-}"
        [[ -z "$cmd" ]] && cmd_var="BRIK_SECURITY_${category^^}_COMMAND" && cmd="${!cmd_var:-}"
        eval "$cmd"
        return
    fi

    # Find template for resolved tool (last match wins, supports re-registration)
    local template=""
    local var_name var_val _t_priority _t_tool _t_binary _t_template
    for var_name in $(compgen -v _BRIK_TOOL_"${category}"_ 2>/dev/null); do
        var_val="${!var_name}"
        _brik_tool_parse_entry "$var_val"
        if [[ "$_t_tool" == "$resolved" ]]; then
            template="$_t_template"
        fi
    done

    if [[ -z "$template" ]]; then
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi

    # Substitute {var} placeholders with key=value args
    # Values are sanitized: only allow alphanumeric, hyphens, dots, colons, slashes, underscores
    local cmd="$template"
    local key val
    while [[ $# -gt 0 ]]; do
        key="${1%%=*}" val="${1#*=}"
        if [[ "$val" =~ [^a-zA-Z0-9_./:@=-] ]]; then
            log.error "unsafe value for {$key}: $val"
            return "$BRIK_EXIT_INVALID_INPUT"
        fi
        cmd="${cmd//\{$key\}/$val}"
        shift
    done

    eval "$cmd"
}

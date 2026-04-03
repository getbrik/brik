#!/usr/bin/env bash
# @module config.java
# @description Java stack defaults and version export.
#
# Loaded via: brik.use config.java

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_CONFIG_JAVA_LOADED:-}" ]] && return 0
_BRIK_CORE_CONFIG_JAVA_LOADED=1

# Return the default value for a Java setting.
# Usage: config.java.default <setting>
config.java.default() {
    local setting="$1"

    case "$setting" in
        build_command)  printf '' ;;
        build_tool)     printf 'auto' ;;
        test_framework) printf 'junit' ;;
        lint_tool)      printf 'checkstyle' ;;
        format_tool)    printf 'google-java-format' ;;
        *) return 1 ;;
    esac
    return 0
}

# Export Java version pinning.
# Sets: BRIK_BUILD_JAVA_VERSION (if configured)
config.java.export_build_vars() {
    local java_version
    java_version="$(config.get '.build.java_version' '')"
    [[ -n "$java_version" ]] && export BRIK_BUILD_JAVA_VERSION="$java_version"
    return 0
}

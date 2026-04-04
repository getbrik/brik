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

# Validate Java build tool coherence.
# If build tool is explicitly set, verify the matching project file exists.
# Usage: config.java.validate_coherence <workspace>
config.java.validate_coherence() {
    local workspace="$1"
    local tool="${BRIK_BUILD_TOOL:-}"

    # Only validate when tool is explicitly set (not auto)
    [[ -z "$tool" || "$tool" == "auto" ]] && return 0

    case "$tool" in
        maven)
            if [[ ! -f "${workspace}/pom.xml" ]]; then
                log.error "config mismatch: build.tool is 'maven' but pom.xml not found"
                log.error "fix: create a pom.xml, or change build.tool in brik.yml"
                return 7
            fi
            ;;
        gradle)
            if [[ ! -f "${workspace}/build.gradle" ]] && [[ ! -f "${workspace}/build.gradle.kts" ]]; then
                log.error "config mismatch: build.tool is 'gradle' but neither build.gradle nor build.gradle.kts found"
                log.error "fix: create a build.gradle, or change build.tool in brik.yml"
                return 7
            fi
            ;;
    esac

    return 0
}

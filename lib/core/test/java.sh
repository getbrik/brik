#!/usr/bin/env bash
# @module test.java
# @requires mvn or gradle
# @description Test commands for Java projects (Maven, Gradle).

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_TEST_JAVA_LOADED:-}" ]] && return 0
_BRIK_CORE_TEST_JAVA_LOADED=1

# Build the test command for a given Java framework.
# Usage: test.java.cmd <framework> <workspace> <report_dir>
# Frameworks: junit, maven, gradle
test.java.cmd() {
    local framework="$1" workspace="$2" report_dir="$3"
    local cmd=""

    case "$framework" in
        junit|maven)
            cmd="mvn -B test"
            [[ -n "$report_dir" ]] && cmd="$cmd -Dsurefire.reportsDirectory=${report_dir}"
            ;;
        gradle)
            cmd="gradle test"
            [[ -x "${workspace}/gradlew" ]] && cmd="./gradlew test"
            ;;
        *)
            log.error "unsupported Java test framework: $framework"
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac

    printf '%s' "$cmd"
    return 0
}

# Auto-detect and return the test command for a Java workspace.
# Detects pom.xml -> maven, build.gradle(.kts) -> gradle.
# Usage: test.java.run_cmd <workspace> <report_dir>
test.java.run_cmd() {
    local workspace="$1" report_dir="$2"

    if [[ -f "${workspace}/pom.xml" ]]; then
        test.java.cmd "maven" "$workspace" "$report_dir"
    elif [[ -f "${workspace}/build.gradle" || -f "${workspace}/build.gradle.kts" ]]; then
        test.java.cmd "gradle" "$workspace" "$report_dir"
    else
        log.error "cannot detect Java test tool in workspace: $workspace"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
}

#!/usr/bin/env bash
# @module build.java
# @requires mvn or gradle
# @description Build Java projects (Maven, Gradle).

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_BUILD_JAVA_LOADED:-}" ]] && return 0
_BRIK_CORE_BUILD_JAVA_LOADED=1

# Detect the build tool from marker files.
# Prints maven or gradle on stdout.
_build.java._detect_tool() {
    local workspace="$1"

    if [[ -f "${workspace}/pom.xml" ]]; then
        printf 'maven'
    elif [[ -f "${workspace}/build.gradle" || -f "${workspace}/build.gradle.kts" ]]; then
        printf 'gradle'
    else
        printf ''
    fi
}

# Run the build.
# Usage: build.java.run <workspace> [--tool <maven|gradle>] [--goals <goals>]
build.java.run() {
    local workspace="$1"
    shift
    local tool="" goals=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tool) tool="$2"; shift 2 ;;
            --goals) goals="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    runtime.require_dir "$workspace" || return 6

    # Auto-detect tool if not specified
    if [[ -z "$tool" ]]; then
        tool="$(_build.java._detect_tool "$workspace")"
        if [[ -z "$tool" ]]; then
            log.error "cannot detect Java build tool in workspace: $workspace"
            return 7
        fi
    fi

    case "$tool" in
        maven)
            runtime.require_tool mvn || return 3
            [[ -z "$goals" ]] && goals="package -DskipTests"
            log.info "building with Maven: mvn $goals"
            # $goals intentionally word-splits
            # shellcheck disable=SC2086
            (cd "$workspace" && mvn -B $goals) || {
                log.error "build failed"
                return 5
            }
            ;;
        gradle)
            local gradle_cmd="gradle"
            if [[ -x "${workspace}/gradlew" ]]; then
                gradle_cmd="./gradlew"
            else
                runtime.require_tool gradle || return 3
            fi
            [[ -z "$goals" ]] && goals="build -x test"
            log.info "building with Gradle: $gradle_cmd $goals"
            # $goals intentionally word-splits
            # shellcheck disable=SC2086
            (cd "$workspace" && $gradle_cmd $goals) || {
                log.error "build failed"
                return 5
            }
            ;;
        *)
            log.error "unsupported Java build tool: $tool"
            return 7
            ;;
    esac

    log.info "build completed successfully"
    return 0
}

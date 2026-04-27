#!/usr/bin/env bash
# @module stacks/java
# @requires mvn or gradle
# @description Build Java projects (Maven, Gradle).

# Guard against double-sourcing
[[ -n "${_BRIK_STACKS_JAVA_LOADED:-}" ]] && return 0
_BRIK_STACKS_JAVA_LOADED=1

# Detect the build tool from marker files.
# Prints maven or gradle on stdout.
_stacks.java._detect_tool() {
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
# Usage: stacks.java.build <workspace> [--tool <maven|gradle>] [--goals <goals>]
stacks.java.build() {
    local workspace="$1"
    shift
    local tool="" goals=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tool) tool="$2"; shift 2 ;;
            --goals) goals="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    pipeline.require_dir "$workspace" || return "$BRIK_EXIT_IO_FAILURE"

    # Auto-detect tool if not specified
    if [[ -z "$tool" ]]; then
        tool="$(_stacks.java._detect_tool "$workspace")"
        if [[ -z "$tool" ]]; then
            log.error "cannot detect Java build tool in workspace: $workspace"
            return "$BRIK_EXIT_CONFIG_ERROR"
        fi
    fi

    case "$tool" in
        maven)
            pipeline.require_tool mvn || return "$BRIK_EXIT_MISSING_DEP"
            [[ -z "$goals" ]] && goals="package -DskipTests"
            log.info "building with Maven: mvn $goals"
            # $goals intentionally word-splits
            # shellcheck disable=SC2086
            (cd "$workspace" && mvn -B $goals) || {
                log.error "build failed"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
            ;;
        gradle)
            local gradle_cmd="gradle"
            if [[ -x "${workspace}/gradlew" ]]; then
                gradle_cmd="./gradlew"
            else
                pipeline.require_tool gradle || return "$BRIK_EXIT_MISSING_DEP"
            fi
            [[ -z "$goals" ]] && goals="build -x test"
            log.info "building with Gradle: $gradle_cmd $goals"
            # $goals intentionally word-splits
            # shellcheck disable=SC2086
            (cd "$workspace" && $gradle_cmd $goals) || {
                log.error "build failed"
                return "$BRIK_EXIT_EXTERNAL_FAIL"
            }
            ;;
        *)
            log.error "unsupported Java build tool: $tool"
            return "$BRIK_EXIT_CONFIG_ERROR"
            ;;
    esac

    log.info "build completed successfully"
    return 0
}

# Build the test command for a given Java framework.
# Usage: stacks.java.test_cmd <framework> <workspace> <report_dir>
# Frameworks: junit, maven, gradle
stacks.java.test_cmd() {
    local framework="$1" workspace="$2" report_dir="$3"
    local cmd=""
    local reports_on="${BRIK_TEST_REPORTS_ENABLED:-false}"
    local cov_dir="${BRIK_TEST_COVERAGE_DIR:-coverage}"

    case "$framework" in
        junit|maven)
            cmd="mvn -B test"
            if [[ "$reports_on" == "true" ]]; then
                # Surefire writes JUnit XMLs natively under target/surefire-reports/.
                # Standardize to reports/junit/. Jacoco is opt-in (project must
                # configure the plugin); if jacoco.xml exists, copy it to ${cov_dir}.
                # Use ; (not &&) so reports are captured even when tests fail.
                cmd="${cmd}; _rc=\$?"
                cmd="${cmd}; mkdir -p reports/junit"
                cmd="${cmd}; find target/surefire-reports -name '*.xml' -exec cp -f {} reports/junit/ \\; 2>/dev/null"
                cmd="${cmd}; if [[ -f target/site/jacoco/jacoco.xml ]]; then mkdir -p '${cov_dir}'; cp -f target/site/jacoco/jacoco.xml '${cov_dir}/jacoco.xml'; fi"
                cmd="${cmd}; exit \$_rc"
            elif [[ -n "$report_dir" ]]; then
                cmd="$cmd -Dsurefire.reportsDirectory=${report_dir}"
            fi
            ;;
        gradle)
            cmd="gradle test"
            [[ -x "${workspace}/gradlew" ]] && cmd="./gradlew test"
            if [[ "$reports_on" == "true" ]]; then
                # Gradle writes JUnit XMLs to build/test-results/test/. Standardize
                # to reports/junit/. Jacoco default report path is
                # build/reports/jacoco/test/jacocoTestReport.xml.
                cmd="${cmd}; _rc=\$?"
                cmd="${cmd}; mkdir -p reports/junit"
                cmd="${cmd}; find build/test-results/test -name '*.xml' -exec cp -f {} reports/junit/ \\; 2>/dev/null"
                cmd="${cmd}; if [[ -f build/reports/jacoco/test/jacocoTestReport.xml ]]; then mkdir -p '${cov_dir}'; cp -f build/reports/jacoco/test/jacocoTestReport.xml '${cov_dir}/jacoco.xml'; fi"
                cmd="${cmd}; exit \$_rc"
            fi
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
# Usage: stacks.java.test <workspace> <report_dir>
stacks.java.test() {
    local workspace="$1" report_dir="$2"

    if [[ -f "${workspace}/pom.xml" ]]; then
        stacks.java.test_cmd "maven" "$workspace" "$report_dir"
    elif [[ -f "${workspace}/build.gradle" || -f "${workspace}/build.gradle.kts" ]]; then
        stacks.java.test_cmd "gradle" "$workspace" "$report_dir"
    else
        log.error "cannot detect Java test tool in workspace: $workspace"
        return "$BRIK_EXIT_CONFIG_ERROR"
    fi
}

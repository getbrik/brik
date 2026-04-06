#!/usr/bin/env bash
# @module publish.maven
# @requires mvn|gradle
# @description Publish to a Maven repository.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_PUBLISH_MAVEN_LOADED:-}" ]] && return 0
_BRIK_CORE_PUBLISH_MAVEN_LOADED=1

# Publish to Maven repository.
# Usage: publish.maven.run [--repository <url>] [--username-var <VAR>]
#        [--password-var <VAR>] [--dry-run]
# Reads defaults from BRIK_PUBLISH_MAVEN_* environment variables.
# Auth: uses a temporary settings.xml (chmod 600) to avoid CLI credential exposure.
publish.maven.run() {
    local repository="${BRIK_PUBLISH_MAVEN_REPOSITORY:-}"
    local username_var="${BRIK_PUBLISH_MAVEN_USERNAME_VAR:-}"
    local password_var="${BRIK_PUBLISH_MAVEN_PASSWORD_VAR:-}"
    local dry_run="${BRIK_DRY_RUN:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repository) repository="$2"; shift 2 ;;
            --username-var) username_var="$2"; shift 2 ;;
            --password-var) password_var="$2"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            --target) shift 2 ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    # Detect build tool
    local tool=""
    if [[ -f "pom.xml" ]]; then
        tool="mvn"
    elif [[ -f "build.gradle" || -f "build.gradle.kts" ]]; then
        tool="gradle"
    else
        log.error "no pom.xml or build.gradle found"
        return 6
    fi

    runtime.require_tool "$tool" || return 3

    # Validate credentials if provided
    if [[ -n "$username_var" ]]; then
        _publish._require_secret_var "$username_var" "maven username" || return $?
    fi
    if [[ -n "$password_var" ]]; then
        _publish._require_secret_var "$password_var" "maven password" || return $?
    fi

    local -a cmd
    local tmp_settings=""

    if [[ "$tool" == "mvn" ]]; then
        cmd=(mvn deploy -B)
        [[ -n "$repository" ]] && cmd+=(-DaltDeploymentRepository="brik::default::${repository}")

        # Write temporary settings.xml with credentials (never pass via CLI args)
        if [[ -n "$username_var" && -n "$password_var" ]]; then
            tmp_settings="$(mktemp)"
            chmod 600 "$tmp_settings"
            cat > "$tmp_settings" <<SETTINGS_XML
<settings>
  <servers>
    <server>
      <id>brik</id>
      <username>${!username_var}</username>
      <password>${!password_var}</password>
    </server>
  </servers>
</settings>
SETTINGS_XML
            cmd+=(--settings "$tmp_settings")
        fi
    else
        cmd=(gradle publish)
        [[ -n "$repository" ]] && cmd+=(-PmavenRepository="$repository")
    fi

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] ${cmd[*]}"
        rm -f "$tmp_settings" 2>/dev/null || true
        return 0
    fi

    log.info "publishing to maven: ${cmd[*]}"
    "${cmd[@]}"
    local rc=$?

    # Cleanup temporary settings file
    rm -f "$tmp_settings" 2>/dev/null || true

    if [[ $rc -ne 0 ]]; then
        log.error "maven publish failed"
        return 5
    fi

    log.info "maven publish completed successfully"
    return 0
}

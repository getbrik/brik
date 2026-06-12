#!/usr/bin/env bash
# @module pkg.maven
# @requires mvn|gradle
# @description Publish to a Maven repository.

# Guard against double-sourcing
[[ -n "${_BRIK_PKG_MAVEN_LOADED:-}" ]] && return 0
_BRIK_PKG_MAVEN_LOADED=1

# Publish to Maven repository.
# Usage: pkg.maven.publish [--repository <url>] [--username-var <VAR>]
#        [--password-var <VAR>] [--dry-run]
# Reads defaults from BRIK_PUBLISH_MAVEN_* environment variables.
# Auth: uses a temporary settings.xml (chmod 600) to avoid CLI credential exposure.
pkg.maven.publish() {
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
            *) log.error "unknown option: $1"; return "$BRIK_EXIT_INVALID_INPUT" ;;
        esac
    done

    # Referential absorption: a declared PackageRegistry endpoint of this
    # format is the single source of truth for the destination and identity;
    # the BRIK_PUBLISH_MAVEN_* variables remain the legacy path without one.
    # Maven needs a username + password pair, so a token credential cannot
    # serve it (fail closed rather than guess a split).
    brik.use package-managers._endpoint 2>/dev/null || true
    local _ep=""
    if declare -f pkg.endpoint.resolve >/dev/null 2>&1; then
        _ep="$(pkg.endpoint.resolve maven "$repository")" || return "$?"
    fi
    if [[ -n "$_ep" ]]; then
        repository="$(jq -r '.url' <<<"$_ep")"
        case "$(jq -r '.method' <<<"$_ep")" in
            basic)
                BRIK_PKG_MAVEN_USERNAME="$(jq -r '.username' <<<"$_ep")"
                export BRIK_PKG_MAVEN_USERNAME
                username_var="BRIK_PKG_MAVEN_USERNAME"
                password_var="$(jq -r '.password_var' <<<"$_ep")"
                ;;
            token)
                log.error "PackageRegistry 'maven': a token credential cannot serve maven (username + password required) -- failing closed"
                return "$BRIK_EXIT_CONFIG_ERROR"
                ;;
            none) username_var=""; password_var="" ;;
        esac
    fi

    # Detect build tool
    local tool=""
    if [[ -f "pom.xml" ]]; then
        tool="mvn"
    elif [[ -f "build.gradle" || -f "build.gradle.kts" ]]; then
        tool="gradle"
    else
        log.error "no pom.xml or build.gradle found"
        return "$BRIK_EXIT_IO_FAILURE"
    fi

    pipeline.require_tool "$tool" || return "$BRIK_EXIT_MISSING_DEP"

    # Validate credentials if provided
    if [[ -n "$username_var" ]]; then
        brik.use transverse.secrets
        transverse.secrets.require_var "$username_var" "maven username" || return $?
    fi
    if [[ -n "$password_var" ]]; then
        brik.use transverse.secrets
        transverse.secrets.require_var "$password_var" "maven password" || return $?
    fi

    local -a cmd
    local tmp_settings=""

    if [[ "$tool" == "mvn" ]]; then
        cmd=(mvn deploy -B)
        [[ -n "$repository" ]] && cmd+=(-DaltDeploymentRepository="brik::default::${repository}")

        # Write temporary settings.xml with credentials (never pass via CLI args)
        if [[ -n "$username_var" && -n "$password_var" ]]; then
            brik.use transverse.env
            local maven_username maven_password
            maven_username="$(transverse.env.resolve_indirect "$username_var")"
            maven_password="$(transverse.env.resolve_indirect "$password_var")"
            tmp_settings="$(mktemp)"
            chmod 600 "$tmp_settings"
            cat > "$tmp_settings" <<SETTINGS_XML
<settings>
  <servers>
    <server>
      <id>brik</id>
      <username>${maven_username}</username>
      <password>${maven_password}</password>
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
        # cleanup: always remove temp credentials file
        rm -f "$tmp_settings" 2>/dev/null || true
        return 0
    fi

    log.info "publishing to maven: ${cmd[*]}"
    local rc=0
    "${cmd[@]}" || rc=$?

    # cleanup: always remove temp credentials file
    rm -f "$tmp_settings" 2>/dev/null || true

    if [[ $rc -ne 0 ]]; then
        log.error "maven publish failed"
        return "$BRIK_EXIT_EXTERNAL_FAIL"
    fi

    log.info "maven publish completed successfully"
    return 0
}

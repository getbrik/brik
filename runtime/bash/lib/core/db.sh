#!/usr/bin/env bash
# @module db
# @description Database migration management.

# Guard against double-sourcing
[[ -n "${_BRIK_CORE_DB_LOADED:-}" ]] && return 0
_BRIK_CORE_DB_LOADED=1

# Run database migrations.
# Usage: db.migrate --tool <flyway|liquibase|alembic|custom> --url <db_url> [--dry-run]
# Returns: 0=success, 2=invalid input, 3=tool missing, 5=command failed
db.migrate() {
    local tool="${BRIK_DB_TOOL:-}"
    local url="${BRIK_DB_URL:-}"
    local dry_run="${BRIK_DRY_RUN:-}"
    local command="${BRIK_DB_COMMAND:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tool) tool="$2"; shift 2 ;;
            --url) url="$2"; shift 2 ;;
            --command) command="$2"; shift 2 ;;
            --dry-run) dry_run="true"; shift ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    if [[ -z "$tool" ]]; then
        log.error "migration tool is required (--tool)"
        return 2
    fi

    case "$tool" in
        flyway)     _db._migrate_flyway "$url" "$dry_run" ;;
        liquibase)  _db._migrate_liquibase "$url" "$dry_run" ;;
        alembic)    _db._migrate_alembic "$url" "$dry_run" ;;
        custom)     _db._migrate_custom "$command" "$dry_run" ;;
        *)
            log.error "unsupported migration tool: $tool"
            return 2
            ;;
    esac
}

# Check migration status.
# Usage: db.status --tool <flyway|liquibase|alembic|custom> --url <db_url>
# stdout: JSON {pending: n, applied: n}
# Returns: 0=success, 2=invalid input, 3=tool missing, 5=command failed
db.status() {
    local tool="${BRIK_DB_TOOL:-}"
    local url="${BRIK_DB_URL:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tool) tool="$2"; shift 2 ;;
            --url) url="$2"; shift 2 ;;
            *) log.error "unknown option: $1"; return 2 ;;
        esac
    done

    if [[ -z "$tool" ]]; then
        log.error "migration tool is required (--tool)"
        return 2
    fi

    case "$tool" in
        flyway)
            runtime.require_tool flyway || return 3
            local -a cmd=(flyway info)
            [[ -n "$url" ]] && cmd+=(-url="$url")
            log.info "checking migration status: ${cmd[*]}"
            "${cmd[@]}" || {
                log.error "flyway info failed"
                return 5
            }
            ;;
        liquibase)
            runtime.require_tool liquibase || return 3
            local -a cmd=(liquibase status)
            [[ -n "$url" ]] && cmd+=(--url="$url")
            log.info "checking migration status: ${cmd[*]}"
            "${cmd[@]}" || {
                log.error "liquibase status failed"
                return 5
            }
            ;;
        alembic)
            runtime.require_tool alembic || return 3
            log.info "checking migration status: alembic current"
            alembic current || {
                log.error "alembic current failed"
                return 5
            }
            ;;
        *)
            log.error "unsupported migration tool for status: $tool"
            return 2
            ;;
    esac
}

_db._migrate_flyway() {
    local url="$1" dry_run="$2"
    runtime.require_tool flyway || return 3

    local -a cmd=(flyway migrate)
    [[ -n "$url" ]] && cmd+=(-url="$url")

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] ${cmd[*]}"
        return 0
    fi

    log.info "running migrations: ${cmd[*]}"
    "${cmd[@]}" || {
        log.error "flyway migrate failed"
        return 5
    }

    log.info "flyway migrations completed successfully"
    return 0
}

_db._migrate_liquibase() {
    local url="$1" dry_run="$2"
    runtime.require_tool liquibase || return 3

    local -a cmd=(liquibase update)
    [[ -n "$url" ]] && cmd+=(--url="$url")

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] ${cmd[*]}"
        return 0
    fi

    log.info "running migrations: ${cmd[*]}"
    "${cmd[@]}" || {
        log.error "liquibase update failed"
        return 5
    }

    log.info "liquibase migrations completed successfully"
    return 0
}

_db._migrate_alembic() {
    local url="$1" dry_run="$2"
    runtime.require_tool alembic || return 3

    local -a cmd=(alembic upgrade head)

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] ${cmd[*]}"
        return 0
    fi

    log.info "running migrations: ${cmd[*]}"
    if [[ -n "$url" ]]; then
        SQLALCHEMY_DATABASE_URI="$url" "${cmd[@]}" || {
            log.error "alembic upgrade failed"
            return 5
        }
    else
        "${cmd[@]}" || {
            log.error "alembic upgrade failed"
            return 5
        }
    fi

    log.info "alembic migrations completed successfully"
    return 0
}

_db._migrate_custom() {
    local command="$1" dry_run="$2"

    if [[ -z "$command" ]]; then
        log.error "custom migration command is required (--command)"
        return 2
    fi

    if [[ "$dry_run" == "true" ]]; then
        log.info "[dry-run] $command"
        return 0
    fi

    log.info "running custom migration: $command"
    # eval is required here: custom commands come from brik.yml (trusted project config)
    eval "$command" || {
        log.error "custom migration failed"
        return 5
    }

    log.info "custom migration completed successfully"
    return 0
}

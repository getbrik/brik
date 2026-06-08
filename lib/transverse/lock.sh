#!/usr/bin/env bash
# @module transverse.lock
# @description Portable per-key mutex (E5 / design S6.5). Serializes deploys to
#   the same environment so two `brik deploy` runs cannot interleave their
#   push-based applies. Backed by an atomic `mkdir` lock (POSIX, works on macOS
#   and Alpine alike -- flock is absent on macOS), with stale-lock reclamation
#   when the previous holder's PID is gone.
#
#   GitLab (resource_group) and Jenkins (lock step) provide the equivalent at
#   the orchestrator level; this primitive covers the local verb.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_TRANSVERSE_LOCK_LOADED:-}" ]] && return 0
_BRIK_MODULE_TRANSVERSE_LOCK_LOADED=1

# Map of held lock keys -> lock directory, so release removes the exact lock.
declare -gA _BRIK_LOCK_DIRS=()

# _transverse.lock._dir <key> - echo the lock directory path for a key.
_transverse.lock._dir() {
    local key="$1" dir safe
    dir="${BRIK_LOCK_DIR:-${BRIK_LOG_DIR:-${TMPDIR:-/tmp}}/brik-locks}"
    mkdir -p "$dir" 2>/dev/null || true
    safe="$(printf '%s' "$key" | tr -c 'A-Za-z0-9_.-' '_')"
    printf '%s/%s.lock.d' "$dir" "$safe"
}

# _transverse.lock._reclaim_if_stale <lockdir> - remove the lock when its
# recorded holder PID is no longer alive. Returns 0 when reclaimed, 1 otherwise.
_transverse.lock._reclaim_if_stale() {
    local lockdir="$1" pid
    pid="$(cat "${lockdir}/pid" 2>/dev/null || true)"
    [[ -z "$pid" ]] && return 1
    kill -0 "$pid" 2>/dev/null && return 1   # holder still alive
    rm -rf "$lockdir" 2>/dev/null || true    # holder gone -> reclaim
    return 0
}

# transverse.lock.acquire <key> [timeout_seconds]
# Acquires an exclusive lock for <key>. With no timeout (or 0) the call is
# non-blocking and fails immediately if the lock is held; with a positive
# timeout it polls up to that many seconds. Returns 0 on success, non-zero when
# the lock could not be taken.
transverse.lock.acquire() {
    local key="$1" timeout="${2:-0}" lockdir waited=0
    if [[ -z "$key" ]]; then
        log.error "transverse.lock.acquire: key is required"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi
    lockdir="$(_transverse.lock._dir "$key")"

    while true; do
        if mkdir "$lockdir" 2>/dev/null; then
            printf '%s' "$$" > "${lockdir}/pid" 2>/dev/null || true
            _BRIK_LOCK_DIRS["$key"]="$lockdir"
            return 0
        fi
        # Reclaim a lock left behind by a holder that has since died.
        _transverse.lock._reclaim_if_stale "$lockdir" && continue
        if [[ "$timeout" -le 0 ]]; then
            log.error "environment '${key}' is locked by another deploy"
            return "${BRIK_EXIT_FAILURE}"
        fi
        if [[ "$waited" -ge "$timeout" ]]; then
            log.error "timed out acquiring lock for '${key}' after ${timeout}s"
            return "${BRIK_EXIT_FAILURE}"
        fi
        sleep 1
        waited=$((waited + 1))
    done
}

# transverse.lock.release <key>
# Releases a previously-acquired lock. Idempotent: a no-op when <key> is not
# held. Always returns 0.
transverse.lock.release() {
    local key="$1" lockdir
    lockdir="${_BRIK_LOCK_DIRS[$key]:-}"
    [[ -z "$lockdir" ]] && return 0
    rm -rf "$lockdir" 2>/dev/null || true
    unset "_BRIK_LOCK_DIRS[$key]"
    return 0
}

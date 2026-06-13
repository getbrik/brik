Describe "transverse/lock.sh - per-environment mutex (E5, S6.5)"
  Include "$BRIK_PIPELINE_LIB/version-info.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/error.sh"
  Include "$BRIK_TRANSVERSE_LIB/lock.sh"

  setup() {
    LOCKDIR="$(mktemp -d)"
    export BRIK_LOCK_DIR="$LOCKDIR"
  }
  cleanup() {
    transverse.lock.release testenv 2>/dev/null || true
    transverse.lock.release envA 2>/dev/null || true
    transverse.lock.release envB 2>/dev/null || true
    rm -rf "$LOCKDIR"
    unset BRIK_LOCK_DIR 2>/dev/null || true
  }
  Before 'setup'
  After 'cleanup'

  It "acquires a free lock"
    acquire() { transverse.lock.acquire testenv; }
    When call acquire
    The status should be success
  End

  It "blocks a second acquirer on the same key, frees on release"
    probe() {
      transverse.lock.acquire testenv
      if transverse.lock.acquire testenv 2>/dev/null; then printf 'second=ok\n'; else printf 'second=blocked\n'; fi
      transverse.lock.release testenv
      if transverse.lock.acquire testenv 2>/dev/null; then printf 'after=ok\n'; else printf 'after=blocked\n'; fi
      transverse.lock.release testenv
    }
    When call probe
    The output should include "second=blocked"
    The output should include "after=ok"
    The status should be success
  End

  It "does not block across different keys"
    two() {
      transverse.lock.acquire envA && transverse.lock.acquire envB
      printf 'rc=%s\n' "$?"
      transverse.lock.release envA
      transverse.lock.release envB
    }
    When call two
    The output should include "rc=0"
  End

  It "reclaims a stale lock whose holder PID is gone"
    stale() {
      mkdir -p "${LOCKDIR}/testenv.lock.d"
      printf '%s' "999999" > "${LOCKDIR}/testenv.lock.d/pid"   # non-existent PID
      transverse.lock.acquire testenv
    }
    When call stale
    The status should be success
  End

  It "release is idempotent (no error when not held)"
    rel() { transverse.lock.release never-acquired; }
    When call rel
    The status should be success
  End

  It "rejects an empty key"
    When call transverse.lock.acquire ""
    The status should equal 2
    The stderr should include "key is required"
  End

  It "times out on a lock held by a live holder, failing rather than interleaving"
    timeout_probe() {
      # The holder PID is this process (alive), so the lock is never reclaimed
      # as stale: the second acquirer waits out the timeout and fails closed.
      transverse.lock.acquire testenv
      transverse.lock.acquire testenv 1
    }
    When call timeout_probe
    The status should equal 1
    The stderr should include "timed out acquiring lock"
  End
End

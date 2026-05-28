#shellcheck shell=bash
# Contract for lib/registry/_loader.sh
#
# Exercises the lazy loader internals not reached by registry_spec.sh:
#   - _registry._reset / _registry._reload (test helpers that drop and
#     reload the cached associative arrays)
#   - the cache-missing branch of _registry._load (auto-compile when yq+jq
#     are on PATH, "cache not found" error otherwise)
#
# Prerequisites: lib/registry/cache/registry.json must exist (run
# scripts/compile-registry.sh first; the BeforeAll guard handles it).

Describe "lib/registry/_loader.sh"
  # Ensure the cache is built before the suite runs (idempotent if up to date).
  BeforeAll '! [[ -f "$BRIK_HOME/lib/registry/cache/registry.json" ]] && "$BRIK_HOME/scripts/compile-registry.sh" >/dev/null 2>&1; true'

  Include "$BRIK_HOME/lib/registry/registry.sh"

  Describe "_registry._reload"
    It "drops the caches and reloads them, leaving stacks readable"
      When call _registry._reload
      The status should be success
    End

    It "repopulates the stack id list after a reset"
      reload_then_list() {
        _registry._reload || return $?
        registry.stack.list
      }
      When call reload_then_list
      The status should be success
      The output should include "node"
    End

    It "repopulates the stage id list after a reset"
      reload_then_stages() {
        _registry._reload || return $?
        registry.stage.list
      }
      When call reload_then_stages
      The status should be success
      The output should include "init"
    End
  End

  Describe "_registry._reset"
    It "clears the loaded marker so the next access reloads"
      reset_then_use() {
        _registry._reset
        # _BRIK_REGISTRY_LOADED must be empty after a reset.
        [[ -z "${_BRIK_REGISTRY_LOADED:-}" ]] || return 1
        # A fresh load must succeed and repopulate the registry.
        registry.use || return $?
        registry.stack.list
      }
      When call reset_then_use
      The status should be success
      The output should include "python"
    End
  End

  Describe "_registry._load with a missing cache"
    It "errors with 'cache not found' when auto-compile is not possible"
      # Point the loader at a non-existent cache file and disable the
      # auto-compile path by clearing PATH so yq/jq cannot be found.
      load_missing_cache() {
        _registry._reset
        BRIK_REGISTRY_CACHE="$(mktemp -u)" \
        PATH="/nonexistent-dir-for-brik-test" \
          _registry._load
      }
      When call load_missing_cache
      The status should equal "$BRIK_EXIT_IO_FAILURE"
      The stderr should include "cache not found"
    End

    It "auto-compiles the cache on the fly when yq and jq are on PATH"
      # A missing cache plus yq+jq available triggers the best-effort
      # compile-registry.sh invocation.
      autocompile_cache() {
        _registry._reset
        BRIK_REGISTRY_CACHE="$(mktemp -u)" \
          _registry._load
      }
      When call autocompile_cache
      The status should be success
      The stderr should include "compiling from manifests"
    End
  End
End

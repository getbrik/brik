Describe "cache.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/cache.sh"

  Describe "cache.save"
    It "returns 2 when no key specified"
      When call cache.save --paths /tmp/something
      The status should equal 2
      The stderr should include "cache key is required"
    End

    It "returns 2 when no paths specified"
      When call cache.save --key mykey
      The status should equal 2
      The stderr should include "no paths specified"
    End

    It "returns 2 for unknown option"
      When call cache.save --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "with temp workspace"
      setup_save() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/node_modules"
        printf 'dep\n' > "${TEST_WS}/node_modules/pkg.js"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
        export _CACHE_BASE_DIR="${TEST_WS}/.cache"
      }
      cleanup_save() {
        cd "$ORIG_DIR" || true
        rm -rf "$TEST_WS"
      }
      Before 'setup_save'
      After 'cleanup_save'

      It "returns 6 when source path does not exist"
        When call cache.save --key mykey --paths nonexistent
        The status should equal 6
        The stderr should include "cache source path not found"
      End

      It "saves paths to cache"
        invoke_save() {
          cache.save --key "node-deps-v1" --paths node_modules 2>/dev/null || return 1
          ls "${_CACHE_BASE_DIR}"/*.tar.gz >/dev/null 2>&1
        }
        When call invoke_save
        The status should be success
      End

      It "logs cache save"
        When call cache.save --key "test-key" --paths node_modules
        The status should be success
        The stderr should include "cache saved"
      End
    End
  End

  Describe "cache.restore"
    It "returns 2 when no key specified"
      When call cache.restore --destination /tmp/dest
      The status should equal 2
      The stderr should include "cache key is required"
    End

    It "returns 2 for unknown option"
      When call cache.restore --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "with temp workspace"
      setup_restore() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/data"
        printf 'cached\n' > "${TEST_WS}/data/file.txt"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
        export _CACHE_BASE_DIR="${TEST_WS}/.cache"
        # Pre-populate cache
        cache.save --key "restore-test" --paths data 2>/dev/null
      }
      cleanup_restore() {
        cd "$ORIG_DIR" || true
        rm -rf "$TEST_WS"
      }
      Before 'setup_restore'
      After 'cleanup_restore'

      It "returns 1 for cache miss"
        When call cache.restore --key "nonexistent-key"
        The status should equal 1
        The stderr should include "cache miss"
      End

      It "restores from cache"
        invoke_restore() {
          rm -rf data
          cache.restore --key "restore-test" --destination . 2>/dev/null || return 1
          [[ -f data/file.txt ]]
        }
        When call invoke_restore
        The status should be success
      End

      It "logs cache restore"
        invoke_restore_log() {
          cache.restore --key "restore-test" --destination "${TEST_WS}/out"
        }
        When call invoke_restore_log
        The status should be success
        The stderr should include "cache restored"
      End
    End
  End

  Describe "_cache._hash_key"
    It "produces consistent hashes"
      invoke_hash() {
        local h1 h2
        h1="$(_cache._hash_key "test-key")"
        h2="$(_cache._hash_key "test-key")"
        [[ "$h1" == "$h2" ]]
      }
      When call invoke_hash
      The status should be success
    End

    It "produces different hashes for different keys"
      invoke_diff_hash() {
        local h1 h2
        h1="$(_cache._hash_key "key-a")"
        h2="$(_cache._hash_key "key-b")"
        [[ "$h1" != "$h2" ]]
      }
      When call invoke_diff_hash
      The status should be success
    End
  End
End

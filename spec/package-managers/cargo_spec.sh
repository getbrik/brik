Describe "publish/cargo.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/publish.sh"
  Include "$BRIK_TRANSVERSE_LIB/secrets.sh"
  Include "$BRIK_PACKAGE_MANAGERS_LIB/cargo.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  brik.use() { :; }

  Describe "pkg.cargo.publish"
    It "returns 2 for unknown option"
      When call pkg.cargo.publish --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "missing Cargo.toml"
      setup_no_cargo() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "cargo" 0
        mock.activate
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_no_cargo() {
        cd "$ORIG_DIR" || true
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_cargo'
      After 'cleanup_no_cargo'

      It "returns 6 when Cargo.toml not found"
        When call pkg.cargo.publish
        The status should equal 6
        The stderr should include "required file not found"
      End
    End

    Describe "with mock cargo"
      setup_cargo() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_cargo.log"
        printf '[package]\nname = "test"\nversion = "1.0.0"\n' > "${TEST_WS}/Cargo.toml"
        mock.create_logging "cargo" "$MOCK_LOG"
        mock.activate
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_cargo() {
        cd "$ORIG_DIR" || true
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_cargo'
      After 'cleanup_cargo'

      It "runs cargo publish"
        invoke_publish() {
          pkg.cargo.publish 2>/dev/null || return 1
          grep -q "cargo publish" "$MOCK_LOG"
        }
        When call invoke_publish
        The status should be success
      End

      It "passes registry option"
        invoke_registry() {
          pkg.cargo.publish --registry "my-registry" 2>/dev/null || return 1
          grep -q "\-\-registry my-registry" "$MOCK_LOG"
        }
        When call invoke_registry
        The status should be success
      End

      It "sets CARGO_REGISTRY_TOKEN from token_var"
        invoke_token() {
          export MY_CARGO_TOKEN="cargo-token-123"
          pkg.cargo.publish --token-var "MY_CARGO_TOKEN" 2>/dev/null || return 1
          # Token should NOT appear in CLI args (security: env var only)
          ! grep -q "cargo-token-123" "$MOCK_LOG"
        }
        When call invoke_token
        The status should be success
      End

      It "uses dry-run mode"
        invoke_dryrun() {
          pkg.cargo.publish --dry-run 2>/dev/null || return 1
          grep -q "\-\-dry-run" "$MOCK_LOG"
        }
        When call invoke_dryrun
        The status should be success
      End

      It "reports success"
        When call pkg.cargo.publish
        The status should be success
        The stderr should include "cargo publish completed"
      End

      It "shows registry name in log message"
        When call pkg.cargo.publish --registry "my-registry"
        The status should be success
        The stderr should include "publishing to my-registry"
      End

      It "shows crates.io when no registry specified"
        When call pkg.cargo.publish
        The status should be success
        The stderr should include "publishing to crates.io"
      End
    End

    Describe "with index support"
      setup_cargo_index() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_cargo.log"
        printf '[package]\nname = "test"\nversion = "1.0.0"\n' > "${TEST_WS}/Cargo.toml"
        mock.create_logging "cargo" "$MOCK_LOG"
        mock.activate
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_cargo_index() {
        cd "$ORIG_DIR" || true
        mock.cleanup
        unset BRIK_PUBLISH_CARGO_INDEX 2>/dev/null
        unset CARGO_REGISTRIES_MY_REGISTRY_INDEX 2>/dev/null
        unset CARGO_REGISTRIES_BRIK_CARGO_INDEX 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_cargo_index'
      After 'cleanup_cargo_index'

      It "exports CARGO_REGISTRIES_<NAME>_INDEX when registry and index provided"
        invoke_index() {
          pkg.cargo.publish --registry "my-registry" --index "sparse+http://nexus:8081/repo/" 2>/dev/null || return 1
          grep -q "\-\-registry my-registry" "$MOCK_LOG"
        }
        When call invoke_index
        The status should be success
      End

      It "converts registry name to uppercase with underscores for env var"
        invoke_index_convert() {
          pkg.cargo.publish --registry "brik-cargo" --index "sparse+http://nexus:8081/repo/" 2>/dev/null || return 1
          # After pkg.cargo.publish, the index env var should be cleaned up
          [ -z "${CARGO_REGISTRIES_BRIK_CARGO_INDEX:-}" ]
        }
        When call invoke_index_convert
        The status should be success
      End

      It "reads index from BRIK_PUBLISH_CARGO_INDEX env var"
        invoke_env_index() {
          export BRIK_PUBLISH_CARGO_INDEX="sparse+http://nexus:8081/repo/"
          pkg.cargo.publish --registry "brik-cargo" 2>/dev/null || return 1
          [ -z "${CARGO_REGISTRIES_BRIK_CARGO_INDEX:-}" ]
        }
        When call invoke_env_index
        The status should be success
      End

      It "cleans up index env var after execution"
        invoke_cleanup() {
          export CARGO_REGISTRIES_BRIK_CARGO_INDEX=""
          pkg.cargo.publish --registry "brik-cargo" --index "sparse+http://nexus:8081/repo/" 2>/dev/null || return 1
          [ -z "${CARGO_REGISTRIES_BRIK_CARGO_INDEX:-}" ]
        }
        When call invoke_cleanup
        The status should be success
      End
    End
  End
End

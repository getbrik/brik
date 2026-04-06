Describe "publish/cargo.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/publish.sh"
  Include "$BRIK_CORE_LIB/publish/cargo.sh"

  Describe "publish.cargo.run"
    It "returns 2 for unknown option"
      When call publish.cargo.run --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "missing Cargo.toml"
      setup_no_cargo() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/cargo" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/cargo"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_no_cargo() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_cargo'
      After 'cleanup_no_cargo'

      It "returns 6 when Cargo.toml not found"
        When call publish.cargo.run
        The status should equal 6
        The stderr should include "required file not found"
      End
    End

    Describe "with mock cargo"
      setup_cargo() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_cargo.log"
        printf '[package]\nname = "test"\nversion = "1.0.0"\n' > "${TEST_WS}/Cargo.toml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/cargo" << MOCKEOF
#!/usr/bin/env bash
printf 'cargo %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/cargo"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_cargo() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_cargo'
      After 'cleanup_cargo'

      It "runs cargo publish"
        invoke_publish() {
          publish.cargo.run 2>/dev/null || return 1
          grep -q "cargo publish" "$MOCK_LOG"
        }
        When call invoke_publish
        The status should be success
      End

      It "passes registry option"
        invoke_registry() {
          publish.cargo.run --registry "my-registry" 2>/dev/null || return 1
          grep -q "\-\-registry my-registry" "$MOCK_LOG"
        }
        When call invoke_registry
        The status should be success
      End

      It "sets CARGO_REGISTRY_TOKEN from token_var"
        invoke_token() {
          export MY_CARGO_TOKEN="cargo-token-123"
          publish.cargo.run --token-var "MY_CARGO_TOKEN" 2>/dev/null || return 1
          # Token should NOT appear in CLI args (security: env var only)
          ! grep -q "cargo-token-123" "$MOCK_LOG"
        }
        When call invoke_token
        The status should be success
      End

      It "uses dry-run mode"
        invoke_dryrun() {
          publish.cargo.run --dry-run 2>/dev/null || return 1
          grep -q "\-\-dry-run" "$MOCK_LOG"
        }
        When call invoke_dryrun
        The status should be success
      End

      It "reports success"
        When call publish.cargo.run
        The status should be success
        The stderr should include "cargo publish completed"
      End
    End
  End
End

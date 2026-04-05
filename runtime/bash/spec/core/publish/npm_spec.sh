Describe "publish/npm.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/publish.sh"
  Include "$BRIK_CORE_LIB/publish/npm.sh"

  Describe "publish.npm.run"
    It "returns 2 for unknown option"
      When call publish.npm.run --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "require_tool npm failure"
      setup_no_npm() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test","version":"1.0.0"}\n' > "${TEST_WS}/package.json"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_no_npm() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_npm'
      After 'cleanup_no_npm'

      It "returns 3 when npm is not on PATH"
        When call publish.npm.run
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End

    Describe "missing package.json"
      setup_no_pkg() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/npm" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/npm"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_no_pkg() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_pkg'
      After 'cleanup_no_pkg'

      It "returns 6 when package.json not found"
        When call publish.npm.run
        The status should equal 6
        The stderr should include "required file not found"
      End
    End

    Describe "with mock npm"
      setup_npm() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_npm.log"
        printf '{"name":"test","version":"1.0.0"}\n' > "${TEST_WS}/package.json"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/npm" << MOCKEOF
#!/usr/bin/env bash
printf 'npm %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/npm"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_npm() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        unset BRIK_DRY_RUN BRIK_PUBLISH_NPM_REGISTRY BRIK_PUBLISH_NPM_TAG 2>/dev/null
        unset BRIK_PUBLISH_NPM_ACCESS BRIK_PUBLISH_NPM_TOKEN_VAR NPM_TOKEN 2>/dev/null
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_npm'
      After 'cleanup_npm'

      It "runs npm publish successfully"
        When call publish.npm.run
        The status should be success
        The stderr should include "npm publish completed successfully"
      End

      It "passes --registry option"
        invoke_registry() {
          publish.npm.run --registry "https://npm.example.com" 2>/dev/null || return 1
          grep -q "\-\-registry https://npm.example.com" "$MOCK_LOG"
        }
        When call invoke_registry
        The status should be success
      End

      It "passes --tag option"
        invoke_tag() {
          publish.npm.run --tag "beta" 2>/dev/null || return 1
          grep -q "\-\-tag beta" "$MOCK_LOG"
        }
        When call invoke_tag
        The status should be success
      End

      It "defaults tag to latest"
        invoke_default_tag() {
          publish.npm.run 2>/dev/null || return 1
          grep -q "\-\-tag latest" "$MOCK_LOG"
        }
        When call invoke_default_tag
        The status should be success
      End

      It "passes --access option"
        invoke_access() {
          publish.npm.run --access "public" 2>/dev/null || return 1
          grep -q "\-\-access public" "$MOCK_LOG"
        }
        When call invoke_access
        The status should be success
      End

      It "reads registry from BRIK_PUBLISH_NPM_REGISTRY"
        invoke_env_registry() {
          export BRIK_PUBLISH_NPM_REGISTRY="https://env.registry.com"
          publish.npm.run 2>/dev/null || return 1
          grep -q "\-\-registry https://env.registry.com" "$MOCK_LOG"
        }
        When call invoke_env_registry
        The status should be success
      End

      It "sets NPM_TOKEN from token_var"
        invoke_token() {
          export MY_NPM_TOKEN="secret-token-123"
          publish.npm.run --token-var "MY_NPM_TOKEN" 2>/dev/null || return 1
          [[ "$NPM_TOKEN" == "secret-token-123" ]]
        }
        When call invoke_token
        The status should be success
      End

      It "returns 7 when token_var references unset variable"
        When call publish.npm.run --token-var "NONEXISTENT_VAR_12345"
        The status should equal 7
        The stderr should include "is not set or empty"
      End

      It "uses --dry-run flag"
        invoke_dryrun() {
          publish.npm.run --dry-run 2>/dev/null || return 1
          grep -q "\-\-dry-run" "$MOCK_LOG"
        }
        When call invoke_dryrun
        The status should be success
      End

      It "respects BRIK_DRY_RUN env var"
        invoke_env_dryrun() {
          export BRIK_DRY_RUN="true"
          publish.npm.run 2>/dev/null || return 1
          grep -q "\-\-dry-run" "$MOCK_LOG"
        }
        When call invoke_env_dryrun
        The status should be success
      End
    End

    Describe "with failing npm"
      setup_fail() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test","version":"1.0.0"}\n' > "${TEST_WS}/package.json"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/npm" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/npm"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_fail() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 5 when npm publish fails"
        When call publish.npm.run
        The status should equal 5
        The stderr should include "npm publish failed"
      End
    End
  End
End

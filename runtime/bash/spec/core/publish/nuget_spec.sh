Describe "publish/nuget.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/publish.sh"
  Include "$BRIK_CORE_LIB/publish/nuget.sh"

  Describe "publish.nuget.run"
    It "returns 2 for unknown option"
      When call publish.nuget.run --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "no nupkg files"
      setup_no_pkg() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/dotnet" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/dotnet"
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

      It "returns 6 when no .nupkg files found"
        When call publish.nuget.run
        The status should equal 6
        The stderr should include "no .nupkg files found"
      End
    End

    Describe "with mock dotnet"
      setup_dotnet() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_dotnet.log"
        mkdir -p "${TEST_WS}/bin/Release"
        printf 'pkg\n' > "${TEST_WS}/bin/Release/Test.1.0.0.nupkg"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/dotnet" << MOCKEOF
#!/usr/bin/env bash
printf 'dotnet %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/dotnet"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_dotnet() {
        cd "$ORIG_DIR" || true
        export PATH="$ORIG_PATH"
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_dotnet'
      After 'cleanup_dotnet'

      It "runs dotnet nuget push"
        invoke_push() {
          publish.nuget.run 2>/dev/null || return 1
          grep -q "dotnet nuget push" "$MOCK_LOG"
        }
        When call invoke_push
        The status should be success
      End

      It "passes source option"
        invoke_source() {
          publish.nuget.run --source "https://api.nuget.org/v3/index.json" 2>/dev/null || return 1
          grep -q "\-\-source" "$MOCK_LOG"
        }
        When call invoke_source
        The status should be success
      End

      It "passes api key"
        invoke_key() {
          export MY_NUGET_KEY="nuget-key-123"
          publish.nuget.run --api-key-var "MY_NUGET_KEY" 2>/dev/null || return 1
          grep -q "\-\-api-key nuget-key-123" "$MOCK_LOG"
        }
        When call invoke_key
        The status should be success
      End

      It "uses dry-run mode"
        When call publish.nuget.run --dry-run
        The status should be success
        The stderr should include "[dry-run]"
      End

      It "reports success"
        When call publish.nuget.run
        The status should be success
        The stderr should include "nuget publish completed"
      End
    End
  End
End

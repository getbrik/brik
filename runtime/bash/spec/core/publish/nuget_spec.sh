Describe "publish/nuget.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/publish.sh"
  Include "$BRIK_CORE_LIB/publish/nuget.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "publish.nuget.run"
    It "returns 2 for unknown option"
      When call publish.nuget.run --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    Describe "no nupkg files"
      setup_no_pkg() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "dotnet" 0
        mock.activate
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_no_pkg() {
        cd "$ORIG_DIR" || true
        mock.cleanup
        rm -rf "$TEST_WS"
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
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_dotnet.log"
        mkdir -p "${TEST_WS}/bin/Release"
        printf 'pkg\n' > "${TEST_WS}/bin/Release/Test.1.0.0.nupkg"
        mock.create_logging "dotnet" "$MOCK_LOG"
        mock.activate
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_dotnet() {
        cd "$ORIG_DIR" || true
        mock.cleanup
        unset BRIK_DRY_RUN 2>/dev/null
        rm -rf "$TEST_WS"
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

      It "returns 5 when dotnet nuget push fails"
        setup_fail() {
          TEST_WS_FAIL="$(mktemp -d)"
          mkdir -p "${TEST_WS_FAIL}/pkg"
          printf 'pkg\n' > "${TEST_WS_FAIL}/pkg/Fail.1.0.0.nupkg"
          MOCK_BIN_FAIL="$(mktemp -d)"
          cat > "${MOCK_BIN_FAIL}/dotnet" << 'FAILEOF'
#!/usr/bin/env bash
if [[ "$1" == "nuget" ]]; then exit 1; fi
exit 0
FAILEOF
          chmod +x "${MOCK_BIN_FAIL}/dotnet"
          ORIG_PATH_F="$PATH"
          export PATH="${MOCK_BIN_FAIL}:${PATH}"
          ORIG_DIR_F="$(pwd)"
          cd "$TEST_WS_FAIL" || return 1
        }
        invoke_push_fail() {
          setup_fail
          publish.nuget.run 2>/dev/null
          local rc=$?
          cd "$ORIG_DIR_F" || true
          export PATH="$ORIG_PATH_F"
          rm -rf "$TEST_WS_FAIL" "$MOCK_BIN_FAIL"
          return $rc
        }
        When call invoke_push_fail
        The status should equal 5
      End
    End

    Describe "with HTTP source (NuGet.Config)"
      setup_http() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_dotnet.log"
        mkdir -p "${TEST_WS}/out"
        printf 'pkg\n' > "${TEST_WS}/out/Http.1.0.0.nupkg"
        mock.create_logging "dotnet" "$MOCK_LOG"
        mock.activate
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_http() {
        cd "$ORIG_DIR" || true
        mock.cleanup
        unset BRIK_DRY_RUN MY_HTTP_KEY 2>/dev/null
        rm -rf "$TEST_WS"
      }
      Before 'setup_http'
      After 'cleanup_http'

      It "creates NuGet.Config for HTTP source"
        invoke_http() {
          publish.nuget.run --source "http://nexus:8081/repository/nuget/" 2>/dev/null || return 1
          grep -q "\-\-configfile" "$MOCK_LOG" && grep -q "\-\-source brik" "$MOCK_LOG"
        }
        When call invoke_http
        The status should be success
      End

      It "uses basic auth when api key contains colon"
        invoke_basic_auth() {
          export MY_HTTP_KEY="admin:secret123"
          publish.nuget.run --source "http://nexus:8081/repository/nuget/" --api-key-var "MY_HTTP_KEY" 2>/dev/null || return 1
          # Should NOT have --api-key in log (config-based auth used instead)
          ! grep -q "\-\-api-key" "$MOCK_LOG"
        }
        When call invoke_basic_auth
        The status should be success
      End

      It "passes api-key for HTTP source without colon in key"
        invoke_http_key() {
          export MY_HTTP_KEY="plain-api-key"
          publish.nuget.run --source "http://nexus:8081/repository/nuget/" --api-key-var "MY_HTTP_KEY" 2>/dev/null || return 1
          grep -q "\-\-api-key plain-api-key" "$MOCK_LOG"
        }
        When call invoke_http_key
        The status should be success
      End

      It "dry-run with HTTP source"
        When call publish.nuget.run --source "http://nexus:8081/repository/nuget/" --dry-run
        The status should be success
        The stderr should include "[dry-run]"
      End
    End

    Describe "auto-pack success"
      setup_autopack() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_dotnet.log"
        mock.create_script "dotnet" "printf 'dotnet %s\n' \"\$*\" >> \"$MOCK_LOG\"
if [ \"\$1\" = \"pack\" ]; then
  mkdir -p \"$TEST_WS/nupkg\"
  printf 'pkg\n' > \"$TEST_WS/nupkg/Auto.1.0.0.nupkg\"
fi
exit 0"
        mock.activate
        ORIG_DIR="$(pwd)"
        cd "$TEST_WS" || return 1
      }
      cleanup_autopack() {
        cd "$ORIG_DIR" || true
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_autopack'
      After 'cleanup_autopack'

      It "auto-packs and then pushes"
        invoke_autopack() {
          publish.nuget.run 2>/dev/null || return 1
          grep -q "dotnet pack" "$MOCK_LOG" && grep -q "dotnet nuget push" "$MOCK_LOG"
        }
        When call invoke_autopack
        The status should be success
      End
    End
  End
End

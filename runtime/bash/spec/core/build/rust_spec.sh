Describe "build/rust.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/build/rust.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "build.rust.run"
    It "returns 6 for nonexistent workspace"
      When call build.rust.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    It "returns 2 for unknown option"
      When call build.rust.run "$WORKSPACES/rust-simple" --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 6 when no Cargo.toml found"
      When call build.rust.run "$WORKSPACES/unknown"
      The status should equal 6
      The stderr should include "no Cargo.toml found"
    End

    Describe "with mock cargo"
      setup_cargo() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_cargo.log"
        printf '[package]\nname = "test"\nversion = "0.1.0"\n' > "${TEST_WS}/Cargo.toml"
        mock.create_logging "cargo" "$MOCK_LOG"
        mock.activate
      }
      cleanup_cargo() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_cargo'
      After 'cleanup_cargo'

      It "succeeds and reports completion"
        When call build.rust.run "$TEST_WS"
        The status should be success
        The stderr should include "build completed successfully"
      End

      It "runs cargo build by default"
        invoke_cargo_check() {
          build.rust.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^cargo build" "$MOCK_LOG"
        }
        When call invoke_cargo_check
        The status should be success
      End
    End

    Describe "with --profile release"
      setup_cargo_release() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_cargo.log"
        printf '[package]\nname = "test"\nversion = "0.1.0"\n' > "${TEST_WS}/Cargo.toml"
        mock.create_logging "cargo" "$MOCK_LOG"
        mock.activate
      }
      cleanup_cargo_release() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_cargo_release'
      After 'cleanup_cargo_release'

      It "passes --release flag to cargo build"
        invoke_release_check() {
          build.rust.run "$TEST_WS" --profile release 2>/dev/null || return 1
          grep -q "\-\-release" "$MOCK_LOG"
        }
        When call invoke_release_check
        The status should be success
      End
    End

    Describe "with failing cargo"
      setup_cargo_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '[package]\nname = "test"\nversion = "0.1.0"\n' > "${TEST_WS}/Cargo.toml"
        mock.create_exit "cargo" 1
        mock.activate
      }
      cleanup_cargo_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_cargo_fail'
      After 'cleanup_cargo_fail'

      It "returns 5 when cargo fails"
        When call build.rust.run "$TEST_WS"
        The status should equal 5
        The stderr should include "build failed"
      End
    End

    Describe "require_tool cargo failure"
      setup_no_cargo() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '[package]\nname = "test"\nversion = "0.1.0"\n' > "${TEST_WS}/Cargo.toml"
        mock.isolate
      }
      cleanup_no_cargo() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_cargo'
      After 'cleanup_no_cargo'

      It "returns 3 when cargo is not on PATH"
        When call build.rust.run "$TEST_WS"
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End
  End
End

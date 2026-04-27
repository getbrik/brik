Describe "build/rust.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_STACKS_LIB/rust.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  Describe "stacks.rust.build"
    It "returns 6 for nonexistent workspace"
      When call stacks.rust.build "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    It "returns 2 for unknown option"
      When call stacks.rust.build "$WORKSPACES/rust-simple" --badopt foo
      The status should equal 2
      The stderr should include "unknown option"
    End

    It "returns 6 when no Cargo.toml found"
      When call stacks.rust.build "$WORKSPACES/unknown"
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
        When call stacks.rust.build "$TEST_WS"
        The status should be success
        The stderr should include "build completed successfully"
      End

      It "runs cargo build by default"
        invoke_cargo_check() {
          stacks.rust.build "$TEST_WS" 2>/dev/null || return 1
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
          stacks.rust.build "$TEST_WS" --profile release 2>/dev/null || return 1
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
        When call stacks.rust.build "$TEST_WS"
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
        When call stacks.rust.build "$TEST_WS"
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End
  End
End
Describe "test/rust.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_STACKS_LIB/rust.sh"

  Describe "stacks.rust.test_cmd"
    Include "$BRIK_HOME/spec/support/mock_helper.sh"

    It "returns cargo test for cargo framework"
      When call stacks.rust.test_cmd "cargo" "/workspace" ""
      The output should equal "cargo test"
    End

    It "returns 7 for unsupported framework"
      When call stacks.rust.test_cmd "unknown" "/workspace" ""
      The status should equal 7
      The stderr should include "unsupported Rust test framework"
    End

    Describe "with BRIK_TEST_REPORTS_ENABLED=true"
      Describe "and both cargo-nextest and cargo-llvm-cov on PATH"
        setup_both() {
          mock.setup
          mock.create_exit "cargo-nextest" 0
          mock.create_exit "cargo-llvm-cov" 0
          mock.activate
          export BRIK_TEST_REPORTS_ENABLED=true
        }
        cleanup_both() {
          mock.cleanup
          unset BRIK_TEST_REPORTS_ENABLED BRIK_TEST_COVERAGE_DIR
        }
        Before 'setup_both'
        After 'cleanup_both'

        It "drives llvm-cov with nextest and emits cobertura to coverage/coverage.xml"
          When call stacks.rust.test_cmd "cargo" "/workspace" ""
          The output should include "cargo llvm-cov"
          The output should include "--cobertura"
          The output should include "--output-path 'coverage/coverage.xml'"
          The output should include "nextest --profile ci"
          The output should include "mkdir -p 'coverage'"
        End

        It "honours BRIK_TEST_COVERAGE_DIR override"
          export BRIK_TEST_COVERAGE_DIR="custom/cov"
          When call stacks.rust.test_cmd "cargo" "/workspace" ""
          The output should include "--output-path 'custom/cov/coverage.xml'"
          The output should include "mkdir -p 'custom/cov'"
        End
      End

      Describe "and only cargo-nextest on PATH"
        setup_nextest_only() {
          mock.setup
          mock.create_exit "cargo-nextest" 0
          mock.isolate
          export BRIK_TEST_REPORTS_ENABLED=true
        }
        cleanup_nextest_only() {
          mock.cleanup
          unset BRIK_TEST_REPORTS_ENABLED
        }
        Before 'setup_nextest_only'
        After 'cleanup_nextest_only'

        It "uses nextest standalone and warns about coverage"
          When call stacks.rust.test_cmd "cargo" "/workspace" ""
          The output should equal "cargo nextest run --profile ci"
          The stderr should include "cargo-llvm-cov not installed"
        End
      End

      Describe "and only cargo-llvm-cov on PATH"
        setup_llvm_only() {
          mock.setup
          mock.create_exit "cargo-llvm-cov" 0
          mock.isolate
          export BRIK_TEST_REPORTS_ENABLED=true
        }
        cleanup_llvm_only() {
          mock.cleanup
          unset BRIK_TEST_REPORTS_ENABLED
        }
        Before 'setup_llvm_only'
        After 'cleanup_llvm_only'

        It "uses llvm-cov standalone and warns about JUnit"
          When call stacks.rust.test_cmd "cargo" "/workspace" ""
          The output should include "cargo llvm-cov --cobertura --output-path 'coverage/coverage.xml'"
          The output should not include "nextest"
          The stderr should include "cargo-nextest not installed"
        End
      End

      Describe "and neither tool on PATH"
        setup_neither() {
          mock.setup
          mock.isolate
          export BRIK_TEST_REPORTS_ENABLED=true
        }
        cleanup_neither() {
          mock.cleanup
          unset BRIK_TEST_REPORTS_ENABLED
        }
        Before 'setup_neither'
        After 'cleanup_neither'

        It "falls back to cargo test and warns about both tools"
          When call stacks.rust.test_cmd "cargo" "/workspace" ""
          The output should equal "cargo test"
          The stderr should include "cargo-nextest and cargo-llvm-cov not installed"
        End
      End
    End
  End

  Describe "stacks.rust.test"
    It "delegates to cargo test by default"
      When call stacks.rust.test "/workspace" ""
      The output should equal "cargo test"
    End
  End
End

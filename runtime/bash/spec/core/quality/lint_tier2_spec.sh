Describe "quality/lint.sh - Tier 1 and Tier 2 tool selection"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/lint.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "quality.lint.run"
    Describe "Tier 1: command failure returns 10"
      setup_cmd_fail() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "failing-lint" 1
        mock.activate
        export BRIK_QUALITY_LINT_COMMAND="failing-lint"
      }
      cleanup_cmd_fail() {
        unset BRIK_QUALITY_LINT_COMMAND
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_cmd_fail'
      After 'cleanup_cmd_fail'

      It "returns 10 when Tier 1 command fails"
        When call quality.lint.run "$TEST_WS"
        The status should equal 10
        The stderr should include "lint violations found"
      End
    End

    Describe "Tier 2: eslint with npx present"
      setup_eslint_tool() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf 'export default [];\n' > "${TEST_WS}/eslint.config.js"
        mock.create_logging "npx" "$MOCK_LOG"
        mock.activate
        export BRIK_QUALITY_LINT_TOOL="eslint"
      }
      cleanup_eslint_tool() {
        unset BRIK_QUALITY_LINT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_eslint_tool'
      After 'cleanup_eslint_tool'

      It "runs eslint via npx"
        invoke_eslint_tool() {
          quality.lint.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "eslint" "$MOCK_LOG"
        }
        When call invoke_eslint_tool
        The status should be success
      End
    End

    Describe "Tier 2: eslint npx missing"
      setup_eslint_no_npx() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf 'export default [];\n' > "${TEST_WS}/eslint.config.js"
        mock.isolate
        export BRIK_QUALITY_LINT_TOOL="eslint"
      }
      cleanup_eslint_no_npx() {
        unset BRIK_QUALITY_LINT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_eslint_no_npx'
      After 'cleanup_eslint_no_npx'

      It "returns 3 when npx not found for eslint"
        When call quality.lint.run "$TEST_WS"
        The status should equal 3
        The stderr should include "npx not found"
      End
    End

    Describe "Tier 2: eslint without config skips"
      setup_eslint_no_cfg() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "npx" 0
        mock.activate
        export BRIK_QUALITY_LINT_TOOL="eslint"
      }
      cleanup_eslint_no_cfg() {
        unset BRIK_QUALITY_LINT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_eslint_no_cfg'
      After 'cleanup_eslint_no_cfg'

      It "skips eslint when no config found (Tier 2)"
        When call quality.lint.run "$TEST_WS"
        The status should be success
        The stderr should include "no eslint config found"
      End
    End

    Describe "Tier 2: biome npx missing"
      setup_biome_no_npx() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_QUALITY_LINT_TOOL="biome"
      }
      cleanup_biome_no_npx() {
        unset BRIK_QUALITY_LINT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_biome_no_npx'
      After 'cleanup_biome_no_npx'

      It "returns 3 when npx not found for biome"
        When call quality.lint.run "$TEST_WS"
        The status should equal 3
        The stderr should include "npx not found"
      End
    End

    Describe "Tier 2: biome with --fix"
      setup_biome_fix() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "npx" "$MOCK_LOG"
        mock.activate
        export BRIK_QUALITY_LINT_TOOL="biome"
      }
      cleanup_biome_fix() {
        unset BRIK_QUALITY_LINT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_biome_fix'
      After 'cleanup_biome_fix'

      It "passes --fix flag to biome"
        invoke_biome_fix() {
          quality.lint.run "$TEST_WS" --fix 2>/dev/null || return 1
          grep -q "\-\-fix" "$MOCK_LOG"
        }
        When call invoke_biome_fix
        The status should be success
      End
    End

    Describe "Tier 2: ruff present"
      setup_ruff_tool() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "ruff" "$MOCK_LOG"
        mock.activate
        export BRIK_QUALITY_LINT_TOOL="ruff"
      }
      cleanup_ruff_tool() {
        unset BRIK_QUALITY_LINT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_ruff_tool'
      After 'cleanup_ruff_tool'

      It "runs ruff check via tool"
        invoke_ruff_tool() {
          quality.lint.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "ruff check" "$MOCK_LOG"
        }
        When call invoke_ruff_tool
        The status should be success
      End
    End

    Describe "Tier 2: ruff missing"
      setup_no_ruff_tool() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_QUALITY_LINT_TOOL="ruff"
      }
      cleanup_no_ruff_tool() {
        unset BRIK_QUALITY_LINT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_ruff_tool'
      After 'cleanup_no_ruff_tool'

      It "returns 3 when ruff not found"
        When call quality.lint.run "$TEST_WS"
        The status should equal 3
        The stderr should include "ruff not found"
      End
    End

    Describe "Tier 2: clippy present"
      setup_clippy_tool() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "cargo" "$MOCK_LOG"
        mock.activate
        export BRIK_QUALITY_LINT_TOOL="clippy"
      }
      cleanup_clippy_tool() {
        unset BRIK_QUALITY_LINT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_clippy_tool'
      After 'cleanup_clippy_tool'

      It "runs cargo clippy"
        invoke_clippy_tool() {
          quality.lint.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "cargo clippy" "$MOCK_LOG"
        }
        When call invoke_clippy_tool
        The status should be success
      End
    End

    Describe "Tier 2: clippy cargo missing"
      setup_no_clippy() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_QUALITY_LINT_TOOL="clippy"
      }
      cleanup_no_clippy() {
        unset BRIK_QUALITY_LINT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_clippy'
      After 'cleanup_no_clippy'

      It "returns 3 when cargo not found for clippy"
        When call quality.lint.run "$TEST_WS"
        The status should equal 3
        The stderr should include "cargo not found"
      End
    End

    Describe "Tier 2: checkstyle via mvn"
      setup_checkstyle_mvn() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "mvn" "$MOCK_LOG"
        mock.activate
        export BRIK_QUALITY_LINT_TOOL="checkstyle"
      }
      cleanup_checkstyle_mvn() {
        unset BRIK_QUALITY_LINT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_checkstyle_mvn'
      After 'cleanup_checkstyle_mvn'

      It "runs mvn checkstyle:check"
        invoke_checkstyle_mvn() {
          quality.lint.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "mvn -B checkstyle" "$MOCK_LOG"
        }
        When call invoke_checkstyle_mvn
        The status should be success
      End
    End

    Describe "Tier 2: checkstyle via gradle"
      setup_checkstyle_gradle() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        SAFE_BIN="$(mktemp -d)"
        mock.create_logging "gradle" "$MOCK_LOG"
        # Build a clean PATH without mvn (CI runners have /usr/bin/mvn)
        local cmd cmd_path
        for cmd in bash date tput env basename dirname cat grep sed awk printf mkdir rm mktemp tee tr cut sort head tail wc; do
          cmd_path="$(command -v "$cmd" 2>/dev/null)" && ln -sf "$cmd_path" "${SAFE_BIN}/${cmd}"
        done
        export PATH="${MOCK_BIN}:${SAFE_BIN}"
        export BRIK_QUALITY_LINT_TOOL="checkstyle"
      }
      cleanup_checkstyle_gradle() {
        unset BRIK_QUALITY_LINT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS" "$SAFE_BIN"
      }
      Before 'setup_checkstyle_gradle'
      After 'cleanup_checkstyle_gradle'

      It "runs gradle checkstyleMain"
        invoke_checkstyle_gradle() {
          quality.lint.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "gradle checkstyleMain" "$MOCK_LOG"
        }
        When call invoke_checkstyle_gradle
        The status should be success
      End
    End

    Describe "Tier 2: checkstyle neither mvn nor gradle"
      setup_no_checkstyle() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_QUALITY_LINT_TOOL="checkstyle"
      }
      cleanup_no_checkstyle() {
        unset BRIK_QUALITY_LINT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_checkstyle'
      After 'cleanup_no_checkstyle'

      It "returns 3 when neither mvn nor gradle found"
        When call quality.lint.run "$TEST_WS"
        The status should equal 3
        The stderr should include "mvn or gradle not found"
      End
    End

    Describe "Tier 2: dotnet-format present"
      setup_dotnet_tool() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "dotnet" "$MOCK_LOG"
        mock.activate
        export BRIK_QUALITY_LINT_TOOL="dotnet-format"
      }
      cleanup_dotnet_tool() {
        unset BRIK_QUALITY_LINT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_dotnet_tool'
      After 'cleanup_dotnet_tool'

      It "runs dotnet format"
        invoke_dotnet_tool() {
          quality.lint.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "dotnet format" "$MOCK_LOG"
        }
        When call invoke_dotnet_tool
        The status should be success
      End
    End

    Describe "Tier 2: dotnet-format missing"
      setup_no_dotnet_tool() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_QUALITY_LINT_TOOL="dotnet-format"
      }
      cleanup_no_dotnet_tool() {
        unset BRIK_QUALITY_LINT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_dotnet_tool'
      After 'cleanup_no_dotnet_tool'

      It "returns 3 when dotnet not found"
        When call quality.lint.run "$TEST_WS"
        The status should equal 3
        The stderr should include "dotnet not found"
      End
    End

    Describe "Tier 2: custom tool found on PATH"
      setup_raw_lint() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "my-linter" 0
        mock.activate
        export BRIK_QUALITY_LINT_TOOL="my-linter"
      }
      cleanup_raw_lint() {
        unset BRIK_QUALITY_LINT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_raw_lint'
      After 'cleanup_raw_lint'

      It "uses custom tool binary as command"
        When call quality.lint.run "$TEST_WS"
        The status should be success
        The stderr should include "lint passed"
      End
    End

    Describe "Tier 2: unknown tool not found"
      setup_missing_tool() {
        TEST_WS="$(mktemp -d)"
        export BRIK_QUALITY_LINT_TOOL="nonexistent-linter"
      }
      cleanup_missing_tool() {
        unset BRIK_QUALITY_LINT_TOOL
        rm -rf "$TEST_WS"
      }
      Before 'setup_missing_tool'
      After 'cleanup_missing_tool'

      It "returns 7 for unknown tool not on PATH"
        When call quality.lint.run "$TEST_WS"
        The status should equal 7
        The stderr should include "unknown lint tool"
      End
    End
  End
End

Describe "quality/lint.sh - 3-tier resolution"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/lint.sh"

  Describe "Tier 1: BRIK_QUALITY_LINT_COMMAND override"
    setup_cmd_override() {
      TEST_WS="$(mktemp -d)"
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/biome" << 'EOF'
#!/usr/bin/env bash
printf "biome %s\n" "$*"
exit 0
EOF
      chmod +x "${MOCK_BIN}/biome"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
      export BRIK_QUALITY_LINT_COMMAND="biome check ."
    }
    cleanup_cmd_override() {
      export PATH="$ORIG_PATH"
      unset BRIK_QUALITY_LINT_COMMAND
      rm -rf "$TEST_WS" "$MOCK_BIN"
    }
    Before 'setup_cmd_override'
    After 'cleanup_cmd_override'

    It "uses BRIK_QUALITY_LINT_COMMAND regardless of workspace content"
      When call quality.lint.run "$TEST_WS"
      The status should be success
      The stdout should be present
      The stderr should include "lint passed"
    End
  End

  Describe "Tier 2: BRIK_QUALITY_LINT_TOOL override"
    setup_tool_override() {
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/npx" << MOCKEOF
#!/usr/bin/env bash
printf 'npx %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/npx"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
      export BRIK_QUALITY_LINT_TOOL="biome"
    }
    cleanup_tool_override() {
      export PATH="$ORIG_PATH"
      unset BRIK_QUALITY_LINT_TOOL
      rm -rf "$TEST_WS" "$MOCK_BIN"
    }
    Before 'setup_tool_override'
    After 'cleanup_tool_override'

    It "uses biome when BRIK_QUALITY_LINT_TOOL=biome"
      invoke_biome() {
        quality.lint.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "biome" "$MOCK_LOG"
      }
      When call invoke_biome
      The status should be success
    End
  End

  Describe "Java lint with checkstyle"
    setup_java_lint() {
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '<project/>\n' > "${TEST_WS}/pom.xml"
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/mvn" << MOCKEOF
#!/usr/bin/env bash
printf 'mvn %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/mvn"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
    }
    cleanup_java_lint() {
      export PATH="$ORIG_PATH"
      rm -rf "$TEST_WS" "$MOCK_BIN"
    }
    Before 'setup_java_lint'
    After 'cleanup_java_lint'

    It "runs mvn checkstyle:check for Java/Maven projects"
      invoke_checkstyle() {
        quality.lint.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "checkstyle" "$MOCK_LOG"
      }
      When call invoke_checkstyle
      The status should be success
    End
  End

  Describe ".NET lint with dotnet format"
    setup_dotnet_lint() {
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${TEST_WS}/Test.csproj"
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/dotnet" << MOCKEOF
#!/usr/bin/env bash
printf 'dotnet %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
      chmod +x "${MOCK_BIN}/dotnet"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
    }
    cleanup_dotnet_lint() {
      export PATH="$ORIG_PATH"
      rm -rf "$TEST_WS" "$MOCK_BIN"
    }
    Before 'setup_dotnet_lint'
    After 'cleanup_dotnet_lint'

    It "runs dotnet format for .NET projects"
      invoke_dotnet_fmt() {
        quality.lint.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "dotnet format" "$MOCK_LOG"
      }
      When call invoke_dotnet_fmt
      The status should be success
    End
  End
End

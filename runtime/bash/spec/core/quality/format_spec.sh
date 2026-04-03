Describe "quality/format.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/format.sh"

  Describe "quality.format.run"
    It "returns 6 for nonexistent workspace"
      When call quality.format.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "unknown option"
      setup_ws() { TEST_WS="$(mktemp -d)"; }
      cleanup_ws() { rm -rf "$TEST_WS"; }
      Before 'setup_ws'
      After 'cleanup_ws'

      It "returns 2 for unknown option"
        When call quality.format.run "$TEST_WS" --badopt
        The status should equal 2
        The stderr should include "unknown option"
      End
    End

    Describe "Tier 1: BRIK_QUALITY_FORMAT_COMMAND override"
      setup_cmd_override() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/prettier" << 'EOF'
#!/usr/bin/env bash
printf "prettier %s\n" "$*"
exit 0
EOF
        chmod +x "${MOCK_BIN}/prettier"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_FORMAT_COMMAND="prettier --check ."
      }
      cleanup_cmd_override() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_FORMAT_COMMAND
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_cmd_override'
      After 'cleanup_cmd_override'

      It "uses BRIK_QUALITY_FORMAT_COMMAND as Tier 1 override"
        When call quality.format.run "$TEST_WS"
        The status should be success
        The stdout should be present
        The stderr should include "format check passed"
      End
    End

    Describe "Tier 2: BRIK_QUALITY_FORMAT_TOOL selection"
      setup_tool_selection() {
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
        export BRIK_QUALITY_FORMAT_TOOL="prettier"
      }
      cleanup_tool_selection() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_FORMAT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_tool_selection'
      After 'cleanup_tool_selection'

      It "uses prettier when BRIK_QUALITY_FORMAT_TOOL=prettier"
        invoke_check() {
          quality.format.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "prettier" "$MOCK_LOG"
        }
        When call invoke_check
        The status should be success
      End
    End

    Describe "Tier 3: auto-detect for Node.js"
      setup_node_fmt() {
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
      }
      cleanup_node_fmt() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_node_fmt'
      After 'cleanup_node_fmt'

      It "auto-detects prettier for Node.js"
        invoke_auto() {
          quality.format.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "prettier" "$MOCK_LOG"
        }
        When call invoke_auto
        The status should be success
      End
    End

    Describe "Tier 3: auto-detect for Python"
      setup_py_fmt() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/ruff" << MOCKEOF
#!/usr/bin/env bash
printf 'ruff %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/ruff"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_py_fmt() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_py_fmt'
      After 'cleanup_py_fmt'

      It "auto-detects ruff format for Python"
        invoke_py_auto() {
          quality.format.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "ruff format" "$MOCK_LOG"
        }
        When call invoke_py_auto
        The status should be success
      End
    End

    Describe "Tier 3: auto-detect for Rust"
      setup_rust_fmt() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '[package]\nname = "test"\n' > "${TEST_WS}/Cargo.toml"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/cargo" << MOCKEOF
#!/usr/bin/env bash
printf 'cargo %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/cargo"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_rust_fmt() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_rust_fmt'
      After 'cleanup_rust_fmt'

      It "auto-detects rustfmt via cargo for Rust"
        invoke_rust_fmt() {
          quality.format.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "cargo fmt" "$MOCK_LOG"
        }
        When call invoke_rust_fmt
        The status should be success
      End
    End

    Describe "Tier 1: command failure returns 10"
      setup_cmd_fail() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/failing-fmt" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/failing-fmt"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_FORMAT_COMMAND="failing-fmt"
      }
      cleanup_cmd_fail() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_FORMAT_COMMAND
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_cmd_fail'
      After 'cleanup_cmd_fail'

      It "returns 10 when Tier 1 command fails"
        When call quality.format.run "$TEST_WS"
        The status should equal 10
        The stderr should include "format violations found"
      End
    End

    Describe "--check option accepted"
      setup_check() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/npx" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/npx"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_check() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_check'
      After 'cleanup_check'

      It "accepts --check without error"
        When call quality.format.run "$TEST_WS" --check
        The status should be success
        The stderr should include "format check passed"
      End
    End

    Describe "Tier 2: biome with npx present"
      setup_biome() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/npx" << MOCKEOF
#!/usr/bin/env bash
printf 'npx %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/npx"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_FORMAT_TOOL="biome"
      }
      cleanup_biome() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_FORMAT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_biome'
      After 'cleanup_biome'

      It "runs biome format via npx"
        invoke_biome_fmt() {
          quality.format.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "biome" "$MOCK_LOG"
        }
        When call invoke_biome_fmt
        The status should be success
      End
    End

    Describe "Tier 2: biome with npx missing"
      setup_biome_no_npx() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_QUALITY_FORMAT_TOOL="biome"
      }
      cleanup_biome_no_npx() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_FORMAT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_biome_no_npx'
      After 'cleanup_biome_no_npx'

      It "returns 3 when npx not found for biome"
        When call quality.format.run "$TEST_WS"
        The status should equal 3
        The stderr should include "npx not found"
      End
    End

    Describe "Tier 2: black present"
      setup_black() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/black" << MOCKEOF
#!/usr/bin/env bash
printf 'black %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/black"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_FORMAT_TOOL="black"
      }
      cleanup_black() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_FORMAT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_black'
      After 'cleanup_black'

      It "runs black --check"
        invoke_black_fmt() {
          quality.format.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "black" "$MOCK_LOG"
        }
        When call invoke_black_fmt
        The status should be success
      End
    End

    Describe "Tier 2: black missing"
      setup_no_black() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_QUALITY_FORMAT_TOOL="black"
      }
      cleanup_no_black() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_FORMAT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_black'
      After 'cleanup_no_black'

      It "returns 3 when black not found"
        When call quality.format.run "$TEST_WS"
        The status should equal 3
        The stderr should include "black not found"
      End
    End

    Describe "Tier 2: ruff-format missing"
      setup_no_ruff() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_QUALITY_FORMAT_TOOL="ruff-format"
      }
      cleanup_no_ruff() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_FORMAT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_ruff'
      After 'cleanup_no_ruff'

      It "returns 3 when ruff not found"
        When call quality.format.run "$TEST_WS"
        The status should equal 3
        The stderr should include "ruff not found"
      End
    End

    Describe "Tier 2: rustfmt with cargo missing"
      setup_no_cargo() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_QUALITY_FORMAT_TOOL="rustfmt"
      }
      cleanup_no_cargo() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_FORMAT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_cargo'
      After 'cleanup_no_cargo'

      It "returns 3 when cargo not found for rustfmt"
        When call quality.format.run "$TEST_WS"
        The status should equal 3
        The stderr should include "cargo not found"
      End
    End

    Describe "Tier 2: dotnet-format present"
      setup_dotnet_fmt() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/dotnet" << MOCKEOF
#!/usr/bin/env bash
printf 'dotnet %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/dotnet"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_FORMAT_TOOL="dotnet-format"
      }
      cleanup_dotnet_fmt() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_FORMAT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_dotnet_fmt'
      After 'cleanup_dotnet_fmt'

      It "runs dotnet format"
        invoke_dotnet_fmt() {
          quality.format.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "dotnet format" "$MOCK_LOG"
        }
        When call invoke_dotnet_fmt
        The status should be success
      End
    End

    Describe "Tier 2: dotnet-format missing"
      setup_no_dotnet() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_QUALITY_FORMAT_TOOL="dotnet-format"
      }
      cleanup_no_dotnet() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_FORMAT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_dotnet'
      After 'cleanup_no_dotnet'

      It "returns 3 when dotnet not found"
        When call quality.format.run "$TEST_WS"
        The status should equal 3
        The stderr should include "dotnet not found"
      End
    End

    Describe "Tier 2: unknown tool as raw command"
      setup_raw_cmd() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/my-formatter" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/my-formatter"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_FORMAT_TOOL="my-formatter"
      }
      cleanup_raw_cmd() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_FORMAT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_raw_cmd'
      After 'cleanup_raw_cmd'

      It "uses unknown tool name as raw command"
        When call quality.format.run "$TEST_WS"
        The status should be success
        The stderr should include "format check passed"
      End
    End

    Describe "Tier 3: auto-detect .NET from csproj"
      setup_dotnet_auto() {
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
      cleanup_dotnet_auto() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_dotnet_auto'
      After 'cleanup_dotnet_auto'

      It "auto-detects dotnet-format for .NET projects"
        invoke_dotnet_auto() {
          quality.format.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "dotnet format" "$MOCK_LOG"
        }
        When call invoke_dotnet_auto
        The status should be success
      End
    End

    Describe "Tier 3: auto-detect Java skips google-java-format"
      setup_java_fmt() {
        TEST_WS="$(mktemp -d)"
        printf '<project/>\n' > "${TEST_WS}/pom.xml"
      }
      cleanup_java_fmt() { rm -rf "$TEST_WS"; }
      Before 'setup_java_fmt'
      After 'cleanup_java_fmt'

      It "skips format check for Java with a warning"
        When call quality.format.run "$TEST_WS"
        The status should be success
        The stderr should include "not yet automated"
      End
    End

    Describe "Tier 3: empty workspace skips"
      setup_empty_ws() { TEST_WS="$(mktemp -d)"; }
      cleanup_empty_ws() { rm -rf "$TEST_WS"; }
      Before 'setup_empty_ws'
      After 'cleanup_empty_ws'

      It "skips when no format tool detected"
        When call quality.format.run "$TEST_WS"
        The status should be success
        The stderr should include "no format tool detected"
      End
    End

    Describe "Tier 3: Node.js npx missing"
      setup_node_no_npx() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_node_no_npx() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_node_no_npx'
      After 'cleanup_node_no_npx'

      It "returns 3 when npx not found for Node.js"
        When call quality.format.run "$TEST_WS"
        The status should equal 3
        The stderr should include "npx not found"
      End
    End

    Describe "with failing formatter"
      setup_fail() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/npx" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/npx"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_fail() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_fail'
      After 'cleanup_fail'

      It "returns 10 when format check fails"
        When call quality.format.run "$TEST_WS"
        The status should equal 10
        The stderr should include "format violations found"
      End
    End
  End
End

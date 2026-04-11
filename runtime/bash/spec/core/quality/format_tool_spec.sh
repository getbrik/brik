Describe "quality/format.sh - Tier 2 tool selection"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/format.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "quality.format.run"
    Describe "Tier 2: biome with npx present"
      setup_biome() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "npx" "$MOCK_LOG"
        mock.activate
        export BRIK_QUALITY_FORMAT_TOOL="biome"
      }
      cleanup_biome() {
        unset BRIK_QUALITY_FORMAT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
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
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_QUALITY_FORMAT_TOOL="biome"
      }
      cleanup_biome_no_npx() {
        unset BRIK_QUALITY_FORMAT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
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
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "black" "$MOCK_LOG"
        mock.activate
        export BRIK_QUALITY_FORMAT_TOOL="black"
      }
      cleanup_black() {
        unset BRIK_QUALITY_FORMAT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
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
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_QUALITY_FORMAT_TOOL="black"
      }
      cleanup_no_black() {
        unset BRIK_QUALITY_FORMAT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
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
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_QUALITY_FORMAT_TOOL="ruff-format"
      }
      cleanup_no_ruff() {
        unset BRIK_QUALITY_FORMAT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
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
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_QUALITY_FORMAT_TOOL="rustfmt"
      }
      cleanup_no_cargo() {
        unset BRIK_QUALITY_FORMAT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
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
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "dotnet" "$MOCK_LOG"
        mock.activate
        export BRIK_QUALITY_FORMAT_TOOL="dotnet-format"
      }
      cleanup_dotnet_fmt() {
        unset BRIK_QUALITY_FORMAT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
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
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_QUALITY_FORMAT_TOOL="dotnet-format"
      }
      cleanup_no_dotnet() {
        unset BRIK_QUALITY_FORMAT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_dotnet'
      After 'cleanup_no_dotnet'

      It "returns 3 when dotnet not found"
        When call quality.format.run "$TEST_WS"
        The status should equal 3
        The stderr should include "dotnet not found"
      End
    End

    Describe "Tier 2: custom tool found on PATH"
      setup_raw_cmd() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "my-formatter" 0
        mock.activate
        export BRIK_QUALITY_FORMAT_TOOL="my-formatter"
      }
      cleanup_raw_cmd() {
        unset BRIK_QUALITY_FORMAT_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_raw_cmd'
      After 'cleanup_raw_cmd'

      It "uses custom tool binary as command"
        When call quality.format.run "$TEST_WS"
        The status should be success
        The stderr should include "format check passed"
      End
    End

    Describe "Tier 2: unknown tool not found"
      setup_missing_fmt() {
        TEST_WS="$(mktemp -d)"
        export BRIK_QUALITY_FORMAT_TOOL="nonexistent-formatter"
      }
      cleanup_missing_fmt() {
        unset BRIK_QUALITY_FORMAT_TOOL
        rm -rf "$TEST_WS"
      }
      Before 'setup_missing_fmt'
      After 'cleanup_missing_fmt'

      It "returns 7 for unknown tool not on PATH"
        When call quality.format.run "$TEST_WS"
        The status should equal 7
        The stderr should include "unknown format tool"
      End
    End

    Describe "Tier 3: auto-detect .NET from csproj"
      setup_dotnet_auto() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${TEST_WS}/Test.csproj"
        mock.create_logging "dotnet" "$MOCK_LOG"
        mock.activate
      }
      cleanup_dotnet_auto() {
        mock.cleanup
        rm -rf "$TEST_WS"
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
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        mock.isolate
      }
      cleanup_node_no_npx() {
        mock.cleanup
        rm -rf "$TEST_WS"
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
        mock.setup
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        mock.create_exit "npx" 1
        mock.activate
      }
      cleanup_fail() {
        mock.cleanup
        rm -rf "$TEST_WS"
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

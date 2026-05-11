Describe "verify.lint.run - config-aware skip for ruff/checkstyle/dotnet-format"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_HOME/lib/stages/verify/lint.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  # Mirrors the eslint pattern: when stack default exports the lint tool
  # but the project never opted in via a config file, skip cleanly instead
  # of running the tool with default rules and failing on environmental
  # violations the user never agreed to enforce.

  Describe "Tier 2: ruff without project config skips"
    setup_ruff_no_cfg() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      printf '[project]\nname = "x"\n' > "${TEST_WS}/pyproject.toml"
      mock.create_exit "ruff" 0
      mock.activate
      export BRIK_QUALITY_LINT_TOOL="ruff"
    }
    cleanup_ruff_no_cfg() {
      unset BRIK_QUALITY_LINT_TOOL
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_ruff_no_cfg'
    After 'cleanup_ruff_no_cfg'

    It "skips when pyproject.toml lacks [tool.ruff]"
      When call verify.lint.run "$TEST_WS"
      The status should be success
      The stderr should include "no ruff config found"
    End
  End

  Describe "Tier 2: ruff with [tool.ruff] in pyproject.toml runs"
    setup_ruff_pyproject_cfg() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '[project]\nname = "x"\n[tool.ruff]\nline-length = 100\n' > "${TEST_WS}/pyproject.toml"
      mock.create_logging "ruff" "$MOCK_LOG"
      mock.activate
      export BRIK_QUALITY_LINT_TOOL="ruff"
    }
    cleanup_ruff_pyproject_cfg() {
      unset BRIK_QUALITY_LINT_TOOL MOCK_LOG
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_ruff_pyproject_cfg'
    After 'cleanup_ruff_pyproject_cfg'

    It "runs ruff check when [tool.ruff] is present"
      invoke_ruff_pyproject() {
        verify.lint.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "ruff check" "$MOCK_LOG"
      }
      When call invoke_ruff_pyproject
      The status should be success
    End
  End

  Describe "Tier 2: ruff with ruff.toml runs"
    setup_ruff_toml_cfg() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf 'line-length = 88\n' > "${TEST_WS}/ruff.toml"
      mock.create_logging "ruff" "$MOCK_LOG"
      mock.activate
      export BRIK_QUALITY_LINT_TOOL="ruff"
    }
    cleanup_ruff_toml_cfg() {
      unset BRIK_QUALITY_LINT_TOOL MOCK_LOG
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_ruff_toml_cfg'
    After 'cleanup_ruff_toml_cfg'

    It "runs ruff check when ruff.toml exists"
      invoke_ruff_toml() {
        verify.lint.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "ruff check" "$MOCK_LOG"
      }
      When call invoke_ruff_toml
      The status should be success
    End
  End

  Describe "Tier 2: checkstyle without project config skips"
    setup_checkstyle_no_cfg() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      printf '<project></project>\n' > "${TEST_WS}/pom.xml"
      mock.create_exit "mvn" 0
      mock.activate
      export BRIK_QUALITY_LINT_TOOL="checkstyle"
    }
    cleanup_checkstyle_no_cfg() {
      unset BRIK_QUALITY_LINT_TOOL
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_checkstyle_no_cfg'
    After 'cleanup_checkstyle_no_cfg'

    It "skips when pom.xml has no checkstyle plugin and no checkstyle.xml"
      When call verify.lint.run "$TEST_WS"
      The status should be success
      The stderr should include "no checkstyle config found"
    End
  End

  Describe "Tier 2: checkstyle with checkstyle.xml runs"
    setup_checkstyle_xml_cfg() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf '<project></project>\n' > "${TEST_WS}/pom.xml"
      printf '<module name="Checker"/>\n' > "${TEST_WS}/checkstyle.xml"
      mock.create_logging "mvn" "$MOCK_LOG"
      mock.activate
      export BRIK_QUALITY_LINT_TOOL="checkstyle"
    }
    cleanup_checkstyle_xml_cfg() {
      unset BRIK_QUALITY_LINT_TOOL MOCK_LOG
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_checkstyle_xml_cfg'
    After 'cleanup_checkstyle_xml_cfg'

    It "runs mvn checkstyle:check when checkstyle.xml exists"
      invoke_checkstyle_xml() {
        verify.lint.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "mvn -B checkstyle" "$MOCK_LOG"
      }
      When call invoke_checkstyle_xml
      The status should be success
    End
  End

  Describe "Tier 2: checkstyle plugin in pom.xml runs"
    setup_checkstyle_pom_plugin() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      cat > "${TEST_WS}/pom.xml" <<'POM'
<project>
  <build><plugins><plugin>
    <artifactId>maven-checkstyle-plugin</artifactId>
  </plugin></plugins></build>
</project>
POM
      mock.create_logging "mvn" "$MOCK_LOG"
      mock.activate
      export BRIK_QUALITY_LINT_TOOL="checkstyle"
    }
    cleanup_checkstyle_pom_plugin() {
      unset BRIK_QUALITY_LINT_TOOL MOCK_LOG
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_checkstyle_pom_plugin'
    After 'cleanup_checkstyle_pom_plugin'

    It "runs mvn checkstyle:check when maven-checkstyle-plugin in pom"
      invoke_checkstyle_pom() {
        verify.lint.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "mvn -B checkstyle" "$MOCK_LOG"
      }
      When call invoke_checkstyle_pom
      The status should be success
    End
  End

  Describe "Tier 2: dotnet-format without .editorconfig skips"
    setup_dotnet_no_cfg() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      mock.create_exit "dotnet" 0
      mock.activate
      export BRIK_QUALITY_LINT_TOOL="dotnet-format"
    }
    cleanup_dotnet_no_cfg() {
      unset BRIK_QUALITY_LINT_TOOL
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_dotnet_no_cfg'
    After 'cleanup_dotnet_no_cfg'

    It "skips when no .editorconfig present"
      When call verify.lint.run "$TEST_WS"
      The status should be success
      The stderr should include "no dotnet-format config found"
    End
  End

  Describe "Tier 2: dotnet-format with .editorconfig runs"
    setup_dotnet_with_cfg() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      MOCK_LOG="${TEST_WS}/mock.log"
      printf 'root = true\n' > "${TEST_WS}/.editorconfig"
      mock.create_logging "dotnet" "$MOCK_LOG"
      mock.activate
      export BRIK_QUALITY_LINT_TOOL="dotnet-format"
    }
    cleanup_dotnet_with_cfg() {
      unset BRIK_QUALITY_LINT_TOOL MOCK_LOG
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_dotnet_with_cfg'
    After 'cleanup_dotnet_with_cfg'

    It "runs dotnet format when .editorconfig exists"
      invoke_dotnet_with_cfg() {
        verify.lint.run "$TEST_WS" 2>/dev/null || return 1
        grep -q "dotnet format" "$MOCK_LOG"
      }
      When call invoke_dotnet_with_cfg
      The status should be success
    End
  End

  Describe "Tier 3: ruff auto-detect without [tool.ruff] skips"
    setup_tier3_ruff_no_cfg() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      printf '[project]\nname = "x"\n' > "${TEST_WS}/pyproject.toml"
      mock.create_exit "ruff" 0
      mock.activate
    }
    cleanup_tier3_ruff_no_cfg() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_tier3_ruff_no_cfg'
    After 'cleanup_tier3_ruff_no_cfg'

    It "skips when pyproject.toml lacks [tool.ruff] in auto-detect"
      When call verify.lint.run "$TEST_WS"
      The status should be success
      The stderr should include "no ruff config found"
    End
  End

  Describe "Tier 3: maven auto-detect without checkstyle plugin skips"
    setup_tier3_mvn_no_cfg() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      printf '<project></project>\n' > "${TEST_WS}/pom.xml"
      mock.create_exit "mvn" 0
      mock.activate
    }
    cleanup_tier3_mvn_no_cfg() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_tier3_mvn_no_cfg'
    After 'cleanup_tier3_mvn_no_cfg'

    It "skips when pom.xml has no checkstyle plugin in auto-detect"
      When call verify.lint.run "$TEST_WS"
      The status should be success
      The stderr should include "no checkstyle config found"
    End
  End

  Describe "Tier 3: dotnet auto-detect without .editorconfig skips"
    setup_tier3_dotnet_no_cfg() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${TEST_WS}/Test.csproj"
      mock.create_exit "dotnet" 0
      mock.activate
    }
    cleanup_tier3_dotnet_no_cfg() {
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_tier3_dotnet_no_cfg'
    After 'cleanup_tier3_dotnet_no_cfg'

    It "skips when no .editorconfig present in auto-detect"
      When call verify.lint.run "$TEST_WS"
      The status should be success
      The stderr should include "no dotnet-format config found"
    End
  End
End

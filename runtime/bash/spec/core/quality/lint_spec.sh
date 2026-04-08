Describe "quality/lint.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/lint.sh"

  Describe "quality.lint.run"
    It "returns 6 for nonexistent workspace"
      When call quality.lint.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "unknown option"
      setup_ws() { TEST_WS="$(mktemp -d)"; }
      cleanup_ws() { rm -rf "$TEST_WS"; }
      Before 'setup_ws'
      After 'cleanup_ws'

      It "returns 2 for unknown option"
        When call quality.lint.run "$TEST_WS" --badopt
        The status should equal 2
        The stderr should include "unknown option"
      End
    End

    Describe "with Node.js workspace and mock npx"
      setup_node_lint() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_npx.log"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        printf 'export default [];\n' > "${TEST_WS}/eslint.config.js"
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
      cleanup_node_lint() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_node_lint'
      After 'cleanup_node_lint'

      It "runs eslint for Node.js projects"
        invoke_eslint() {
          quality.lint.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^npx eslint" "$MOCK_LOG"
        }
        When call invoke_eslint
        The status should be success
      End

      It "passes --fix flag to eslint"
        invoke_fix() {
          quality.lint.run "$TEST_WS" --fix 2>/dev/null || return 1
          grep -q "\-\-fix" "$MOCK_LOG"
        }
        When call invoke_fix
        The status should be success
      End

      It "succeeds and reports lint passed"
        When call quality.lint.run "$TEST_WS"
        The status should be success
        The stderr should include "lint passed"
      End
    End

    Describe "Node.js npx not found"
      setup_no_npx() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        printf 'export default [];\n' > "${TEST_WS}/eslint.config.js"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_no_npx() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_npx'
      After 'cleanup_no_npx'

      It "returns 3 when npx is not available"
        When call quality.lint.run "$TEST_WS"
        The status should equal 3
        The stderr should include "npx not found"
      End
    End

    Describe "with Python workspace and mock ruff"
      setup_py_lint() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_ruff.log"
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
      cleanup_py_lint() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_py_lint'
      After 'cleanup_py_lint'

      It "runs ruff check for Python projects"
        invoke_ruff() {
          quality.lint.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^ruff check" "$MOCK_LOG"
        }
        When call invoke_ruff
        The status should be success
      End

      It "passes --fix flag to ruff"
        invoke_ruff_fix() {
          quality.lint.run "$TEST_WS" --fix 2>/dev/null || return 1
          grep -q "\-\-fix" "$MOCK_LOG"
        }
        When call invoke_ruff_fix
        The status should be success
      End
    End

    Describe "Python ruff not found"
      setup_no_ruff() {
        TEST_WS="$(mktemp -d)"
        printf '[project]\nname = "test"\n' > "${TEST_WS}/pyproject.toml"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_no_ruff() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_ruff'
      After 'cleanup_no_ruff'

      It "returns 3 when ruff is not available"
        When call quality.lint.run "$TEST_WS"
        The status should equal 3
        The stderr should include "ruff not found"
      End
    End

    Describe "with Rust workspace and mock cargo"
      setup_rust_lint() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock_cargo.log"
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
      cleanup_rust_lint() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_rust_lint'
      After 'cleanup_rust_lint'

      It "runs cargo clippy for Rust projects"
        invoke_clippy() {
          quality.lint.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^cargo clippy" "$MOCK_LOG"
        }
        When call invoke_clippy
        The status should be success
      End
    End

    Describe "with Java workspace and no mvn"
      setup_java_lint() {
        TEST_WS="$(mktemp -d)"
        printf '<project/>\n' > "${TEST_WS}/pom.xml"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_java_lint() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_java_lint'
      After 'cleanup_java_lint'

      It "skips Java when mvn not found"
        When call quality.lint.run "$TEST_WS"
        The status should be success
        The stderr should include "mvn not found"
      End
    End

    Describe "Node.js without eslint config"
      setup_no_eslint_cfg() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
      }
      cleanup_no_eslint_cfg() { rm -rf "$TEST_WS"; }
      Before 'setup_no_eslint_cfg'
      After 'cleanup_no_eslint_cfg'

      It "skips lint when no eslint config found"
        When call quality.lint.run "$TEST_WS"
        The status should be success
        The stderr should include "no eslint config found"
      End
    End

    Describe "Tier 2: eslint without config skips"
      setup_eslint_no_cfg() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/npx" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/npx"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_LINT_TOOL="eslint"
      }
      cleanup_eslint_no_cfg() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_LINT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_eslint_no_cfg'
      After 'cleanup_eslint_no_cfg'

      It "skips eslint when no config found (Tier 2)"
        When call quality.lint.run "$TEST_WS"
        The status should be success
        The stderr should include "no eslint config found"
      End
    End

    Describe "with unknown workspace"
      setup_empty() { TEST_WS="$(mktemp -d)"; }
      cleanup_empty() { rm -rf "$TEST_WS"; }
      Before 'setup_empty'
      After 'cleanup_empty'

      It "returns 3 when no stack detected"
        When call quality.lint.run "$TEST_WS"
        The status should equal 3
        The stderr should include "cannot detect stack"
      End
    End

    Describe "Tier 1: command failure returns 10"
      setup_cmd_fail() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/failing-lint" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
        chmod +x "${MOCK_BIN}/failing-lint"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_LINT_COMMAND="failing-lint"
      }
      cleanup_cmd_fail() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_LINT_COMMAND
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf 'export default [];\n' > "${TEST_WS}/eslint.config.js"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/npx" << MOCKEOF
#!/usr/bin/env bash
printf 'npx %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/npx"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_LINT_TOOL="eslint"
      }
      cleanup_eslint_tool() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_LINT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        printf 'export default [];\n' > "${TEST_WS}/eslint.config.js"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_QUALITY_LINT_TOOL="eslint"
      }
      cleanup_eslint_no_npx() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_LINT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_eslint_no_npx'
      After 'cleanup_eslint_no_npx'

      It "returns 3 when npx not found for eslint"
        When call quality.lint.run "$TEST_WS"
        The status should equal 3
        The stderr should include "npx not found"
      End
    End

    Describe "Tier 2: biome npx missing"
      setup_biome_no_npx() {
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_QUALITY_LINT_TOOL="biome"
      }
      cleanup_biome_no_npx() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_LINT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        export BRIK_QUALITY_LINT_TOOL="biome"
      }
      cleanup_biome_fix() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_LINT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/ruff" << MOCKEOF
#!/usr/bin/env bash
printf 'ruff %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/ruff"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_LINT_TOOL="ruff"
      }
      cleanup_ruff_tool() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_LINT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_QUALITY_LINT_TOOL="ruff"
      }
      cleanup_no_ruff_tool() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_LINT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/cargo" << MOCKEOF
#!/usr/bin/env bash
printf 'cargo %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/cargo"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_LINT_TOOL="clippy"
      }
      cleanup_clippy_tool() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_LINT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_QUALITY_LINT_TOOL="clippy"
      }
      cleanup_no_clippy() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_LINT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/mvn" << MOCKEOF
#!/usr/bin/env bash
printf 'mvn %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/mvn"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_LINT_TOOL="checkstyle"
      }
      cleanup_checkstyle_mvn() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_LINT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        MOCK_BIN="$(mktemp -d)"
        SAFE_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/gradle" << MOCKEOF
#!/usr/bin/env bash
printf 'gradle %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/gradle"
        # Build a clean PATH without mvn (CI runners have /usr/bin/mvn)
        local cmd cmd_path
        for cmd in bash date tput env basename dirname cat grep sed awk printf mkdir rm mktemp tee tr cut sort head tail wc; do
          cmd_path="$(command -v "$cmd" 2>/dev/null)" && ln -sf "$cmd_path" "${SAFE_BIN}/${cmd}"
        done
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${SAFE_BIN}"
        export BRIK_QUALITY_LINT_TOOL="checkstyle"
      }
      cleanup_checkstyle_gradle() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_LINT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN" "$SAFE_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_QUALITY_LINT_TOOL="checkstyle"
      }
      cleanup_no_checkstyle() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_LINT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        export BRIK_QUALITY_LINT_TOOL="dotnet-format"
      }
      cleanup_dotnet_tool() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_LINT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
        export BRIK_QUALITY_LINT_TOOL="dotnet-format"
      }
      cleanup_no_dotnet_tool() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_LINT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
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
        TEST_WS="$(mktemp -d)"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/my-linter" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "${MOCK_BIN}/my-linter"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
        export BRIK_QUALITY_LINT_TOOL="my-linter"
      }
      cleanup_raw_lint() {
        export PATH="$ORIG_PATH"
        unset BRIK_QUALITY_LINT_TOOL
        rm -rf "$TEST_WS" "$MOCK_BIN"
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

    Describe "Tier 3: Gradle auto-detect with gradle present"
      setup_gradle_auto() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf 'apply plugin: "java"\n' > "${TEST_WS}/build.gradle"
        MOCK_BIN="$(mktemp -d)"
        cat > "${MOCK_BIN}/gradle" << MOCKEOF
#!/usr/bin/env bash
printf 'gradle %s\n' "\$*" >> "$MOCK_LOG"
exit 0
MOCKEOF
        chmod +x "${MOCK_BIN}/gradle"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_gradle_auto() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_gradle_auto'
      After 'cleanup_gradle_auto'

      It "auto-detects gradle checkstyleMain"
        invoke_gradle_auto() {
          quality.lint.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "gradle checkstyleMain" "$MOCK_LOG"
        }
        When call invoke_gradle_auto
        The status should be success
      End
    End

    Describe "Tier 3: Gradle auto-detect with gradle missing"
      setup_gradle_missing() {
        TEST_WS="$(mktemp -d)"
        printf 'apply plugin: "java"\n' > "${TEST_WS}/build.gradle"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_gradle_missing() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_gradle_missing'
      After 'cleanup_gradle_missing'

      It "skips when gradle not found"
        When call quality.lint.run "$TEST_WS"
        The status should be success
        The stderr should include "gradle not found"
      End
    End

    Describe "Tier 3: .NET dotnet missing"
      setup_dotnet_missing() {
        TEST_WS="$(mktemp -d)"
        printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "${TEST_WS}/Test.csproj"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_dotnet_missing() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_dotnet_missing'
      After 'cleanup_dotnet_missing'

      It "returns 3 when dotnet not found for .NET"
        When call quality.lint.run "$TEST_WS"
        The status should equal 3
        The stderr should include "dotnet not found"
      End
    End

    Describe "Tier 3: Rust cargo missing"
      setup_rust_no_cargo() {
        TEST_WS="$(mktemp -d)"
        printf '[package]\nname = "test"\n' > "${TEST_WS}/Cargo.toml"
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}"
      }
      cleanup_rust_no_cargo() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_rust_no_cargo'
      After 'cleanup_rust_no_cargo'

      It "returns 3 when cargo not found for Rust"
        When call quality.lint.run "$TEST_WS"
        The status should equal 3
        The stderr should include "cargo not found"
      End
    End

    Describe "Tier 3: Python via setup.py"
      setup_setuppy() {
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        printf 'from setuptools import setup\n' > "${TEST_WS}/setup.py"
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
      cleanup_setuppy() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_setuppy'
      After 'cleanup_setuppy'

      It "detects Python from setup.py"
        invoke_setuppy() {
          quality.lint.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "ruff check" "$MOCK_LOG"
        }
        When call invoke_setuppy
        The status should be success
      End
    End

    Describe "with failing linter"
      setup_fail() {
        TEST_WS="$(mktemp -d)"
        printf '{"name":"test"}\n' > "${TEST_WS}/package.json"
        printf 'export default [];\n' > "${TEST_WS}/eslint.config.js"
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

      It "returns 10 when lint fails"
        When call quality.lint.run "$TEST_WS"
        The status should equal 10
        The stderr should include "lint violations found"
      End
    End
  End
End

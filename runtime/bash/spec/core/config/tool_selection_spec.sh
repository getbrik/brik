## TDD RED: Tests for tool selection - config module changes (Phase 1)
# These tests should FAIL until config modules are updated.

Describe "Tool selection: config module build_tool defaults"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_CORE_LIB/config.sh"

  # =========================================================================
  # build_tool defaults per stack
  # =========================================================================

  Describe "config.node.default build_tool"
    Include "$BRIK_CORE_LIB/config/node.sh"

    It "returns 'auto' for build_tool"
      When call config.node.default "build_tool"
      The output should equal "auto"
      The status should be success
    End
  End

  Describe "config.java.default build_tool"
    Include "$BRIK_CORE_LIB/config/java.sh"

    It "returns 'auto' for build_tool"
      When call config.java.default "build_tool"
      The output should equal "auto"
      The status should be success
    End
  End

  Describe "config.python.default build_tool"
    Include "$BRIK_CORE_LIB/config/python.sh"

    It "returns 'auto' for build_tool"
      When call config.python.default "build_tool"
      The output should equal "auto"
      The status should be success
    End

    It "returns empty string for build_command (delegate to tool)"
      When call config.python.default "build_command"
      The output should equal ""
      The status should be success
    End
  End

  Describe "config.dotnet.default build_tool"
    Include "$BRIK_CORE_LIB/config/dotnet.sh"

    It "returns 'auto' for build_tool"
      When call config.dotnet.default "build_tool"
      The output should equal "auto"
      The status should be success
    End
  End

  Describe "config.rust.default build_tool"
    Include "$BRIK_CORE_LIB/config/rust.sh"

    It "returns 'auto' for build_tool"
      When call config.rust.default "build_tool"
      The output should equal "auto"
      The status should be success
    End
  End
End

Describe "Tool selection: config.export_build_vars exports BRIK_BUILD_TOOL"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_CORE_LIB/config.sh"

  # =========================================================================
  # BRIK_BUILD_TOOL from brik.yml build.tool
  # =========================================================================

  Describe "when build.tool is set in brik.yml"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: python
build:
  tool: uv
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() {
      rm -f "$TEMP_CONFIG"
      unset BRIK_BUILD_TOOL BRIK_BUILD_COMMAND BRIK_BUILD_STACK BRIK_CONFIG_FILE
    }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_BUILD_TOOL as uv"
      export_and_check() {
        config.export_build_vars
        printf '%s' "${BRIK_BUILD_TOOL:-UNSET}"
      }
      When call export_and_check
      The output should equal "uv"
    End
  End

  Describe "when build.tool is not set and stack has default"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: rust
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() {
      rm -f "$TEMP_CONFIG"
      unset BRIK_BUILD_TOOL BRIK_BUILD_COMMAND BRIK_BUILD_STACK BRIK_CONFIG_FILE
    }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_BUILD_TOOL from stack default (auto)"
      export_and_check() {
        config.export_build_vars
        printf '%s' "${BRIK_BUILD_TOOL:-UNSET}"
      }
      When call export_and_check
      The output should equal "auto"
    End
  End

  Describe "when build.tool is not set and stack is auto"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() {
      rm -f "$TEMP_CONFIG"
      unset BRIK_BUILD_TOOL BRIK_BUILD_COMMAND BRIK_BUILD_STACK BRIK_CONFIG_FILE
    }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports empty BRIK_BUILD_TOOL"
      export_and_check() {
        config.export_build_vars
        printf '%s' "${BRIK_BUILD_TOOL:-}"
      }
      When call export_and_check
      The output should equal ""
    End
  End

  # =========================================================================
  # 3-tier precedence: command > tool > auto
  # =========================================================================

  Describe "3-tier precedence: command takes priority over tool"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: python
build:
  command: make build
  tool: uv
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() {
      rm -f "$TEMP_CONFIG"
      unset BRIK_BUILD_TOOL BRIK_BUILD_COMMAND BRIK_BUILD_STACK BRIK_CONFIG_FILE
    }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports both BRIK_BUILD_COMMAND and BRIK_BUILD_TOOL"
      export_and_check() {
        config.export_build_vars
        printf '%s|%s' "${BRIK_BUILD_COMMAND:-}" "${BRIK_BUILD_TOOL:-}"
      }
      When call export_and_check
      The output should equal "make build|uv"
    End
  End
End

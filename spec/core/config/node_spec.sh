Describe "config/node.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_CORE_LIB/config.sh"
  Include "$BRIK_CORE_LIB/config/node.sh"

  Describe "config.node.default"
    It "returns empty string for build_command"
      When call config.node.default "build_command"
      The output should equal ""
      The status should be success
    End

    It "returns 'jest' for test_framework"
      When call config.node.default "test_framework"
      The output should equal "jest"
    End

    It "returns 'eslint' for lint_tool"
      When call config.node.default "lint_tool"
      The output should equal "eslint"
    End

    It "returns 'prettier' for format_tool"
      When call config.node.default "format_tool"
      The output should equal "prettier"
    End

    It "returns 1 for unknown setting"
      When call config.node.default "unknown_setting"
      The status should equal 1
    End
  End

  Describe "config.node.export_build_vars"
    Describe "when node_version is configured"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
build:
  node_version: "20.11.0"
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() {
        rm -f "$TEMP_CONFIG"
        unset BRIK_BUILD_NODE_VERSION BRIK_CONFIG_FILE
      }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_BUILD_NODE_VERSION"
        export_and_check() {
          config.node.export_build_vars
          printf '%s' "${BRIK_BUILD_NODE_VERSION:-}"
        }
        When call export_and_check
        The output should equal "20.11.0"
      End
    End

    Describe "when node_version is not configured"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() {
        rm -f "$TEMP_CONFIG"
        unset BRIK_CONFIG_FILE
      }
      Before 'setup_config'
      After 'cleanup_config'

      It "does not export BRIK_BUILD_NODE_VERSION"
        export_and_check() {
          unset BRIK_BUILD_NODE_VERSION 2>/dev/null || true
          config.node.export_build_vars
          printf '%s' "${BRIK_BUILD_NODE_VERSION:-UNSET}"
        }
        When call export_and_check
        The output should equal "UNSET"
      End
    End
  End

  Describe "config.node.validate_coherence"

    Describe "node + jest in devDependencies"
      setup_coherent_jest() {
        COHERENT_WS="$(mktemp -d)"
        printf '{"name":"test","devDependencies":{"jest":"^29.0.0"}}\n' > "${COHERENT_WS}/package.json"
        COHERENT_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\ntest:\n  framework: jest\n' > "$COHERENT_CONFIG"
        export BRIK_BUILD_STACK="node"
        export BRIK_TEST_FRAMEWORK="jest"
        export BRIK_CONFIG_FILE="$COHERENT_CONFIG"
      }
      cleanup_coherent_jest() {
        rm -rf "$COHERENT_WS" "$COHERENT_CONFIG"
        unset BRIK_BUILD_STACK BRIK_TEST_FRAMEWORK BRIK_CONFIG_FILE
      }
      Before 'setup_coherent_jest'
      After 'cleanup_coherent_jest'

      It "passes when jest is in devDependencies"
        When call config.node.validate_coherence "$COHERENT_WS"
        The status should be success
      End
    End

    Describe "node + jest not in deps + custom test script"
      setup_incoherent_jest() {
        INCOHERENT_WS="$(mktemp -d)"
        printf '{"name":"test","scripts":{"test":"node test/index.test.js"}}\n' > "${INCOHERENT_WS}/package.json"
        INCOHERENT_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$INCOHERENT_CONFIG"
        export BRIK_BUILD_STACK="node"
        export BRIK_TEST_FRAMEWORK="jest"
        export BRIK_CONFIG_FILE="$INCOHERENT_CONFIG"
      }
      cleanup_incoherent_jest() {
        rm -rf "$INCOHERENT_WS" "$INCOHERENT_CONFIG"
        unset BRIK_BUILD_STACK BRIK_TEST_FRAMEWORK BRIK_CONFIG_FILE
      }
      Before 'setup_incoherent_jest'
      After 'cleanup_incoherent_jest'

      It "fails with exit 7 and descriptive error"
        When call config.node.validate_coherence "$INCOHERENT_WS"
        The status should equal 7
        The error should include "config mismatch"
        The error should include "jest is not in package.json"
        The error should include "stack default"
      End
    End

    Describe "node + framework=npm"
      setup_npm_framework() {
        NPM_WS="$(mktemp -d)"
        printf '{"name":"test","scripts":{"test":"node test/index.test.js"}}\n' > "${NPM_WS}/package.json"
        export BRIK_BUILD_STACK="node"
        export BRIK_TEST_FRAMEWORK="npm"
      }
      cleanup_npm_framework() {
        rm -rf "$NPM_WS"
        unset BRIK_BUILD_STACK BRIK_TEST_FRAMEWORK
      }
      Before 'setup_npm_framework'
      After 'cleanup_npm_framework'

      It "passes (no jest coherence check needed)"
        When call config.node.validate_coherence "$NPM_WS"
        The status should be success
      End
    End

    Describe "node + jest mismatch from brik.yml"
      setup_explicit_jest() {
        EXPLICIT_WS="$(mktemp -d)"
        printf '{"name":"test","scripts":{"test":"mocha"}}\n' > "${EXPLICIT_WS}/package.json"
        EXPLICIT_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\ntest:\n  framework: jest\n' > "$EXPLICIT_CONFIG"
        export BRIK_BUILD_STACK="node"
        export BRIK_TEST_FRAMEWORK="jest"
        export BRIK_CONFIG_FILE="$EXPLICIT_CONFIG"
      }
      cleanup_explicit_jest() {
        rm -rf "$EXPLICIT_WS" "$EXPLICIT_CONFIG"
        unset BRIK_BUILD_STACK BRIK_TEST_FRAMEWORK BRIK_CONFIG_FILE
      }
      Before 'setup_explicit_jest'
      After 'cleanup_explicit_jest'

      It "reports brik.yml as the source"
        When call config.node.validate_coherence "$EXPLICIT_WS"
        The status should equal 7
        The error should include "brik.yml"
      End
    End

    Describe "no package.json"
      setup_no_pkg() {
        NO_PKG_WS="$(mktemp -d)"
        export BRIK_TEST_FRAMEWORK="jest"
      }
      cleanup_no_pkg() {
        rm -rf "$NO_PKG_WS"
        unset BRIK_TEST_FRAMEWORK
      }
      Before 'setup_no_pkg'
      After 'cleanup_no_pkg'

      It "passes when package.json is missing"
        When call config.node.validate_coherence "$NO_PKG_WS"
        The status should be success
      End
    End

    Describe "jest in dependencies (not devDependencies)"
      setup_jest_deps() {
        JEST_DEPS_WS="$(mktemp -d)"
        printf '{"name":"test","dependencies":{"jest":"^29.0.0"}}\n' > "${JEST_DEPS_WS}/package.json"
        JEST_DEPS_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$JEST_DEPS_CONFIG"
        export BRIK_TEST_FRAMEWORK="jest"
        export BRIK_CONFIG_FILE="$JEST_DEPS_CONFIG"
      }
      cleanup_jest_deps() {
        rm -rf "$JEST_DEPS_WS" "$JEST_DEPS_CONFIG"
        unset BRIK_TEST_FRAMEWORK BRIK_CONFIG_FILE
      }
      Before 'setup_jest_deps'
      After 'cleanup_jest_deps'

      It "passes when jest is in dependencies"
        When call config.node.validate_coherence "$JEST_DEPS_WS"
        The status should be success
      End
    End
  End
End

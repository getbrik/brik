## TDD RED: Tests for new config exports (test.command, quality.*.command, security.*_tool)

Describe "Tool selection: config.export_test_vars exports BRIK_TEST_COMMAND"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_CORE_LIB/config.sh"

  Describe "when test.command is set in brik.yml"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
test:
  command: npm run test:ci
  framework: jest
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() {
      rm -f "$TEMP_CONFIG"
      unset BRIK_TEST_COMMAND BRIK_TEST_FRAMEWORK BRIK_CONFIG_FILE
    }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_TEST_COMMAND"
      export_and_check() {
        config.export_test_vars
        printf '%s' "${BRIK_TEST_COMMAND:-UNSET}"
      }
      When call export_and_check
      The output should equal "npm run test:ci"
    End
  End

  Describe "when test.command is not set"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
test:
  framework: jest
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() {
      rm -f "$TEMP_CONFIG"
      unset BRIK_TEST_COMMAND BRIK_TEST_FRAMEWORK BRIK_CONFIG_FILE
    }
    Before 'setup_config'
    After 'cleanup_config'

    It "does not export BRIK_TEST_COMMAND"
      export_and_check() {
        unset BRIK_TEST_COMMAND 2>/dev/null || true
        config.export_test_vars
        printf '%s' "${BRIK_TEST_COMMAND:-UNSET}"
      }
      When call export_and_check
      The output should equal "UNSET"
    End
  End
End

Describe "Tool selection: config.export_quality_vars exports command overrides"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_CORE_LIB/config.sh"

  Describe "when quality command overrides are set"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
quality:
  lint:
    tool: biome
    command: npx biome check .
  format:
    tool: biome
    command: npx biome format . --check
  sast:
    tool: semgrep
    command: semgrep scan --config p/security-audit .
  deps:
    tool: npm-audit
    command: npm audit --production
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() {
      rm -f "$TEMP_CONFIG"
      unset BRIK_QUALITY_LINT_COMMAND BRIK_QUALITY_FORMAT_COMMAND \
            BRIK_QUALITY_SAST_COMMAND BRIK_QUALITY_DEPS_COMMAND \
            BRIK_QUALITY_LINT_TOOL BRIK_QUALITY_FORMAT_TOOL \
            BRIK_QUALITY_SAST_TOOL BRIK_QUALITY_DEPS_TOOL \
            BRIK_QUALITY_ENABLED BRIK_CONFIG_FILE
    }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_QUALITY_LINT_COMMAND"
      export_and_check() {
        config.export_quality_vars
        printf '%s' "${BRIK_QUALITY_LINT_COMMAND:-UNSET}"
      }
      When call export_and_check
      The output should equal "npx biome check ."
    End

    It "exports BRIK_QUALITY_FORMAT_COMMAND"
      export_and_check() {
        config.export_quality_vars
        printf '%s' "${BRIK_QUALITY_FORMAT_COMMAND:-UNSET}"
      }
      When call export_and_check
      The output should equal "npx biome format . --check"
    End

    It "exports BRIK_QUALITY_SAST_COMMAND"
      export_and_check() {
        config.export_quality_vars
        printf '%s' "${BRIK_QUALITY_SAST_COMMAND:-UNSET}"
      }
      When call export_and_check
      The output should equal "semgrep scan --config p/security-audit ."
    End

    It "exports BRIK_QUALITY_DEPS_COMMAND"
      export_and_check() {
        config.export_quality_vars
        printf '%s' "${BRIK_QUALITY_DEPS_COMMAND:-UNSET}"
      }
      When call export_and_check
      The output should equal "npm audit --production"
    End
  End

  Describe "when quality command overrides are not set"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
quality:
  lint:
    tool: eslint
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() {
      rm -f "$TEMP_CONFIG"
      unset BRIK_QUALITY_LINT_COMMAND BRIK_QUALITY_FORMAT_COMMAND \
            BRIK_QUALITY_SAST_COMMAND BRIK_QUALITY_DEPS_COMMAND \
            BRIK_QUALITY_LINT_TOOL BRIK_QUALITY_ENABLED BRIK_CONFIG_FILE
    }
    Before 'setup_config'
    After 'cleanup_config'

    It "does not export command vars when not configured"
      export_and_check() {
        unset BRIK_QUALITY_LINT_COMMAND BRIK_QUALITY_FORMAT_COMMAND 2>/dev/null || true
        config.export_quality_vars
        printf '%s|%s' "${BRIK_QUALITY_LINT_COMMAND:-UNSET}" "${BRIK_QUALITY_FORMAT_COMMAND:-UNSET}"
      }
      When call export_and_check
      The output should equal "UNSET|UNSET"
    End
  End
End

Describe "Tool selection: config.export_security_vars exports tool fields"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_CORE_LIB/config.sh"

  Describe "when security tool fields are set"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
security:
  enabled: true
  dependency_scan: true
  dependency_scan_tool: npm-audit
  secret_scan: true
  secret_scan_tool: gitleaks
  container_scan: true
  container_scan_tool: trivy
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() {
      rm -f "$TEMP_CONFIG"
      unset BRIK_SECURITY_ENABLED BRIK_SECURITY_DEPENDENCY_SCAN \
            BRIK_SECURITY_DEPENDENCY_SCAN_TOOL BRIK_SECURITY_SECRET_SCAN \
            BRIK_SECURITY_SECRET_SCAN_TOOL BRIK_SECURITY_CONTAINER_SCAN \
            BRIK_SECURITY_CONTAINER_SCAN_TOOL BRIK_SECURITY_SEVERITY_THRESHOLD \
            BRIK_CONFIG_FILE
    }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_SECURITY_DEPENDENCY_SCAN_TOOL"
      export_and_check() {
        config.export_security_vars
        printf '%s' "${BRIK_SECURITY_DEPENDENCY_SCAN_TOOL:-UNSET}"
      }
      When call export_and_check
      The output should equal "npm-audit"
    End

    It "exports BRIK_SECURITY_SECRET_SCAN_TOOL"
      export_and_check() {
        config.export_security_vars
        printf '%s' "${BRIK_SECURITY_SECRET_SCAN_TOOL:-UNSET}"
      }
      When call export_and_check
      The output should equal "gitleaks"
    End

    It "exports BRIK_SECURITY_CONTAINER_SCAN_TOOL"
      export_and_check() {
        config.export_security_vars
        printf '%s' "${BRIK_SECURITY_CONTAINER_SCAN_TOOL:-UNSET}"
      }
      When call export_and_check
      The output should equal "trivy"
    End
  End

  Describe "when security tool fields are not set"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
security:
  enabled: true
  dependency_scan: true
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() {
      rm -f "$TEMP_CONFIG"
      unset BRIK_SECURITY_ENABLED BRIK_SECURITY_DEPENDENCY_SCAN \
            BRIK_SECURITY_DEPENDENCY_SCAN_TOOL BRIK_SECURITY_SECRET_SCAN_TOOL \
            BRIK_SECURITY_CONTAINER_SCAN_TOOL BRIK_CONFIG_FILE
    }
    Before 'setup_config'
    After 'cleanup_config'

    It "does not export tool vars when not configured"
      export_and_check() {
        unset BRIK_SECURITY_DEPENDENCY_SCAN_TOOL BRIK_SECURITY_SECRET_SCAN_TOOL \
              BRIK_SECURITY_CONTAINER_SCAN_TOOL 2>/dev/null || true
        config.export_security_vars
        printf '%s|%s|%s' \
          "${BRIK_SECURITY_DEPENDENCY_SCAN_TOOL:-UNSET}" \
          "${BRIK_SECURITY_SECRET_SCAN_TOOL:-UNSET}" \
          "${BRIK_SECURITY_CONTAINER_SCAN_TOOL:-UNSET}"
      }
      When call export_and_check
      The output should equal "UNSET|UNSET|UNSET"
    End
  End
End

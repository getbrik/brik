Describe "config.sh - export core vars"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"

  # =========================================================================
  # config.export_build_vars
  # =========================================================================
  Describe "config.export_build_vars"
    Describe "with explicit build.command in config"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
build:
  command: npm run custom-build
  node_version: "20"
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_BUILD_STACK as node"
        export_and_check() {
          config.export_build_vars
          printf '%s' "$BRIK_BUILD_STACK"
        }
        When call export_and_check
        The output should equal "node"
      End

      It "exports explicit BRIK_BUILD_COMMAND"
        export_and_check() {
          config.export_build_vars
          printf '%s' "$BRIK_BUILD_COMMAND"
        }
        When call export_and_check
        The output should equal "npm run custom-build"
      End

      It "exports BRIK_BUILD_NODE_VERSION"
        export_and_check() {
          config.export_build_vars
          printf '%s' "${BRIK_BUILD_NODE_VERSION:-}"
        }
        When call export_and_check
        The output should equal "20"
      End
    End

    Describe "fallback to stack default when build.command is absent"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "falls back to empty build command for node stack"
        export_and_check() {
          config.export_build_vars
          printf '%s' "${BRIK_BUILD_COMMAND:-}"
        }
        When call export_and_check
        The output should equal ""
      End
    End

    Describe "with stack auto (no defaults applied)"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: auto
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports empty BRIK_BUILD_COMMAND when no default available"
        export_and_check() {
          config.export_build_vars
          printf '%s' "${BRIK_BUILD_COMMAND}"
        }
        When call export_and_check
        The output should equal ""
      End
    End
  End

  # =========================================================================
  # config.export_test_vars
  # =========================================================================
  Describe "config.export_test_vars"
    Describe "with explicit values"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
test:
  framework: jest
  commands:
    unit: npm test -- --unit
    integration: npm test -- --integration
    e2e: npm run e2e
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_TEST_FRAMEWORK"
        export_and_check() {
          config.export_test_vars
          printf '%s' "$BRIK_TEST_FRAMEWORK"
        }
        When call export_and_check
        The output should equal "jest"
      End

      It "exports BRIK_TEST_COMMAND_UNIT"
        export_and_check() {
          config.export_test_vars
          printf '%s' "${BRIK_TEST_COMMAND_UNIT:-}"
        }
        When call export_and_check
        The output should equal "npm test -- --unit"
      End

      It "exports BRIK_TEST_COMMAND_INTEGRATION"
        export_and_check() {
          config.export_test_vars
          printf '%s' "${BRIK_TEST_COMMAND_INTEGRATION:-}"
        }
        When call export_and_check
        The output should equal "npm test -- --integration"
      End

      It "exports BRIK_TEST_COMMAND_E2E"
        export_and_check() {
          config.export_test_vars
          printf '%s' "${BRIK_TEST_COMMAND_E2E:-}"
        }
        When call export_and_check
        The output should equal "npm run e2e"
      End
    End

    Describe "fallback to stack default when test.framework is absent"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: python
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "falls back to pytest for python stack"
        export_and_check() {
          config.export_test_vars
          printf '%s' "$BRIK_TEST_FRAMEWORK"
        }
        When call export_and_check
        The output should equal "pytest"
      End
    End
  End

  # =========================================================================
  # config.export_quality_vars
  # =========================================================================
  Describe "config.export_quality_vars"
    Describe "with explicit quality config"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
quality:
  lint:
    enabled: true
    tool: eslint
  format:
    tool: prettier
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_LINT_ENABLED as true"
        export_and_check() {
          config.export_quality_vars
          printf '%s' "$BRIK_LINT_ENABLED"
        }
        When call export_and_check
        The output should equal "true"
      End

      It "exports BRIK_QUALITY_LINT_TOOL"
        export_and_check() {
          config.export_quality_vars
          printf '%s' "$BRIK_QUALITY_LINT_TOOL"
        }
        When call export_and_check
        The output should equal "eslint"
      End

      It "exports BRIK_QUALITY_FORMAT_TOOL"
        export_and_check() {
          config.export_quality_vars
          printf '%s' "$BRIK_QUALITY_FORMAT_TOOL"
        }
        When call export_and_check
        The output should equal "prettier"
      End
    End

    Describe "fallback to stack defaults when quality tools absent"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "falls back to eslint for node lint_tool"
        export_and_check() {
          config.export_quality_vars
          printf '%s' "$BRIK_QUALITY_LINT_TOOL"
        }
        When call export_and_check
        The output should equal "eslint"
      End

      It "falls back to prettier for node format_tool"
        export_and_check() {
          config.export_quality_vars
          printf '%s' "$BRIK_QUALITY_FORMAT_TOOL"
        }
        When call export_and_check
        The output should equal "prettier"
      End

      It "defaults format_check to false"
        export_and_check() {
          config.export_quality_vars
          printf '%s' "$BRIK_QUALITY_FORMAT_CHECK"
        }
        When call export_and_check
        The output should equal "false"
      End
    End
  End

  # =========================================================================
  # config.export_security_vars
  # =========================================================================
  Describe "config.export_security_vars"
    Describe "with explicit security config"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
security:
  sast:
    tool: semgrep
    ruleset: auto
    command: semgrep scan
  deps:
    tool: npm-audit
    severity: high
    command: npm audit
  secrets:
    tool: gitleaks
    command: gitleaks detect
  license:
    allowed: MIT,Apache-2.0
    denied: GPL-3.0
  container:
    image: myapp:latest
    severity: critical
  iac:
    tool: checkov
    command: checkov -d .
  severity_threshold: medium
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_SECURITY_SAST_TOOL"
        export_and_check() { config.export_security_vars; printf '%s' "${BRIK_SECURITY_SAST_TOOL:-}"; }
        When call export_and_check
        The output should equal "semgrep"
      End

      It "exports BRIK_SECURITY_SAST_RULESET"
        export_and_check() { config.export_security_vars; printf '%s' "${BRIK_SECURITY_SAST_RULESET:-}"; }
        When call export_and_check
        The output should equal "auto"
      End

      It "exports BRIK_SECURITY_SAST_COMMAND"
        export_and_check() { config.export_security_vars; printf '%s' "${BRIK_SECURITY_SAST_COMMAND:-}"; }
        When call export_and_check
        The output should equal "semgrep scan"
      End

      It "exports BRIK_SECURITY_DEPS_TOOL"
        export_and_check() { config.export_security_vars; printf '%s' "${BRIK_SECURITY_DEPS_TOOL:-}"; }
        When call export_and_check
        The output should equal "npm-audit"
      End

      It "exports BRIK_SECURITY_DEPS_SEVERITY"
        export_and_check() { config.export_security_vars; printf '%s' "${BRIK_SECURITY_DEPS_SEVERITY:-}"; }
        When call export_and_check
        The output should equal "high"
      End

      It "exports BRIK_SECURITY_DEPS_COMMAND"
        export_and_check() { config.export_security_vars; printf '%s' "${BRIK_SECURITY_DEPS_COMMAND:-}"; }
        When call export_and_check
        The output should equal "npm audit"
      End

      It "exports BRIK_SECURITY_SECRETS_TOOL"
        export_and_check() { config.export_security_vars; printf '%s' "${BRIK_SECURITY_SECRETS_TOOL:-}"; }
        When call export_and_check
        The output should equal "gitleaks"
      End

      It "exports BRIK_SECURITY_SECRETS_COMMAND"
        export_and_check() { config.export_security_vars; printf '%s' "${BRIK_SECURITY_SECRETS_COMMAND:-}"; }
        When call export_and_check
        The output should equal "gitleaks detect"
      End

      It "exports BRIK_SECURITY_LICENSE_ALLOWED"
        export_and_check() { config.export_security_vars; printf '%s' "${BRIK_SECURITY_LICENSE_ALLOWED:-}"; }
        When call export_and_check
        The output should equal "MIT,Apache-2.0"
      End

      It "exports BRIK_SECURITY_LICENSE_DENIED"
        export_and_check() { config.export_security_vars; printf '%s' "${BRIK_SECURITY_LICENSE_DENIED:-}"; }
        When call export_and_check
        The output should equal "GPL-3.0"
      End

      It "exports BRIK_SECURITY_CONTAINER_IMAGE"
        export_and_check() { config.export_security_vars; printf '%s' "${BRIK_SECURITY_CONTAINER_IMAGE:-}"; }
        When call export_and_check
        The output should equal "myapp:latest"
      End

      It "exports BRIK_SECURITY_CONTAINER_SEVERITY"
        export_and_check() { config.export_security_vars; printf '%s' "${BRIK_SECURITY_CONTAINER_SEVERITY:-}"; }
        When call export_and_check
        The output should equal "critical"
      End

      It "exports BRIK_SECURITY_IAC_TOOL"
        export_and_check() { config.export_security_vars; printf '%s' "${BRIK_SECURITY_IAC_TOOL:-}"; }
        When call export_and_check
        The output should equal "checkov"
      End

      It "exports BRIK_SECURITY_IAC_COMMAND"
        export_and_check() { config.export_security_vars; printf '%s' "${BRIK_SECURITY_IAC_COMMAND:-}"; }
        When call export_and_check
        The output should equal "checkov -d ."
      End

      It "exports BRIK_SECURITY_SEVERITY_THRESHOLD"
        export_and_check() { config.export_security_vars; printf '%s' "${BRIK_SECURITY_SEVERITY_THRESHOLD:-}"; }
        When call export_and_check
        The output should equal "medium"
      End
    End

    Describe "defaults when security section absent"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "defaults BRIK_SECURITY_SEVERITY_THRESHOLD to high"
        export_and_check() {
          config.export_security_vars
          printf '%s' "$BRIK_SECURITY_SEVERITY_THRESHOLD"
        }
        When call export_and_check
        The output should equal "high"
      End
    End
  End
End

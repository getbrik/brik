Describe "config.sh (portable config reader)"
  Include "$BRIK_HOME/runtime/bash/lib/core/config.sh"

  # =========================================================================
  # config.read
  # =========================================================================
  Describe "config.read"
    It "returns 7 when config file does not exist"
      When call config.read "/nonexistent/brik.yml"
      The status should equal 7
      The error should include "not found"
    End

    Describe "when yq is not on PATH"
      setup_no_yq() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\n' > "$TEMP_CONFIG"
        ORIG_PATH="$PATH"
      }
      cleanup_no_yq() { export PATH="$ORIG_PATH"; rm -f "$TEMP_CONFIG"; }
      Before 'setup_no_yq'
      After 'cleanup_no_yq'

      It "returns 3 when yq is not on PATH"
        read_without_yq() {
          local saved_path="$PATH"
          PATH="/nonexistent_dir_only"
          config.read "$TEMP_CONFIG"
          local rc=$?
          PATH="$saved_path"
          return "$rc"
        }
        When call read_without_yq
        The status should equal 3
        The error should include "yq is required"
      End
    End

    Describe "when YAML is invalid"
      setup_bad_yaml() {
        TEMP_CONFIG="$(mktemp)"
        printf 'key: [unclosed\n  bad: "yaml\n' > "$TEMP_CONFIG"
      }
      cleanup_bad_yaml() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_bad_yaml'
      After 'cleanup_bad_yaml'

      It "returns 2 when YAML is invalid"
        When call config.read "$TEMP_CONFIG"
        The status should equal 2
        The error should include "failed to parse"
      End
    End

    Describe "with valid YAML file"
      setup_valid_config() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_valid_config'
      After 'cleanup_config'

      It "succeeds and sets BRIK_CONFIG_FILE"
        read_and_check() {
          config.read "$TEMP_CONFIG"
          printf '%s' "$BRIK_CONFIG_FILE"
        }
        When call read_and_check
        The status should be success
        The output should equal "$TEMP_CONFIG"
      End

      It "allows subsequent config.get calls without explicit path"
        read_then_get() {
          config.read "$TEMP_CONFIG"
          config.get '.project.name'
        }
        When call read_then_get
        The output should equal "test"
      End
    End
  End

  # =========================================================================
  # config.get
  # =========================================================================
  Describe "config.get"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: my-app
  stack: node
build:
  command: npm run build
quality:
  enabled: true
  coverage:
    threshold: 90
  lint:
    tool: eslint
  format:
    tool: prettier
security:
  enabled: false
  severity_threshold: medium
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "reads a string value"
      When call config.get '.project.name'
      The output should equal "my-app"
    End

    It "reads a nested value with spaces"
      When call config.get '.build.command'
      The output should equal "npm run build"
    End

    It "reads a numeric value as string"
      When call config.get '.quality.coverage.threshold'
      The output should equal "90"
    End

    It "returns default when key is missing"
      When call config.get '.nonexistent.key' 'default_value'
      The output should equal "default_value"
    End

    It "returns 1 when key is missing and no default"
      When call config.get '.nonexistent.key'
      The status should equal 1
    End

    It "returns 7 when config file does not exist and no default"
      get_from_missing() {
        BRIK_CONFIG_FILE="/nonexistent/file.yml"
        config.get '.project.name'
      }
      When call get_from_missing
      The status should equal 7
    End

    It "returns default when config file does not exist but default given"
      get_from_missing_with_default() {
        BRIK_CONFIG_FILE="/nonexistent/file.yml"
        config.get '.project.name' 'fallback'
      }
      When call get_from_missing_with_default
      The output should equal "fallback"
    End
  End

  # =========================================================================
  # config.stage_enabled
  # =========================================================================
  Describe "config.stage_enabled"
    Describe "always-enabled stages"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "returns 0 for init"
        When call config.stage_enabled "init"
        The status should be success
      End

      It "returns 0 for build"
        When call config.stage_enabled "build"
        The status should be success
      End

      It "returns 0 for test"
        When call config.stage_enabled "test"
        The status should be success
      End

      It "returns 0 for notify"
        When call config.stage_enabled "notify"
        The status should be success
      End
    End

    Describe "quality stage"
      Describe "when quality.enabled is true"
        setup_quality_on() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\nquality:\n  enabled: true\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_quality_on'
        After 'cleanup'

        It "is enabled when quality.enabled is true"
          When call config.stage_enabled "quality"
          The status should be success
        End
      End

      Describe "when quality section is absent"
        setup_no_quality() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\nproject:\n  name: test\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_no_quality'
        After 'cleanup'

        It "is enabled by default when quality section is absent"
          When call config.stage_enabled "quality"
          The status should be success
        End
      End

      Describe "when quality.enabled is false"
        setup_quality_off() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\nquality:\n  enabled: false\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_quality_off'
        After 'cleanup'

        It "is disabled when quality.enabled is false"
          When call config.stage_enabled "quality"
          The status should equal 1
        End
      End
    End

    Describe "security stage"
      Describe "when security.enabled is false"
        setup_sec_off() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\nsecurity:\n  enabled: false\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_sec_off'
        After 'cleanup'

        It "is disabled when security.enabled is false"
          When call config.stage_enabled "security"
          The status should equal 1
        End
      End

      Describe "when security section is absent"
        setup_no_sec() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\nproject:\n  name: test\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_no_sec'
        After 'cleanup'

        It "is disabled by default when security section is absent"
          When call config.stage_enabled "security"
          The status should equal 1
        End
      End
    End

    Describe "release stage"
      Describe "when release.strategy is set"
        setup_release() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\nrelease:\n  strategy: semver\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_release'
        After 'cleanup'

        It "is enabled when release.strategy is set"
          When call config.stage_enabled "release"
          The status should be success
        End
      End

      Describe "when release section is absent"
        setup_no_release() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\nproject:\n  name: test\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_no_release'
        After 'cleanup'

        It "is disabled when release section is absent"
          When call config.stage_enabled "release"
          The status should equal 1
        End
      End
    End

    Describe "package stage"
      Describe "when package.docker.image is set"
        setup_package() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\npackage:\n  docker:\n    image: my-registry/my-app\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_package'
        After 'cleanup'

        It "is enabled when package.docker.image is set"
          When call config.stage_enabled "package"
          The status should be success
        End
      End

      Describe "when package section is absent"
        setup_no_package() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\nproject:\n  name: test\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_no_package'
        After 'cleanup'

        It "is disabled when package section is absent"
          When call config.stage_enabled "package"
          The status should equal 1
        End
      End
    End

    Describe "deploy stage"
      Describe "when deploy.environments has entries"
        setup_deploy() {
          TEMP_CONFIG="$(mktemp)"
          cat > "$TEMP_CONFIG" <<'YAML'
version: 1
deploy:
  environments:
    staging:
      when: "branch == 'main'"
YAML
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_deploy'
        After 'cleanup'

        It "is enabled when deploy.environments has entries"
          When call config.stage_enabled "deploy"
          The status should be success
        End
      End

      Describe "when deploy section is absent"
        setup_no_deploy() {
          TEMP_CONFIG="$(mktemp)"
          printf 'version: 1\nproject:\n  name: test\n' > "$TEMP_CONFIG"
          export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        }
        cleanup() { rm -f "$TEMP_CONFIG"; }
        Before 'setup_no_deploy'
        After 'cleanup'

        It "is disabled when deploy section is absent"
          When call config.stage_enabled "deploy"
          The status should equal 1
        End
      End
    End

    Describe "unknown stages"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup'

      It "returns 1 for unknown stages"
        When call config.stage_enabled "foobar"
        The status should equal 1
      End
    End
  End

  # =========================================================================
  # config.stack_default
  # =========================================================================
  Describe "config.stack_default"
    It "returns node build_command"
      When call config.stack_default "node" "build_command"
      The output should equal "npm run build"
    End

    It "returns node format_tool"
      When call config.stack_default "node" "format_tool"
      The output should equal "prettier"
    End

    It "returns java build_command"
      When call config.stack_default "java" "build_command"
      The output should equal "mvn package -DskipTests"
    End

    It "returns java format_tool"
      When call config.stack_default "java" "format_tool"
      The output should equal "google-java-format"
    End

    It "returns python test_framework"
      When call config.stack_default "python" "test_framework"
      The output should equal "pytest"
    End

    It "returns python format_tool"
      When call config.stack_default "python" "format_tool"
      The output should equal "ruff format"
    End

    It "returns dotnet build_command"
      When call config.stack_default "dotnet" "build_command"
      The output should equal "dotnet build"
    End

    It "returns dotnet format_tool"
      When call config.stack_default "dotnet" "format_tool"
      The output should equal "dotnet-format"
    End

    It "returns rust lint_tool"
      When call config.stack_default "rust" "lint_tool"
      The output should equal "clippy"
    End

    It "returns rust format_tool"
      When call config.stack_default "rust" "format_tool"
      The output should equal "rustfmt"
    End

    It "returns 1 for unknown stack"
      When call config.stack_default "unknown" "build_command"
      The status should equal 1
    End

    It "returns 1 for unknown setting on valid stack"
      When call config.stack_default "node" "nonexistent_setting"
      The status should equal 1
    End
  End

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

      It "falls back to npm run build for node stack"
        export_and_check() {
          config.export_build_vars
          printf '%s' "$BRIK_BUILD_COMMAND"
        }
        When call export_and_check
        The output should equal "npm run build"
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
  enabled: true
  lint:
    tool: eslint
  format:
    tool: prettier
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_QUALITY_ENABLED as true"
        export_and_check() {
          config.export_quality_vars
          printf '%s' "$BRIK_QUALITY_ENABLED"
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
  enabled: true
  severity_threshold: medium
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_SECURITY_ENABLED as true"
        export_and_check() {
          config.export_security_vars
          printf '%s' "$BRIK_SECURITY_ENABLED"
        }
        When call export_and_check
        The output should equal "true"
      End

      It "exports BRIK_SECURITY_SEVERITY_THRESHOLD"
        export_and_check() {
          config.export_security_vars
          printf '%s' "$BRIK_SECURITY_SEVERITY_THRESHOLD"
        }
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

      It "defaults BRIK_SECURITY_ENABLED to false"
        export_and_check() {
          config.export_security_vars
          printf '%s' "$BRIK_SECURITY_ENABLED"
        }
        When call export_and_check
        The output should equal "false"
      End

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

  # =========================================================================
  # config.export_build_vars - dotnet/rust versions
  # =========================================================================
  Describe "config.export_build_vars dotnet version"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: dotnet
build:
  dotnet_version: "8.0"
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_BUILD_DOTNET_VERSION"
      export_and_check() {
        config.export_build_vars
        printf '%s' "${BRIK_BUILD_DOTNET_VERSION:-}"
      }
      When call export_and_check
      The output should equal "8.0"
    End
  End

  Describe "config.export_build_vars rust version"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: rust
build:
  rust_version: "1.75"
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_BUILD_RUST_VERSION"
      export_and_check() {
        config.export_build_vars
        printf '%s' "${BRIK_BUILD_RUST_VERSION:-}"
      }
      When call export_and_check
      The output should equal "1.75"
    End
  End

  # =========================================================================
  # config.export_quality_vars - extended fields
  # =========================================================================
  Describe "config.export_quality_vars extended fields"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: node
quality:
  enabled: true
  lint:
    tool: eslint
    config: .eslintrc.json
    fix: "true"
  sast:
    tool: semgrep
    ruleset: p/security-audit
  deps:
    tool: npm-audit
    severity: high
  coverage:
    threshold: 85
    report: lcov
  license:
    allowed: MIT,Apache-2.0
    denied: GPL-3.0
  format:
    tool: prettier
    check: true
  container:
    image: myapp:latest
    severity: critical
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_QUALITY_FORMAT_CHECK"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_FORMAT_CHECK:-}"; }
      When call export_and_check
      The output should equal "true"
    End

    It "exports BRIK_QUALITY_LINT_CONFIG"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_LINT_CONFIG:-}"; }
      When call export_and_check
      The output should equal ".eslintrc.json"
    End

    It "exports BRIK_QUALITY_LINT_FIX"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_LINT_FIX:-}"; }
      When call export_and_check
      The output should equal "true"
    End

    It "exports BRIK_QUALITY_SAST_TOOL"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_SAST_TOOL:-}"; }
      When call export_and_check
      The output should equal "semgrep"
    End

    It "exports BRIK_QUALITY_SAST_RULESET"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_SAST_RULESET:-}"; }
      When call export_and_check
      The output should equal "p/security-audit"
    End

    It "exports BRIK_QUALITY_DEPS_TOOL"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_DEPS_TOOL:-}"; }
      When call export_and_check
      The output should equal "npm-audit"
    End

    It "exports BRIK_QUALITY_DEPS_SEVERITY"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_DEPS_SEVERITY:-}"; }
      When call export_and_check
      The output should equal "high"
    End

    It "exports BRIK_QUALITY_COVERAGE_THRESHOLD"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_COVERAGE_THRESHOLD:-}"; }
      When call export_and_check
      The output should equal "85"
    End

    It "exports BRIK_QUALITY_COVERAGE_REPORT"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_COVERAGE_REPORT:-}"; }
      When call export_and_check
      The output should equal "lcov"
    End

    It "exports BRIK_QUALITY_LICENSE_ALLOWED"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_LICENSE_ALLOWED:-}"; }
      When call export_and_check
      The output should equal "MIT,Apache-2.0"
    End

    It "exports BRIK_QUALITY_LICENSE_DENIED"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_LICENSE_DENIED:-}"; }
      When call export_and_check
      The output should equal "GPL-3.0"
    End

    It "exports BRIK_QUALITY_CONTAINER_IMAGE"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_CONTAINER_IMAGE:-}"; }
      When call export_and_check
      The output should equal "myapp:latest"
    End

    It "exports BRIK_QUALITY_CONTAINER_SEVERITY"
      export_and_check() { config.export_quality_vars; printf '%s' "${BRIK_QUALITY_CONTAINER_SEVERITY:-}"; }
      When call export_and_check
      The output should equal "critical"
    End
  End

  # =========================================================================
  # config.export_security_vars - scan flags
  # =========================================================================
  Describe "config.export_security_vars scan flags"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
security:
  enabled: true
  dependency_scan: "true"
  secret_scan: "true"
  container_scan: "false"
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_SECURITY_DEPENDENCY_SCAN"
      export_and_check() { config.export_security_vars; printf '%s' "${BRIK_SECURITY_DEPENDENCY_SCAN:-}"; }
      When call export_and_check
      The output should equal "true"
    End

    It "exports BRIK_SECURITY_SECRET_SCAN"
      export_and_check() { config.export_security_vars; printf '%s' "${BRIK_SECURITY_SECRET_SCAN:-}"; }
      When call export_and_check
      The output should equal "true"
    End

    It "exports BRIK_SECURITY_CONTAINER_SCAN"
      export_and_check() { config.export_security_vars; printf '%s' "${BRIK_SECURITY_CONTAINER_SCAN:-}"; }
      When call export_and_check
      The output should equal "false"
    End
  End

  # =========================================================================
  # config.export_package_vars
  # =========================================================================
  Describe "config.export_package_vars"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
package:
  docker:
    image: registry.example.com/myapp
    dockerfile: Dockerfile.prod
    context: .
    platforms: linux/amd64,linux/arm64
    build_args: NODE_ENV=production
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_PACKAGE_DOCKER_IMAGE"
      export_and_check() { config.export_package_vars; printf '%s' "${BRIK_PACKAGE_DOCKER_IMAGE:-}"; }
      When call export_and_check
      The output should equal "registry.example.com/myapp"
    End

    It "exports BRIK_PACKAGE_DOCKER_DOCKERFILE"
      export_and_check() { config.export_package_vars; printf '%s' "${BRIK_PACKAGE_DOCKER_DOCKERFILE:-}"; }
      When call export_and_check
      The output should equal "Dockerfile.prod"
    End

    It "exports BRIK_PACKAGE_DOCKER_CONTEXT"
      export_and_check() { config.export_package_vars; printf '%s' "${BRIK_PACKAGE_DOCKER_CONTEXT:-}"; }
      When call export_and_check
      The output should equal "."
    End

    It "exports BRIK_PACKAGE_DOCKER_PLATFORMS"
      export_and_check() { config.export_package_vars; printf '%s' "${BRIK_PACKAGE_DOCKER_PLATFORMS:-}"; }
      When call export_and_check
      The output should equal "linux/amd64,linux/arm64"
    End

    It "exports BRIK_PACKAGE_DOCKER_BUILD_ARGS"
      export_and_check() { config.export_package_vars; printf '%s' "${BRIK_PACKAGE_DOCKER_BUILD_ARGS:-}"; }
      When call export_and_check
      The output should equal "NODE_ENV=production"
    End

    Describe "when package section absent"
      setup_empty() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_empty() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_empty'
      After 'cleanup_empty'

      It "succeeds with no exports"
        export_and_check() {
          unset BRIK_PACKAGE_DOCKER_IMAGE 2>/dev/null || true
          config.export_package_vars
          printf '%s' "${BRIK_PACKAGE_DOCKER_IMAGE:-empty}"
        }
        When call export_and_check
        The output should equal "empty"
      End
    End
  End

  # =========================================================================
  # config.export_deploy_vars
  # =========================================================================
  Describe "config.export_deploy_vars"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
deploy:
  environments:
    staging:
      target: kubernetes
      namespace: staging-ns
      when: "branch == 'main'"
    production:
      target: kubernetes
      namespace: prod-ns
      manifest: k8s/production.yml
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_DEPLOY_ENVIRONMENTS"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_ENVIRONMENTS:-}"; }
      When call export_and_check
      The output should include "staging"
      The output should include "production"
    End

    It "exports BRIK_DEPLOY_STAGING_TARGET"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_STAGING_TARGET:-}"; }
      When call export_and_check
      The output should equal "kubernetes"
    End

    It "exports BRIK_DEPLOY_STAGING_NAMESPACE"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_STAGING_NAMESPACE:-}"; }
      When call export_and_check
      The output should equal "staging-ns"
    End

    It "exports BRIK_DEPLOY_PRODUCTION_MANIFEST"
      export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_PRODUCTION_MANIFEST:-}"; }
      When call export_and_check
      The output should equal "k8s/production.yml"
    End

    Describe "when deploy section absent"
      setup_empty() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_empty() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_empty'
      After 'cleanup_empty'

      It "exports empty BRIK_DEPLOY_ENVIRONMENTS"
        export_and_check() { config.export_deploy_vars; printf '%s' "${BRIK_DEPLOY_ENVIRONMENTS}"; }
        When call export_and_check
        The output should equal ""
      End
    End
  End

  # =========================================================================
  # config.export_notify_vars
  # =========================================================================
  Describe "config.export_notify_vars"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
notify:
  slack:
    channel: "#builds"
    on: failure
  email:
    to: team@example.com
    on: always
  webhook:
    url: https://hooks.example.com/notify
    on: success
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_NOTIFY_SLACK_CHANNEL"
      export_and_check() { config.export_notify_vars; printf '%s' "${BRIK_NOTIFY_SLACK_CHANNEL:-}"; }
      When call export_and_check
      The output should equal "#builds"
    End

    It "exports BRIK_NOTIFY_SLACK_ON"
      export_and_check() { config.export_notify_vars; printf '%s' "${BRIK_NOTIFY_SLACK_ON:-}"; }
      When call export_and_check
      The output should equal "failure"
    End

    It "exports BRIK_NOTIFY_EMAIL_TO"
      export_and_check() { config.export_notify_vars; printf '%s' "${BRIK_NOTIFY_EMAIL_TO:-}"; }
      When call export_and_check
      The output should equal "team@example.com"
    End

    It "exports BRIK_NOTIFY_WEBHOOK_URL"
      export_and_check() { config.export_notify_vars; printf '%s' "${BRIK_NOTIFY_WEBHOOK_URL:-}"; }
      When call export_and_check
      The output should equal "https://hooks.example.com/notify"
    End
  End

  # =========================================================================
  # config.export_hooks_vars
  # =========================================================================
  Describe "config.export_hooks_vars"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
hooks:
  pre_build: echo pre-build
  post_build: echo post-build
  pre_test: echo pre-test
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_HOOK_PRE_BUILD"
      export_and_check() { config.export_hooks_vars; printf '%s' "${BRIK_HOOK_PRE_BUILD:-}"; }
      When call export_and_check
      The output should equal "echo pre-build"
    End

    It "exports BRIK_HOOK_POST_BUILD"
      export_and_check() { config.export_hooks_vars; printf '%s' "${BRIK_HOOK_POST_BUILD:-}"; }
      When call export_and_check
      The output should equal "echo post-build"
    End

    It "exports BRIK_HOOK_PRE_TEST"
      export_and_check() { config.export_hooks_vars; printf '%s' "${BRIK_HOOK_PRE_TEST:-}"; }
      When call export_and_check
      The output should equal "echo pre-test"
    End
  End

  # =========================================================================
  # config.export_release_vars
  # =========================================================================
  Describe "config.export_release_vars"
    Describe "with explicit values"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
release:
  strategy: calver
  tag_prefix: release-
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_RELEASE_STRATEGY"
        export_and_check() { config.export_release_vars; printf '%s' "${BRIK_RELEASE_STRATEGY:-}"; }
        When call export_and_check
        The output should equal "calver"
      End

      It "exports BRIK_RELEASE_TAG_PREFIX"
        export_and_check() { config.export_release_vars; printf '%s' "${BRIK_RELEASE_TAG_PREFIX:-}"; }
        When call export_and_check
        The output should equal "release-"
      End
    End

    Describe "defaults when release section absent"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_config'
      After 'cleanup_config'

      It "defaults BRIK_RELEASE_STRATEGY to semver"
        export_and_check() { config.export_release_vars; printf '%s' "${BRIK_RELEASE_STRATEGY:-}"; }
        When call export_and_check
        The output should equal "semver"
      End

      It "defaults BRIK_RELEASE_TAG_PREFIX to v"
        export_and_check() { config.export_release_vars; printf '%s' "${BRIK_RELEASE_TAG_PREFIX:-}"; }
        When call export_and_check
        The output should equal "v"
      End
    End
  End

  # =========================================================================
  # config.export_all
  # =========================================================================
  Describe "config.export_all"
    setup_config() {
      TEMP_CONFIG="$(mktemp)"
      cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: full-app
  stack: node
  root: services/api
build:
  command: npm run build
test:
  framework: jest
quality:
  enabled: true
security:
  enabled: false
YAML
      export BRIK_CONFIG_FILE="$TEMP_CONFIG"
    }
    cleanup_config() { rm -f "$TEMP_CONFIG"; }
    Before 'setup_config'
    After 'cleanup_config'

    It "exports BRIK_PROJECT_NAME"
      export_and_check() {
        config.export_all "$TEMP_CONFIG"
        printf '%s' "$BRIK_PROJECT_NAME"
      }
      When call export_and_check
      The output should equal "full-app"
    End

    It "exports BRIK_PROJECT_ROOT"
      export_and_check() {
        config.export_all "$TEMP_CONFIG"
        printf '%s' "$BRIK_PROJECT_ROOT"
      }
      When call export_and_check
      The output should equal "services/api"
    End

    It "exports build vars"
      export_and_check() {
        config.export_all "$TEMP_CONFIG"
        printf '%s' "$BRIK_BUILD_COMMAND"
      }
      When call export_and_check
      The output should equal "npm run build"
    End

    It "exports test vars"
      export_and_check() {
        config.export_all "$TEMP_CONFIG"
        printf '%s' "$BRIK_TEST_FRAMEWORK"
      }
      When call export_and_check
      The output should equal "jest"
    End

    It "exports quality vars"
      export_and_check() {
        config.export_all "$TEMP_CONFIG"
        printf '%s' "$BRIK_QUALITY_ENABLED"
      }
      When call export_and_check
      The output should equal "true"
    End

    It "exports security vars"
      export_and_check() {
        config.export_all "$TEMP_CONFIG"
        printf '%s' "$BRIK_SECURITY_ENABLED"
      }
      When call export_and_check
      The output should equal "false"
    End

    It "returns 7 when config file does not exist"
      When call config.export_all "/nonexistent/brik.yml"
      The status should equal 7
      The error should be present
    End
  End

  # =========================================================================
  # brik.use config integration
  # =========================================================================
  Describe "brik.use config"
    Include "$BRIK_HOME/runtime/bash/lib/core/_loader.sh"

    It "loads config module via brik.use"
      load_via_brik_use() {
        # Reset guards to allow re-load (loader guard + module guard)
        unset _BRIK_MODULE_CONFIG_LOADED _BRIK_CORE_CONFIG_LOADED 2>/dev/null || true
        brik.use config
        declare -f config.read >/dev/null 2>&1 && echo "available" || echo "missing"
      }
      When call load_via_brik_use
      The output should equal "available"
    End
  End

  # =========================================================================
  # config.validate_coherence
  # =========================================================================
  Describe "config.validate_coherence"

    Describe "node + jest in devDependencies"
      setup_coherent_jest() {
        COHERENT_WS="$(mktemp -d)"
        printf '{"name":"test","devDependencies":{"jest":"^29.0.0"}}\n' > "${COHERENT_WS}/package.json"
        COHERENT_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\ntest:\n  framework: jest\n' > "$COHERENT_CONFIG"
        export BRIK_BUILD_STACK="node"
        export BRIK_TEST_FRAMEWORK="jest"
        export BRIK_WORKSPACE="$COHERENT_WS"
        export BRIK_CONFIG_FILE="$COHERENT_CONFIG"
      }
      cleanup_coherent_jest() {
        rm -rf "$COHERENT_WS" "$COHERENT_CONFIG"
        unset BRIK_BUILD_STACK BRIK_TEST_FRAMEWORK BRIK_WORKSPACE BRIK_CONFIG_FILE
      }
      Before 'setup_coherent_jest'
      After 'cleanup_coherent_jest'

      It "passes when jest is in devDependencies"
        When call config.validate_coherence
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
        export BRIK_WORKSPACE="$INCOHERENT_WS"
        export BRIK_CONFIG_FILE="$INCOHERENT_CONFIG"
      }
      cleanup_incoherent_jest() {
        rm -rf "$INCOHERENT_WS" "$INCOHERENT_CONFIG"
        unset BRIK_BUILD_STACK BRIK_TEST_FRAMEWORK BRIK_WORKSPACE BRIK_CONFIG_FILE
      }
      Before 'setup_incoherent_jest'
      After 'cleanup_incoherent_jest'

      It "fails with exit 7 and descriptive error"
        When call config.validate_coherence
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
        export BRIK_WORKSPACE="$NPM_WS"
      }
      cleanup_npm_framework() {
        rm -rf "$NPM_WS"
        unset BRIK_BUILD_STACK BRIK_TEST_FRAMEWORK BRIK_WORKSPACE
      }
      Before 'setup_npm_framework'
      After 'cleanup_npm_framework'

      It "passes (no jest coherence check needed)"
        When call config.validate_coherence
        The status should be success
      End
    End

    Describe "non-node stack"
      setup_python_stack() {
        PYTHON_WS="$(mktemp -d)"
        export BRIK_BUILD_STACK="python"
        export BRIK_TEST_FRAMEWORK="pytest"
        export BRIK_WORKSPACE="$PYTHON_WS"
      }
      cleanup_python_stack() {
        rm -rf "$PYTHON_WS"
        unset BRIK_BUILD_STACK BRIK_TEST_FRAMEWORK BRIK_WORKSPACE
      }
      Before 'setup_python_stack'
      After 'cleanup_python_stack'

      It "passes (skip node-specific checks)"
        When call config.validate_coherence
        The status should be success
      End
    End

    Describe "node + jest + no package.json"
      setup_no_pkgjson() {
        NO_PKGJSON_WS="$(mktemp -d)"
        export BRIK_BUILD_STACK="node"
        export BRIK_TEST_FRAMEWORK="jest"
        export BRIK_WORKSPACE="$NO_PKGJSON_WS"
      }
      cleanup_no_pkgjson() {
        rm -rf "$NO_PKGJSON_WS"
        unset BRIK_BUILD_STACK BRIK_TEST_FRAMEWORK BRIK_WORKSPACE
      }
      Before 'setup_no_pkgjson'
      After 'cleanup_no_pkgjson'

      It "passes when package.json is absent"
        When call config.validate_coherence
        The status should be success
      End
    End

    Describe "node + jest + malformed package.json"
      setup_malformed() {
        MALFORMED_WS="$(mktemp -d)"
        printf 'not valid json{{{' > "${MALFORMED_WS}/package.json"
        export BRIK_BUILD_STACK="node"
        export BRIK_TEST_FRAMEWORK="jest"
        export BRIK_WORKSPACE="$MALFORMED_WS"
      }
      cleanup_malformed() {
        rm -rf "$MALFORMED_WS"
        unset BRIK_BUILD_STACK BRIK_TEST_FRAMEWORK BRIK_WORKSPACE
      }
      Before 'setup_malformed'
      After 'cleanup_malformed'

      It "warns and passes on malformed package.json"
        When call config.validate_coherence
        The status should be success
        The error should include "skipping coherence validation"
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
        export BRIK_WORKSPACE="$EXPLICIT_WS"
        export BRIK_CONFIG_FILE="$EXPLICIT_CONFIG"
      }
      cleanup_explicit_jest() {
        rm -rf "$EXPLICIT_WS" "$EXPLICIT_CONFIG"
        unset BRIK_BUILD_STACK BRIK_TEST_FRAMEWORK BRIK_WORKSPACE BRIK_CONFIG_FILE
      }
      Before 'setup_explicit_jest'
      After 'cleanup_explicit_jest'

      It "reports brik.yml as the source"
        When call config.validate_coherence
        The status should equal 7
        The error should include "brik.yml"
      End
    End
  End
End

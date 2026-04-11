Describe "config.sh - read and get"
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
  lint:
    enabled: true
    tool: eslint
  format:
    tool: prettier
test:
  coverage:
    threshold: 90
security:
  sast:
    tool: semgrep
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
      When call config.get '.test.coverage.threshold'
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
End

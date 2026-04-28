Describe "config.sh - validate_schema"
  Include "$BRIK_HOME/lib/transverse/config.sh"

  # Helper: returns 0 when jv is NOT on PATH (used by `Skip if`).
  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  # =========================================================================
  # config.validate_schema
  # =========================================================================
  Describe "config.validate_schema"

    # ---------- Case 1: config file missing ----------
    It "returns 7 when config file does not exist"
      validate_missing() {
        BRIK_CONFIG_FILE="/nonexistent/brik.yml"
        config.validate_schema
      }
      When call validate_missing
      The status should equal 7
      The error should include "not found"
    End

    # ---------- Case 2: jv absent ----------
    Describe "when jv is not on PATH"
      setup_no_jv() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_no_jv() { rm -f "$TEMP_CONFIG"; }
      Before 'setup_no_jv'
      After 'cleanup_no_jv'

      It "skips silently with status 0 when jv is not on PATH"
        validate_without_jv() {
          local saved_path="$PATH"
          PATH="/nonexistent_dir_only"
          config.validate_schema
          local rc=$?
          PATH="$saved_path"
          return "$rc"
        }
        When call validate_without_jv
        The status should be success
      End
    End

    # ---------- Case 3: schema file missing ----------
    Describe "when the schema file is absent"
      setup_no_schema() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        TEMP_HOME="$(mktemp -d)"
        ORIG_BRIK_HOME="$BRIK_HOME"
        export BRIK_HOME="$TEMP_HOME"
      }
      cleanup_no_schema() {
        rm -f "$TEMP_CONFIG"
        rm -rf "$TEMP_HOME"
        export BRIK_HOME="$ORIG_BRIK_HOME"
      }
      Before 'setup_no_schema'
      After 'cleanup_no_schema'

      It "warns and returns 0 when the bundled schema cannot be located"
        When call config.validate_schema
        The status should be success
        The error should include "schema file not found"
      End
    End

    # ---------- Case 4: valid config (requires jv) ----------
    # jv detects the file format by extension, so the brik.yml fixture
    # must end in .yaml/.yml -- a bare mktemp file would be parsed as JSON.
    Describe "with a valid brik.yml and jv on PATH"
      setup_valid() {
        TEMP_DIR="$(mktemp -d)"
        TEMP_CONFIG="$TEMP_DIR/brik.yml"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_valid() { rm -rf "$TEMP_DIR"; }
      Before 'setup_valid'
      After 'cleanup_valid'

      It "returns 0 when the config matches the schema"
        Skip if "jv not installed" jv_missing
        When call config.validate_schema
        The status should be success
        The error should include "validating brik.yml"
      End
    End

    # ---------- Case 5: invalid config (requires jv) ----------
    Describe "with an invalid brik.yml and jv on PATH"
      setup_invalid() {
        TEMP_DIR="$(mktemp -d)"
        TEMP_CONFIG="$TEMP_DIR/brik.yml"
        printf 'version: 99\nproject:\n  name: bogus\n  unknown_top_level: true\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_invalid() { rm -rf "$TEMP_DIR"; }
      Before 'setup_invalid'
      After 'cleanup_invalid'

      It "returns 7 when the config violates the schema"
        Skip if "jv not installed" jv_missing
        When call config.validate_schema
        The status should equal 7
        The error should include "validation failed"
      End
    End
  End
End

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

    # ---------- Validator selection priority ----------
    # When both jv and check-jsonschema are present, jv must win. When only
    # check-jsonschema is present, the function must fall back to it. Stubs
    # write to a marker file so the spec can verify which one ran.
    Describe "validator selection priority"
      setup_stubs() {
        TEMP_DIR="$(mktemp -d)"
        TEMP_CONFIG="$TEMP_DIR/brik.yml"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
        STUB_BIN="$(mktemp -d)"
        MARKER="$TEMP_DIR/marker"
        cat > "$STUB_BIN/jv" <<EOF
#!/usr/bin/env bash
echo jv-ran > "$MARKER"
exit 0
EOF
        cat > "$STUB_BIN/check-jsonschema" <<EOF
#!/usr/bin/env bash
echo check-jsonschema-ran > "$MARKER"
exit 0
EOF
        chmod +x "$STUB_BIN/jv" "$STUB_BIN/check-jsonschema"
        ORIG_PATH="$PATH"
      }
      cleanup_stubs() {
        rm -rf "$TEMP_DIR" "$STUB_BIN"
        export PATH="$ORIG_PATH"
      }
      Before 'setup_stubs'
      After 'cleanup_stubs'

      It "prefers jv when both validators are on PATH"
        prefers_jv() {
          export PATH="${STUB_BIN}:${ORIG_PATH}"
          config.validate_schema
          local rc=$?
          export PATH="$ORIG_PATH"
          cat "$MARKER" 2>/dev/null
          return $rc
        }
        When call prefers_jv
        The status should be success
        The output should equal "jv-ran"
      End

      It "falls back to check-jsonschema when jv is absent"
        falls_back() {
          rm -f "$STUB_BIN/jv"
          export PATH="${STUB_BIN}:/usr/bin:/bin"
          config.validate_schema
          local rc=$?
          export PATH="$ORIG_PATH"
          cat "$MARKER" 2>/dev/null
          return $rc
        }
        When call falls_back
        The status should be success
        The output should equal "check-jsonschema-ran"
      End
    End
  End
End

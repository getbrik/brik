Describe "config/rust.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_CORE_LIB/config.sh"
  Include "$BRIK_CORE_LIB/config/rust.sh"

  Describe "config.rust.default"
    It "returns empty string for build_command"
      When call config.rust.default "build_command"
      The output should equal ""
      The status should be success
    End

    It "returns 'cargo test' for test_framework"
      When call config.rust.default "test_framework"
      The output should equal "cargo test"
    End

    It "returns 'clippy' for lint_tool"
      When call config.rust.default "lint_tool"
      The output should equal "clippy"
    End

    It "returns 'rustfmt' for format_tool"
      When call config.rust.default "format_tool"
      The output should equal "rustfmt"
    End

    It "returns 1 for unknown setting"
      When call config.rust.default "unknown_setting"
      The status should equal 1
    End
  End

  Describe "config.rust.export_build_vars"
    Describe "when rust_version is configured"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        cat > "$TEMP_CONFIG" <<'YAML'
version: 1
project:
  name: test
  stack: rust
build:
  rust_version: "1.77.0"
YAML
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() {
        rm -f "$TEMP_CONFIG"
        unset BRIK_BUILD_RUST_VERSION BRIK_CONFIG_FILE
      }
      Before 'setup_config'
      After 'cleanup_config'

      It "exports BRIK_BUILD_RUST_VERSION"
        export_and_check() {
          config.rust.export_build_vars
          printf '%s' "${BRIK_BUILD_RUST_VERSION:-}"
        }
        When call export_and_check
        The output should equal "1.77.0"
      End
    End

    Describe "when rust_version is not configured"
      setup_config() {
        TEMP_CONFIG="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: rust\n' > "$TEMP_CONFIG"
        export BRIK_CONFIG_FILE="$TEMP_CONFIG"
      }
      cleanup_config() {
        rm -f "$TEMP_CONFIG"
        unset BRIK_CONFIG_FILE
      }
      Before 'setup_config'
      After 'cleanup_config'

      It "does not export BRIK_BUILD_RUST_VERSION"
        export_and_check() {
          unset BRIK_BUILD_RUST_VERSION 2>/dev/null || true
          config.rust.export_build_vars
          printf '%s' "${BRIK_BUILD_RUST_VERSION:-UNSET}"
        }
        When call export_and_check
        The output should equal "UNSET"
      End
    End
  End

  Describe "config.rust.validate_coherence"

    Describe "Cargo.toml present"
      setup_cargo() {
        CARGO_WS="$(mktemp -d)"
        printf '[package]\nname = "test"\n' > "${CARGO_WS}/Cargo.toml"
      }
      cleanup_cargo() { rm -rf "$CARGO_WS"; }
      Before 'setup_cargo'
      After 'cleanup_cargo'

      It "passes when Cargo.toml exists"
        When call config.rust.validate_coherence "$CARGO_WS"
        The status should be success
      End
    End

    Describe "Cargo.toml absent"
      setup_no_cargo() {
        NO_CARGO_WS="$(mktemp -d)"
      }
      cleanup_no_cargo() { rm -rf "$NO_CARGO_WS"; }
      Before 'setup_no_cargo'
      After 'cleanup_no_cargo'

      It "fails with exit 7"
        When call config.rust.validate_coherence "$NO_CARGO_WS"
        The status should equal 7
        The stderr should include "config mismatch"
        The stderr should include "Cargo.toml"
      End
    End
  End
End

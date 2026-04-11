Describe "stages/container_scan.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_RUNTIME_LIB/context.sh"
  Include "$BRIK_CORE_LIB/_loader.sh"
  Include "$BRIK_CORE_LIB/config.sh"
  Include "$BRIK_CORE_LIB/security.sh"
  Include "$BRIK_HOME/runtime/bash/lib/stages/container_scan.sh"
  Include "$BRIK_HOME/runtime/bash/spec/support/mock_helper.sh"

  Describe "stages.container_scan"
    Describe "no image configured"
      setup_no_image() {
        export BRIK_CONFIG_FILE
        BRIK_CONFIG_FILE="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$BRIK_CONFIG_FILE"
        CTX_FILE="$(mktemp)"
        unset BRIK_SECURITY_CONTAINER_IMAGE 2>/dev/null || true
      }
      cleanup_no_image() {
        rm -f "$BRIK_CONFIG_FILE" "$CTX_FILE"
      }
      Before 'setup_no_image'
      After 'cleanup_no_image'

      It "skips when no container image configured"
        invoke_skip() {
          stages.container_scan "$CTX_FILE" 2>/dev/null
          local status=$?
          grep "^BRIK_CONTAINER_SCAN_STATUS=" "$CTX_FILE" | cut -d= -f2
          return $status
        }
        When call invoke_skip
        The status should be success
        The output should equal "skipped"
      End
    End

    Describe "with image configured auto-loads container module"
      setup_autoload() {
        export BRIK_CONFIG_FILE
        BRIK_CONFIG_FILE="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\nsecurity:\n  container:\n    image: myapp:latest\n' > "$BRIK_CONFIG_FILE"
        CTX_FILE="$(mktemp)"
        export BRIK_WORKSPACE
        BRIK_WORKSPACE="$(mktemp -d)"
        mock.setup
        mock.create_exit "grype" 0
        mock.activate
      }
      cleanup_autoload() {
        mock.cleanup
        rm -f "$BRIK_CONFIG_FILE" "$CTX_FILE"
        rm -rf "$BRIK_WORKSPACE"
      }
      Before 'setup_autoload'
      After 'cleanup_autoload'

      It "auto-loads security.container module and runs scan"
        invoke_autoload() {
          stages.container_scan "$CTX_FILE" 2>/dev/null
          local status=$?
          grep "^BRIK_CONTAINER_SCAN_STATUS=" "$CTX_FILE" | cut -d= -f2
          return $status
        }
        When call invoke_autoload
        The status should be success
        The output should equal "success"
      End
    End

    Describe "with image and mock scanner"
      setup_with_scanner() {
        export BRIK_CONFIG_FILE
        BRIK_CONFIG_FILE="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\nsecurity:\n  container:\n    image: myapp:latest\n    severity: critical\n' > "$BRIK_CONFIG_FILE"
        CTX_FILE="$(mktemp)"
        export BRIK_WORKSPACE
        BRIK_WORKSPACE="$(mktemp -d)"
        security.container.run() { return 0; }
      }
      cleanup_with_scanner() {
        rm -f "$BRIK_CONFIG_FILE" "$CTX_FILE"
        rm -rf "$BRIK_WORKSPACE"
        unset -f security.container.run 2>/dev/null || true
      }
      Before 'setup_with_scanner'
      After 'cleanup_with_scanner'

      It "sets status to success when scan passes"
        invoke_success() {
          stages.container_scan "$CTX_FILE" 2>/dev/null
          local status=$?
          grep "^BRIK_CONTAINER_SCAN_STATUS=" "$CTX_FILE" | cut -d= -f2
          return $status
        }
        When call invoke_success
        The status should be success
        The output should equal "success"
      End
    End

    Describe "with image and failing scanner"
      setup_failing_scanner() {
        export BRIK_CONFIG_FILE
        BRIK_CONFIG_FILE="$(mktemp)"
        printf 'version: 1\nproject:\n  name: test\n  stack: node\nsecurity:\n  container:\n    image: myapp:latest\n' > "$BRIK_CONFIG_FILE"
        CTX_FILE="$(mktemp)"
        export BRIK_WORKSPACE
        BRIK_WORKSPACE="$(mktemp -d)"
        security.container.run() { return 1; }
      }
      cleanup_failing_scanner() {
        rm -f "$BRIK_CONFIG_FILE" "$CTX_FILE"
        rm -rf "$BRIK_WORKSPACE"
        unset -f security.container.run 2>/dev/null || true
      }
      Before 'setup_failing_scanner'
      After 'cleanup_failing_scanner'

      It "sets status to failed and returns non-zero"
        invoke_fail() {
          stages.container_scan "$CTX_FILE" 2>/dev/null
          local status=$?
          grep "^BRIK_CONTAINER_SCAN_STATUS=" "$CTX_FILE" | cut -d= -f2
          return $status
        }
        When call invoke_fail
        The status should equal 10
        The output should equal "failed"
      End
    End
  End
End

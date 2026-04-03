Describe "quality/deps.sh - Tier 1 command override"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/deps.sh"

  Describe "BRIK_QUALITY_DEPS_COMMAND override"
    setup_cmd() {
      TEST_WS="$(mktemp -d)"
      MOCK_BIN="$(mktemp -d)"
      cat > "${MOCK_BIN}/custom-audit" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
      chmod +x "${MOCK_BIN}/custom-audit"
      ORIG_PATH="$PATH"
      export PATH="${MOCK_BIN}:${PATH}"
      export BRIK_QUALITY_DEPS_COMMAND="custom-audit scan"
    }
    cleanup_cmd() {
      export PATH="$ORIG_PATH"
      unset BRIK_QUALITY_DEPS_COMMAND
      rm -rf "$TEST_WS" "$MOCK_BIN"
    }
    Before 'setup_cmd'
    After 'cleanup_cmd'

    It "uses BRIK_QUALITY_DEPS_COMMAND as Tier 1"
      When call quality.deps.run "$TEST_WS"
      The status should be success
      The stderr should include "dependency scan passed"
    End
  End
End

Describe "quality/coverage.sh"
  Include "$BRIK_RUNTIME_LIB/logging.sh"
  Include "$BRIK_RUNTIME_LIB/tools.sh"
  Include "$BRIK_CORE_LIB/quality/coverage.sh"

  Describe "quality.coverage.run"
    It "returns 6 for nonexistent workspace"
      When call quality.coverage.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "unknown option"
      setup_ws() { TEST_WS="$(mktemp -d)"; }
      cleanup_ws() { rm -rf "$TEST_WS"; }
      Before 'setup_ws'
      After 'cleanup_ws'

      It "returns 2 for unknown option"
        When call quality.coverage.run "$TEST_WS" --badopt
        The status should equal 2
        The stderr should include "unknown option"
      End
    End

    Describe "with no coverage report"
      setup_no_report() {
        TEST_WS="$(mktemp -d)"
      }
      cleanup_no_report() { rm -rf "$TEST_WS"; }
      Before 'setup_no_report'
      After 'cleanup_no_report'

      It "skips gracefully when no report found"
        When call quality.coverage.run "$TEST_WS"
        The status should be success
        The stderr should include "skipping"
      End
    End

    Describe "with Cobertura XML report above threshold"
      setup_above() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/coverage"
        cat > "${TEST_WS}/coverage/cobertura-coverage.xml" << 'XMLEOF'
<?xml version="1.0" ?>
<coverage line-rate="0.92" branch-rate="0.85" version="1.0">
  <packages/>
</coverage>
XMLEOF
        MOCK_BIN="$(mktemp -d)"
        if ! command -v yq >/dev/null 2>&1; then
          cat > "${MOCK_BIN}/yq" << 'EOF'
#!/usr/bin/env bash
printf '0.92\n'
EOF
          chmod +x "${MOCK_BIN}/yq"
        fi
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_above() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_above'
      After 'cleanup_above'

      It "passes when coverage is above threshold"
        When call quality.coverage.run "$TEST_WS" --threshold 80
        The status should be success
        The stderr should include "coverage check passed"
      End

      It "reports the correct percentage"
        When call quality.coverage.run "$TEST_WS" --threshold 80
        The status should be success
        The stderr should include "coverage: 92%"
      End
    End

    Describe "with Cobertura XML report below threshold"
      setup_below() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/coverage"
        cat > "${TEST_WS}/coverage/cobertura-coverage.xml" << 'XMLEOF'
<?xml version="1.0" ?>
<coverage line-rate="0.45" branch-rate="0.30" version="1.0">
  <packages/>
</coverage>
XMLEOF
        MOCK_BIN="$(mktemp -d)"
        if ! command -v yq >/dev/null 2>&1; then
          cat > "${MOCK_BIN}/yq" << 'EOF'
#!/usr/bin/env bash
printf '0.45\n'
EOF
          chmod +x "${MOCK_BIN}/yq"
        fi
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_below() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_below'
      After 'cleanup_below'

      It "fails when coverage is below threshold"
        When call quality.coverage.run "$TEST_WS" --threshold 80
        The status should equal 10
        The stderr should include "below threshold"
      End
    End

    Describe "boundary value: threshold equals coverage"
      setup_boundary() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/coverage"
        cat > "${TEST_WS}/coverage/cobertura-coverage.xml" << 'XMLEOF'
<?xml version="1.0" ?>
<coverage line-rate="0.80" branch-rate="0.80" version="1.0">
  <packages/>
</coverage>
XMLEOF
        MOCK_BIN="$(mktemp -d)"
        if ! command -v yq >/dev/null 2>&1; then
          cat > "${MOCK_BIN}/yq" << 'EOF'
#!/usr/bin/env bash
printf '0.80\n'
EOF
          chmod +x "${MOCK_BIN}/yq"
        fi
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_boundary() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_boundary'
      After 'cleanup_boundary'

      It "passes when coverage equals threshold"
        When call quality.coverage.run "$TEST_WS" --threshold 80
        The status should be success
        The stderr should include "coverage check passed"
      End
    End

    Describe "with explicit report path"
      setup_explicit() {
        TEST_WS="$(mktemp -d)"
        REPORT_FILE="${TEST_WS}/my-coverage.xml"
        cat > "$REPORT_FILE" << 'XMLEOF'
<?xml version="1.0" ?>
<coverage line-rate="0.85" branch-rate="0.80" version="1.0">
  <packages/>
</coverage>
XMLEOF
        MOCK_BIN="$(mktemp -d)"
        if ! command -v yq >/dev/null 2>&1; then
          cat > "${MOCK_BIN}/yq" << 'EOF'
#!/usr/bin/env bash
printf '0.85\n'
EOF
          chmod +x "${MOCK_BIN}/yq"
        fi
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_explicit() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_explicit'
      After 'cleanup_explicit'

      It "uses the explicit report path"
        When call quality.coverage.run "$TEST_WS" --report "$REPORT_FILE" --threshold 80
        The status should be success
        The stderr should include "coverage: 85%"
      End
    End

    Describe "auto-detect report in target/site/cobertura/"
      setup_alternate() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/target/site/cobertura"
        cat > "${TEST_WS}/target/site/cobertura/coverage.xml" << 'XMLEOF'
<?xml version="1.0" ?>
<coverage line-rate="0.75" branch-rate="0.60" version="1.0">
  <packages/>
</coverage>
XMLEOF
        MOCK_BIN="$(mktemp -d)"
        if ! command -v yq >/dev/null 2>&1; then
          cat > "${MOCK_BIN}/yq" << 'EOF'
#!/usr/bin/env bash
printf '0.75\n'
EOF
          chmod +x "${MOCK_BIN}/yq"
        fi
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:${PATH}"
      }
      cleanup_alternate() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_alternate'
      After 'cleanup_alternate'

      It "finds report in alternate location"
        When call quality.coverage.run "$TEST_WS" --threshold 70
        The status should be success
        The stderr should include "coverage: 75%"
      End
    End

    Describe "yq not available"
      setup_no_yq() {
        TEST_WS="$(mktemp -d)"
        mkdir -p "${TEST_WS}/coverage"
        cat > "${TEST_WS}/coverage/cobertura-coverage.xml" << 'XMLEOF'
<?xml version="1.0" ?>
<coverage line-rate="0.90" version="1.0">
  <packages/>
</coverage>
XMLEOF
        MOCK_BIN="$(mktemp -d)"
        ORIG_PATH="$PATH"
        export PATH="${MOCK_BIN}:/usr/bin:/bin"
      }
      cleanup_no_yq() {
        export PATH="$ORIG_PATH"
        rm -rf "$TEST_WS" "$MOCK_BIN"
      }
      Before 'setup_no_yq'
      After 'cleanup_no_yq'

      It "returns 3 when yq is not available"
        When call quality.coverage.run "$TEST_WS"
        The status should equal 3
        The stderr should include "required tool not found"
      End
    End
  End
End

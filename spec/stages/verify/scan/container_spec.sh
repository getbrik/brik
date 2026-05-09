Describe "security/container.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_HOME/lib/transverse/tools.sh"
  Include "$BRIK_HOME/lib/stages/verify/scan/container.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  Describe "verify.scan.container.run"
    Describe "Tier 3: auto-detect grype"
      setup_grype() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "grype" "$MOCK_LOG"
        mock.activate
      }
      cleanup_grype() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_grype'
      After 'cleanup_grype'

      It "auto-detects grype and scans image"
        invoke_grype() {
          verify.scan.container.run "$TEST_WS" --image "myapp:1.0" 2>/dev/null || return 1
          grep -q "grype myapp:1.0" "$MOCK_LOG"
        }
        When call invoke_grype
        The status should be success
      End

      It "writes the SARIF under the kebab-case container-scan/ artifact dir"
        invoke_grype_kebab() {
          verify.scan.container.run "$TEST_WS" --image "myapp:1.0" 2>/dev/null || return 1
          # Path is built from BRIK_WORKSPACE (or "." when unset). Assert the
          # kebab fragment regardless of the workspace prefix so the test stays
          # robust to BRIK_WORKSPACE plumbing differences across describes.
          grep -q -- "--file .*brik-artifacts/container-scan/container-scan\.sarif" "$MOCK_LOG"
        }
        When call invoke_grype_kebab
        The status should be success
      End
    End

    Describe "no scanner available"
      setup_none() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
      }
      cleanup_none() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_none'
      After 'cleanup_none'

      It "skips when no scanner available"
        When call verify.scan.container.run "$TEST_WS"
        The status should be success
        The stderr should include "skipping"
      End
    End

    Describe "findings.scan_gate stage key alignment"
      setup_gate_key() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        export BRIK_WORKSPACE="$TEST_WS"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "grype" "$MOCK_LOG"
        mock.activate
        SCAN_GATE_LOG="${TEST_WS}/scan_gate.log"
        # Stub findings.scan_gate so we can assert the stage key argument
        # without booting the full transverse.findings stack.
        eval "findings.scan_gate() { printf '%s\n' \"\$1\" > \"$SCAN_GATE_LOG\"; return 0; }"
      }
      cleanup_gate_key() {
        unset -f findings.scan_gate 2>/dev/null || true
        unset BRIK_WORKSPACE 2>/dev/null || true
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_gate_key'
      After 'cleanup_gate_key'

      It "invokes findings.scan_gate with the canonical kebab-case stage key"
        invoke_gate_key() {
          verify.scan.container.run "$TEST_WS" --image "myapp:1.0" 2>/dev/null || return 1
          cat "$SCAN_GATE_LOG"
        }
        When call invoke_gate_key
        The status should be success
        The output should equal "container-scan"
      End
    End
  End
End

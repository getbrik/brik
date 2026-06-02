Describe "security/deps.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_HOME/lib/transverse/tools.sh"
  Include "$BRIK_HOME/lib/stages/verify/scan/deps.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  Describe "verify.scan.deps.run"
    # Build an osv-scanner mock that mirrors osv-scanner 2.3.8: the single
    # authoritative scan pass writes the SARIF to the --output-file path with
    # $1 results, then exits with code $2 (1 == vulnerabilities present,
    # 0 == clean). The verdict is read from the SARIF, not the exit code.
    osv_mock_sarif() {
      local nresults="$1" code="$2" results="" i=0
      while [ "$i" -lt "$nresults" ]; do
        results="${results}{\"ruleId\":\"CVE-2026-${i}\",\"level\":\"error\"},"
        i=$((i + 1))
      done
      results="${results%,}"
      local body
      body="$(cat <<EOF
out=""
while [ \$# -gt 0 ]; do case "\$1" in --output-file) out="\$2"; shift 2 ;; *) shift ;; esac; done
if [ -n "\$out" ]; then
  cat > "\$out" <<'SARIF'
{"version":"2.1.0","runs":[{"tool":{"driver":{"name":"osv-scanner","rules":[]}},"results":[${results}]}]}
SARIF
fi
echo "Scanning dir ." >&2
exit ${code}
EOF
)"
      mock.create_script "osv-scanner" "$body"
    }

    # osv-scanner that crashes before writing any SARIF (no --output-file
    # write), the council "case 3" tool failure.
    osv_mock_crash() {
      mock.create_script "osv-scanner" 'echo "panic: runtime error: invalid memory address" >&2
exit 2'
    }

    It "returns 6 for nonexistent workspace"
      When call verify.scan.deps.run "/nonexistent/workspace"
      The status should equal 6
      The stderr should include "required directory not found"
    End

    Describe "Tier 1: command override"
      setup_cmd() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_exit "my-scanner" 0
        mock.activate
        export BRIK_SECURITY_DEPS_COMMAND="my-scanner"
      }
      cleanup_cmd() {
        unset BRIK_SECURITY_DEPS_COMMAND
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_cmd'
      After 'cleanup_cmd'

      It "runs command override"
        When call verify.scan.deps.run "$TEST_WS"
        The status should be success
        The stderr should include "security dependency scan passed"
      End
    End

    Describe "Tier 2: explicit tool"
      setup_tool() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        MOCK_LOG="${TEST_WS}/mock.log"
        mock.create_logging "grype" "$MOCK_LOG"
        mock.activate
        export BRIK_SECURITY_DEPS_TOOL="grype"
      }
      cleanup_tool() {
        unset BRIK_SECURITY_DEPS_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_tool'
      After 'cleanup_tool'

      It "runs specified tool"
        invoke_tool() {
          verify.scan.deps.run "$TEST_WS" 2>/dev/null || return 1
          grep -q "^grype" "$MOCK_LOG"
        }
        When call invoke_tool
        The status should be success
      End
    End

    Describe "Tier 2: osv-scanner no package sources"
      setup_no_sources() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_script "osv-scanner" 'echo "No package sources found, --help for usage information." >&2
exit 128'
        mock.activate
        export BRIK_SECURITY_DEPS_TOOL="osv-scanner"
      }
      cleanup_no_sources() {
        unset BRIK_SECURITY_DEPS_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_no_sources'
      After 'cleanup_no_sources'

      It "skips when osv-scanner finds no package sources"
        When call verify.scan.deps.run "$TEST_WS"
        The status should be success
        The stderr should include "no package sources found"
      End
    End

    Describe "Tier 2: osv-scanner finds vulnerabilities"
      setup_vuln() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        osv_mock_sarif 3 1
        mock.activate
        export BRIK_SECURITY_DEPS_TOOL="osv-scanner"
      }
      cleanup_vuln() {
        unset BRIK_SECURITY_DEPS_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_vuln'
      After 'cleanup_vuln'

      It "returns 10 when the authoritative SARIF carries vulnerabilities"
        When call verify.scan.deps.run "$TEST_WS"
        The status should equal 10
        The stderr should include "security dependency vulnerabilities found"
      End

      It "writes the SARIF from the authoritative pass with the real findings"
        sarif_results() {
          verify.scan.deps.run "$TEST_WS" >/dev/null 2>&1
          jq '[.runs[].results[]?] | length' "$TEST_WS/brik-artifacts/scan/deps.sarif"
        }
        When call sarif_results
        The output should equal "3"
      End
    End

    Describe "Tier 2: osv-scanner clean scan"
      setup_clean() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        osv_mock_sarif 0 0
        mock.activate
        export BRIK_SECURITY_DEPS_TOOL="osv-scanner"
      }
      cleanup_clean() {
        unset BRIK_SECURITY_DEPS_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_clean'
      After 'cleanup_clean'

      It "passes with a valid empty SARIF (zero findings)"
        When call verify.scan.deps.run "$TEST_WS"
        The status should be success
        The stderr should include "security dependency scan passed"
      End

      It "still writes the SARIF so business.deps can read a real zero count"
        sarif_results() {
          verify.scan.deps.run "$TEST_WS" >/dev/null 2>&1
          jq '[.runs[].results[]?] | length' "$TEST_WS/brik-artifacts/scan/deps.sarif"
        }
        When call sarif_results
        The output should equal "0"
      End
    End

    Describe "Tier 2: osv-scanner exits non-zero with a clean SARIF"
      # An extraction error can make osv-scanner exit non-zero while the SARIF
      # it produced reports zero vulnerabilities. The verdict follows the SARIF
      # content, not the exit code, so this is a pass.
      setup_zero_vulns() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        osv_mock_sarif 0 1
        mock.activate
        export BRIK_SECURITY_DEPS_TOOL="osv-scanner"
      }
      cleanup_zero_vulns() {
        unset BRIK_SECURITY_DEPS_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_zero_vulns'
      After 'cleanup_zero_vulns'

      It "treats a non-zero exit with an empty SARIF as a pass"
        When call verify.scan.deps.run "$TEST_WS"
        The status should be success
        The stderr should include "security dependency scan passed"
      End
    End

    Describe "Tier 2: osv-scanner crashes before producing a report"
      # Council case 3: a tool failure that writes no valid SARIF must surface
      # a scanner error and fail -- it must NEVER be reported as a clean
      # "0 findings" success (the node-full-cve contradiction in reverse).
      setup_crash() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        osv_mock_crash
        mock.activate
        export BRIK_SECURITY_DEPS_TOOL="osv-scanner"
      }
      cleanup_crash() {
        unset BRIK_SECURITY_DEPS_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_crash'
      After 'cleanup_crash'

      It "fails with a scanner error, never a 0-findings success"
        When call verify.scan.deps.run "$TEST_WS"
        The status should equal 10
        The stderr should include "scanner error"
        The stderr should not include "security dependency scan passed"
      End

      It "does not leave a valid SARIF behind to be mistaken for a clean scan"
        sarif_absent() {
          verify.scan.deps.run "$TEST_WS" >/dev/null 2>&1
          if [ -f "$TEST_WS/brik-artifacts/scan/deps.sarif" ] \
             && jq -e 'has("runs")' "$TEST_WS/brik-artifacts/scan/deps.sarif" >/dev/null 2>&1; then
            echo "present"
          else
            echo "absent"
          fi
        }
        When call sarif_absent
        The output should equal "absent"
      End

      It "does not read a stale SARIF from a prior run as a clean pass"
        stale_then_crash() {
          mkdir -p "$TEST_WS/brik-artifacts/scan"
          printf '%s\n' '{"version":"2.1.0","runs":[{"tool":{"driver":{"name":"osv-scanner","rules":[]}},"results":[]}]}' \
            > "$TEST_WS/brik-artifacts/scan/deps.sarif"
          verify.scan.deps.run "$TEST_WS"
        }
        When call stale_then_crash
        The status should equal 10
        The stderr should include "scanner error"
        The stderr should not include "security dependency scan passed"
      End
    End

    Describe "Tier 2: osv-scanner exits zero without a report"
      # A scanner that succeeds (exit 0) but emits no SARIF has nothing to
      # gate on -- a benign no-op, treated as a clean pass (not a tool error).
      # Real osv-scanner always writes a SARIF on a zero exit; this guards the
      # stubbed-tool case without masking a crash (a crash exits non-zero).
      setup_noreport() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.create_script "osv-scanner" 'exit 0'
        mock.activate
        export BRIK_SECURITY_DEPS_TOOL="osv-scanner"
      }
      cleanup_noreport() {
        unset BRIK_SECURITY_DEPS_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_noreport'
      After 'cleanup_noreport'

      It "passes when the tool exits zero but writes no SARIF"
        When call verify.scan.deps.run "$TEST_WS"
        The status should be success
        The stderr should include "security dependency scan passed"
      End
    End

    Describe "Tier 2: tool not found"
      setup_missing() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        mock.isolate
        export BRIK_SECURITY_DEPS_TOOL="grype"
      }
      cleanup_missing() {
        unset BRIK_SECURITY_DEPS_TOOL
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_missing'
      After 'cleanup_missing'

      It "returns 3 when tool not found"
        When call verify.scan.deps.run "$TEST_WS"
        The status should equal 3
        The stderr should include "not found"
      End
    End

    Describe "Tier 3: auto-detect osv-scanner"
      setup_auto() {
        mock.setup
        TEST_WS="$(mktemp -d)"
        osv_mock_sarif 0 0
        mock.activate
      }
      cleanup_auto() {
        mock.cleanup
        rm -rf "$TEST_WS"
      }
      Before 'setup_auto'
      After 'cleanup_auto'

      It "auto-detects osv-scanner and runs the authoritative SARIF pass"
        invoke_auto() {
          verify.scan.deps.run "$TEST_WS" 2>/dev/null || return 1
          [ -f "$TEST_WS/brik-artifacts/scan/deps.sarif" ]
        }
        When call invoke_auto
        The status should be success
      End
    End

    Describe "no tool available"
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

      It "skips when no tool available"
        When call verify.scan.deps.run "$TEST_WS"
        The status should be success
        The stderr should include "skipping"
      End
    End
  End
End

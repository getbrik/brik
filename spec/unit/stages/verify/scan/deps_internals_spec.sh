Describe "security/deps.sh internal branches"
  # Companion to deps_spec.sh. These in-process tests exercise the branches
  # the main spec leaves uncovered: the Tier-1 command-override FAILURE path,
  # the rc==7 "unknown tool" path, the unknown-arg passthrough in the arg
  # parser, and -- crucially -- the "no findings module" fallback verdicts in
  # both _run_osv and _run_table, plus the grype (_run_table) extraction-error
  # / no-package-sources / gate-fail branches.
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_HOME/lib/transverse/tools.sh"
  Include "$BRIK_HOME/lib/stages/verify/scan/deps.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  # Reuse the osv SARIF mock shape from deps_spec.sh: a single authoritative
  # pass writes a SARIF with $1 results to --output-file, then exits $2.
  osv_mock_sarif() {
    local nresults="$1" code="$2" results="" i=0
    while [ "$i" -lt "$nresults" ]; do
      results="${results}{\"ruleId\":\"CVE-2026-${i}\",\"level\":\"error\",\"message\":{\"text\":\"Package 'pkg@1.0.0' is vulnerable to 'CVE-2026-${i}'.\"}},"
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
exit ${code}
EOF
)"
    mock.create_script "osv-scanner" "$body"
  }

  # Force the "no findings module" fallback: mark transverse.findings as
  # already loaded so deps.sh's lazy `brik.use transverse.findings` is a
  # no-op, and make sure findings.scan_gate is undefined. With that, _run_osv
  # and _run_table take their result-count / tool-rc verdict branches.
  suppress_findings() {
    unset -f findings.scan_gate 2>/dev/null || true
    export _BRIK_MODULE_TRANSVERSE_FINDINGS_LOADED=1
  }
  restore_findings() {
    unset _BRIK_MODULE_TRANSVERSE_FINDINGS_LOADED 2>/dev/null || true
  }

  Describe "Tier 1: command override failure"
    setup_fail() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      mock.activate
      # A command that exits non-zero -> the override eval fails.
      export BRIK_SECURITY_DEPS_COMMAND="false"
    }
    cleanup_fail() {
      unset BRIK_SECURITY_DEPS_COMMAND
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_fail'
    After 'cleanup_fail'

    It "returns 10 and reports vulnerabilities when the override command fails (deps.sh:44-46)"
      When call verify.scan.deps.run "$TEST_WS"
      The status should equal 10
      The stderr should include "command override"
      The stderr should include "security dependency vulnerabilities found"
    End
  End

  Describe "arg parser: unknown flag passthrough"
    setup_args() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      mock.activate
      # Command override short-circuits the registry so the test stays simple;
      # we only need the arg loop to consume the unknown flag (deps.sh:35).
      export BRIK_SECURITY_DEPS_COMMAND="true"
    }
    cleanup_args() {
      unset BRIK_SECURITY_DEPS_COMMAND
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_args'
    After 'cleanup_args'

    It "ignores an unknown flag and still passes (deps.sh:35)"
      When call verify.scan.deps.run "$TEST_WS" --bogus-flag value --severity critical
      The status should be success
      The stderr should include "security dependency scan passed"
    End
  End

  Describe "Tier 2: unknown tool name (rc 7)"
    setup_unknown() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      mock.activate
      # A tool name not registered for the sec_deps family triggers
      # transverse.tools.resolve rc==7 -> CONFIG_ERROR (deps.sh:64-65).
      export BRIK_SECURITY_DEPS_TOOL="not-a-real-scanner"
    }
    cleanup_unknown() {
      unset BRIK_SECURITY_DEPS_TOOL
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_unknown'
    After 'cleanup_unknown'

    It "returns 7 (config error) for an unknown scanner name (deps.sh:64-65)"
      When call verify.scan.deps.run "$TEST_WS"
      The status should equal 7
      The stderr should include "unknown security dependency scan tool"
    End
  End

  Describe "_run_osv without a findings module"
    setup_osv_nofindings() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      mock.activate
      export BRIK_SECURITY_DEPS_TOOL="osv-scanner"
      suppress_findings
    }
    cleanup_osv_nofindings() {
      unset BRIK_SECURITY_DEPS_TOOL
      restore_findings
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_osv_nofindings'
    After 'cleanup_osv_nofindings'

    It "fails on vulnerabilities using the SARIF result count as the verdict (deps.sh:177-179)"
      osv_mock_sarif 2 1
      When call verify.scan.deps.run "$TEST_WS"
      The status should equal 10
      The stderr should include "security dependency vulnerabilities found"
      The stderr should include "dependency vulnerabilities found (2)"
    End

    It "passes on a clean SARIF with no findings module present (deps.sh:181-182)"
      osv_mock_sarif 0 0
      When call verify.scan.deps.run "$TEST_WS"
      The status should be success
      The stderr should include "security dependency scan passed"
    End
  End

  Describe "_run_table (grype) without a findings module"
    setup_grype_nofindings() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      mock.activate
      export BRIK_SECURITY_DEPS_TOOL="grype"
      suppress_findings
    }
    cleanup_grype_nofindings() {
      unset BRIK_SECURITY_DEPS_TOOL
      restore_findings
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_grype_nofindings'
    After 'cleanup_grype_nofindings'

    It "passes when grype exits zero (deps.sh:191,225-226)"
      mock.create_script "grype" 'echo "No vulnerabilities found" ; exit 0'
      When call verify.scan.deps.run "$TEST_WS"
      The status should be success
      The stderr should include "security dependency scan passed"
    End

    It "skips when grype reports no package sources (deps.sh:194-199)"
      mock.create_script "grype" 'echo "No package sources found" >&2 ; exit 1'
      When call verify.scan.deps.run "$TEST_WS"
      The status should be success
      The stderr should include "no package sources found"
    End

    It "treats grype extraction errors with zero vulns as a pass (deps.sh:203-206)"
      mock.create_script "grype" 'echo "deps.dev RPC error" >&2
echo "Total 0 packages affected by 0 known vulnerabilities" >&2
exit 1'
      When call verify.scan.deps.run "$TEST_WS"
      The status should be success
      The stderr should include "treating as pass"
      The stderr should include "security dependency scan passed"
    End

    It "fails when grype exits non-zero with real vulnerabilities (deps.sh:220-223)"
      mock.create_script "grype" 'echo "found 3 vulnerabilities" >&2 ; exit 1'
      When call verify.scan.deps.run "$TEST_WS"
      The status should equal 10
      The stderr should include "security dependency vulnerabilities found"
    End
  End

  Describe "_run_table (grype) with the findings gate failing"
    # Keep the findings module loaded so _run_table takes the gate branch.
    # grype writes no SARIF, so findings.scan_gate falls back to the tool exit
    # code; a non-zero exit makes the gate fail -> deps.sh:215-217.
    setup_grype_gatefail() {
      mock.setup
      TEST_WS="$(mktemp -d)"
      mock.activate
      mock.create_script "grype" 'echo "found vulnerabilities" >&2 ; exit 1'
      export BRIK_SECURITY_DEPS_TOOL="grype"
    }
    cleanup_grype_gatefail() {
      unset BRIK_SECURITY_DEPS_TOOL
      mock.cleanup
      rm -rf "$TEST_WS"
    }
    Before 'setup_grype_gatefail'
    After 'cleanup_grype_gatefail'

    It "fails through the findings gate fallback to the tool exit code (deps.sh:215-217)"
      When call verify.scan.deps.run "$TEST_WS"
      The status should equal 10
      The stderr should include "security dependency vulnerabilities found"
    End
  End
End

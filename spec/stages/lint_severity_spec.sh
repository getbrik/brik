#shellcheck shell=bash
# SC19 acceptance: lint severity passthrough.
#
# The fix_classifier annotates each lint result with brikToolBlocking
# (true for eslint error, ruff E*/F*, etc.; false for eslint warning,
# ruff I*/W*). findings.aggregate counts only the tool-blocking subset
# in business.findings.failing.{has_fix,no_fix}.
#
# Acceptance: a project with eslint error -> failing.has_fix > 0 ->
# business.evaluate returns error in release context. A project with
# only eslint warnings -> failing.has_fix == 0 -> business.evaluate
# stays warning even in release.

Describe "lint severity passthrough (SC19)"
  Include "$BRIK_HOME/lib/pipeline/error.sh"
  Include "$BRIK_HOME/lib/pipeline/logging.sh"
  Include "$BRIK_HOME/lib/transverse/sarif.sh"
  Include "$BRIK_HOME/lib/transverse/fix_classifier.sh"
  Include "$BRIK_HOME/lib/transverse/findings.sh"
  Include "$BRIK_HOME/lib/pipeline/report.sh"
  Include "$BRIK_HOME/lib/pipeline/business.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_lint_sev() {
    LS_LOG_DIR="$(mktemp -d)"
    export BRIK_LOG_DIR="$LS_LOG_DIR"
    mock.workspace.setup
    export BRIK_RUN_ID="lint-sev-spec"
    export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
    # Lower the severity floor so apply_policy keeps warning-level
    # results in failing[]. SC19 must filter them by brikToolBlocking
    # independent of the policy floor; pinning the floor here isolates
    # the SC19 contract from the policy-floor interaction.
    export BRIK_SECURITY_SEVERITY_THRESHOLD="info"
    unset BRIK_POLICY_CACHE_PATH BRIK_COMMIT_TAG
    report.init >/dev/null 2>&1 || true
  }
  cleanup_lint_sev() {
    rm -rf "$LS_LOG_DIR"
    mock.workspace.teardown
    unset BRIK_RUN_ID BRIK_QUALITY_FINDINGS_POLICY BRIK_COMMIT_TAG BRIK_SECURITY_SEVERITY_THRESHOLD
  }
  Before 'setup_lint_sev'
  After  'cleanup_lint_sev'

  process_fixture() {
    local fixture="$1"
    local in="$BRIK_WORKSPACE/lint.sarif"
    cp "$BRIK_HOME/spec/fixtures/sarif/$fixture" "$in"
    findings.process "lint" "$in" >/dev/null 2>&1
  }

  read_failing() {
    jq -r --arg s "lint" \
      '.stages[] | select(.stage == $s) | "\(.business.findings.failing.total),\(.business.findings.failing.has_fix),\(.business.findings.failing.no_fix)"' \
      "$BRIK_LOG_DIR/aggregate-report.json"
  }

  Describe "eslint mixed levels (3 error + 2 warning)"
    It "records failing.total=5 but failing.has_fix=3 (only blocking entries count)"
      do_run() {
        process_fixture "eslint.sarif"
        read_failing
      }
      When call do_run
      # total includes every non-suppressed result; has_fix only the
      # tool-blocking ones (eslint error).
      The output should equal "5,3,0"
    End

    It "yields business.status=warning in snapshot for eslint error"
      do_run() {
        process_fixture "eslint.sarif"
        local has_fix; has_fix="$(jq -r '.stages[] | select(.stage == "lint") | .business.findings.failing.has_fix' "$BRIK_LOG_DIR/aggregate-report.json")"
        local payload; payload="$(business.evaluate \
            --tech-status failed \
            --context snapshot \
            --findings-failing-has-fix "$has_fix" \
            --tech-kind "lint-failure")"
        jq -r '.status' <<<"$payload"
      }
      When call do_run
      The output should equal "warning"
    End

    It "yields business.status=error in release for eslint error"
      do_run() {
        process_fixture "eslint.sarif"
        local has_fix; has_fix="$(jq -r '.stages[] | select(.stage == "lint") | .business.findings.failing.has_fix' "$BRIK_LOG_DIR/aggregate-report.json")"
        local payload; payload="$(business.evaluate \
            --tech-status failed \
            --context release \
            --findings-failing-has-fix "$has_fix" \
            --tech-kind "lint-failure")"
        jq -r '.status' <<<"$payload"
      }
      When call do_run
      The output should equal "error"
    End
  End

  Describe "warnings-only scenario (eslint warning only)"
    setup_warn_only() {
      WARN_FIXTURE="$BRIK_WORKSPACE/eslint-warn-only.sarif"
      jq '.runs[0].results |= map(select(.level == "warning"))' \
        "$BRIK_HOME/spec/fixtures/sarif/eslint.sarif" > "$WARN_FIXTURE"
    }
    Before 'setup_warn_only'

    It "records failing.has_fix=0 even though failing.total=2"
      do_run() {
        cp "$WARN_FIXTURE" "$BRIK_WORKSPACE/lint.sarif"
        findings.process "lint" "$BRIK_WORKSPACE/lint.sarif" >/dev/null 2>&1
        read_failing
      }
      When call do_run
      The output should equal "2,0,0"
    End

    It "stays at success in release context (no blocking findings)"
      do_run() {
        cp "$WARN_FIXTURE" "$BRIK_WORKSPACE/lint.sarif"
        findings.process "lint" "$BRIK_WORKSPACE/lint.sarif" >/dev/null 2>&1
        # tech.status=success because the linter ran fine; failing.total>0
        # but has_fix==0 (all non-blocking), so business stays at success.
        # Note: success branch in business.evaluate emits warning only if
        # failing.no_fix > 0 OR ignored > 0. None of those apply -> success.
        local payload; payload="$(business.evaluate \
            --tech-status success \
            --context release \
            --findings-failing-has-fix 0 \
            --findings-failing-no-fix 0)"
        jq -r '.status' <<<"$payload"
      }
      When call do_run
      The output should equal "success"
    End
  End

  Describe "ruff mixed prefixes (E/F blocking, I/W non-blocking)"
    setup_ruff_mixed() {
      MIXED_FIXTURE="$BRIK_WORKSPACE/ruff-mixed.sarif"
      jq '.runs[0].tool.driver.name = "ruff"
        | .runs[0].results = [
            {ruleId: "E401", level: "error",   message: {text: "E401"}},
            {ruleId: "F401", level: "error",   message: {text: "F401"}},
            {ruleId: "I001", level: "error",   message: {text: "I001"}},
            {ruleId: "W605", level: "warning", message: {text: "W605"}}
          ]' \
        "$BRIK_HOME/spec/fixtures/sarif/ruff.sarif" > "$MIXED_FIXTURE"
    }
    Before 'setup_ruff_mixed'

    It "counts 2 blocking (E + F) of 4 failing entries"
      do_run() {
        cp "$MIXED_FIXTURE" "$BRIK_WORKSPACE/lint.sarif"
        findings.process "lint" "$BRIK_WORKSPACE/lint.sarif" >/dev/null 2>&1
        read_failing
      }
      When call do_run
      The output should equal "4,2,0"
    End
  End
End

#shellcheck shell=bash disable=SC2148,SC2317,SC2329
# Error-path coverage for lib/transverse/findings.sh.
#
# The happy paths and most argument-validation branches are exercised by
# findings_spec.sh. This spec targets the harder-to-reach error branches
# flagged by kcov: missing dependency probes, IO failures (unwritable
# output paths, mv failures), severity-floor edge values, converter
# sourcing failures, and the findings.scan_gate / findings.gate guards.
#
# Every block drives a single uncovered branch with the input that
# triggers it and asserts the exit status and/or the stderr message.

Describe "transverse/findings.sh error paths"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/pipeline/report.sh"
  Include "$BRIK_HOME/lib/transverse/sarif.sh"
  Include "$BRIK_HOME/lib/transverse/findings.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  FIX="${BRIK_HOME}/spec/fixtures/sarif"
  GRYPE="${BRIK_HOME}/spec/fixtures/sarif/grype-fixstate.sarif"

  setup_env() {
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"
    mock.workspace.setup
    export BRIK_RUN_ID="findings-error-paths-spec"
    unset BRIK_QUALITY_FINDINGS_POLICY BRIK_SECURITY_SEVERITY_THRESHOLD \
          BRIK_POLICY_CACHE_PATH
    report.init >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -rf "$BRIK_LOG_DIR"
    mock.workspace.teardown
    unset BRIK_RUN_ID BRIK_QUALITY_FINDINGS_POLICY \
          BRIK_SECURITY_SEVERITY_THRESHOLD BRIK_POLICY_CACHE_PATH
  }
  Before 'setup_env'
  After 'cleanup_env'

  # ---------------------------------------------------------------------------
  # findings.from_sarif -- transverse.sarif module not loaded (L73-75)
  # ---------------------------------------------------------------------------
  Describe "findings.from_sarif missing transverse.sarif"
    It "fails with MISSING_DEP when sarif.is_valid is not declared"
      no_sarif_module() {
        # Drop the SARIF helper so the declare -f probe fails. The input
        # file must exist so the function reaches the dependency check.
        unset -f sarif.is_valid
        findings.from_sarif "sast" "$FIX/semgrep.sarif"
      }
      When call no_sarif_module
      The status should equal 3
      The stderr should include "transverse.sarif module not loaded"
    End
  End

  # ---------------------------------------------------------------------------
  # findings.apply_policy -- severity floor edge values (L171-175)
  # ---------------------------------------------------------------------------
  Describe "findings.apply_policy severity floor values"
    setup_floor() { OUT="$(mktemp).sarif"; export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"; }
    cleanup_floor() { rm -f "$OUT"; }
    Before 'setup_floor'
    After 'cleanup_floor'

    It "accepts floor=low"
      apply_low() {
        export BRIK_SECURITY_SEVERITY_THRESHOLD="low"
        findings.apply_policy "$GRYPE" "$OUT"
      }
      When call apply_low
      The status should be success
    End

    It "accepts floor=info"
      apply_info() {
        export BRIK_SECURITY_SEVERITY_THRESHOLD="info"
        findings.apply_policy "$GRYPE" "$OUT"
      }
      When call apply_info
      The status should be success
    End

    It "accepts floor=critical"
      apply_critical() {
        export BRIK_SECURITY_SEVERITY_THRESHOLD="critical"
        findings.apply_policy "$GRYPE" "$OUT"
      }
      When call apply_critical
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # findings.apply_policy -- cannot create output directory (L184-187)
  # ---------------------------------------------------------------------------
  Describe "findings.apply_policy unwritable output directory"
    It "fails IO when the output directory cannot be created"
      bad_out_dir() {
        # Parent of the requested out dir is a regular file, so mkdir -p
        # of the directory portion cannot succeed.
        local blocker
        blocker="$(mktemp)"
        local bad_out="${blocker}/sub/findings.sarif"
        export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
        findings.apply_policy "$GRYPE" "$bad_out"
        local rc=$?
        rm -f "$blocker"
        return "$rc"
      }
      When call bad_out_dir
      The status should equal 6
      The stderr should include "cannot create output directory"
    End
  End

  # ---------------------------------------------------------------------------
  # findings.apply_policy -- jq not on PATH (L189-192)
  # ---------------------------------------------------------------------------
  Describe "findings.apply_policy jq missing"
    setup_no_jq() {
      OUT="$(mktemp).sarif"
      mock.setup
      mock.preserve_cmds
      mock.isolate
    }
    cleanup_no_jq() {
      mock.cleanup
      rm -f "$OUT"
    }
    Before 'setup_no_jq'
    After 'cleanup_no_jq'

    It "fails with MISSING_DEP when jq is absent"
      apply_no_jq() {
        export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
        export BRIK_SECURITY_SEVERITY_THRESHOLD="high"
        findings.apply_policy "$GRYPE" "$OUT"
      }
      When call apply_no_jq
      The status should equal 3
      The stderr should include "jq not on PATH"
    End
  End

  # ---------------------------------------------------------------------------
  # findings.apply_policy -- mv failure writing the output (L352-356)
  # ---------------------------------------------------------------------------
  Describe "findings.apply_policy cannot write output"
    setup_bad_mv() {
      OUT="$(mktemp).sarif"
      # A failing mv intercepts the post-jq move. mock.activate prepends
      # MOCK_BIN so jq/mktemp/dirname still resolve from the system PATH.
      mock.setup
      mock.create_failing "mv"
      mock.activate
    }
    cleanup_bad_mv() {
      mock.cleanup
      rm -f "$OUT"
    }
    Before 'setup_bad_mv'
    After 'cleanup_bad_mv'

    It "fails IO when mv cannot write the policy SARIF"
      apply_bad_mv() {
        export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
        findings.apply_policy "$GRYPE" "$OUT"
      }
      When call apply_bad_mv
      The status should equal 6
      The stderr should include "cannot write"
    End
  End

  # ---------------------------------------------------------------------------
  # findings.process -- apply_policy failure falls back to raw aggregate
  # (L564-567): an invalid preset makes apply_policy return non-zero.
  # ---------------------------------------------------------------------------
  Describe "findings.process apply_policy fallback"
    setup_proc() {
      mkdir -p "$BRIK_WORKSPACE/brik-artifacts/container-scan"
      PROC_SARIF="$BRIK_WORKSPACE/brik-artifacts/container-scan/container-scan.sarif"
      cp "$GRYPE" "$PROC_SARIF"
    }
    Before 'setup_proc'

    It "warns and aggregates the raw SARIF when apply_policy fails"
      proc_bad_preset() {
        # An unknown preset makes findings.apply_policy return CONFIG_ERROR;
        # findings.process must emit the fallback warning and still return 0.
        export BRIK_QUALITY_FINDINGS_POLICY="aggressive"
        findings.process "container-scan" "$PROC_SARIF"
      }
      When call proc_bad_preset
      The status should be success
      The stderr should include "apply_policy failed"
    End

    It "records L4 v1 counters from the raw SARIF on the fallback path"
      proc_bad_preset_counts() {
        export BRIK_QUALITY_FINDINGS_POLICY="aggressive"
        findings.process "container-scan" "$PROC_SARIF" >/dev/null 2>&1
        jq -r '.stages[] | select(.stage == "container-scan") | .business.findings.total' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call proc_bad_preset_counts
      The output should equal "8"
    End
  End

  # ---------------------------------------------------------------------------
  # findings.scan_gate -- argument validation + gate composition
  # (L592-599, L602-615)
  # ---------------------------------------------------------------------------
  Describe "findings.scan_gate"
    It "rejects missing arguments"
      When call findings.scan_gate
      The status should equal 2
      The stderr should include "missing arguments"
    End

    It "rejects an empty stage name"
      When call findings.scan_gate "" "0" "$GRYPE"
      The status should equal 2
      The stderr should include "stage must not be empty"
    End

    It "returns the tool exit code when no SARIF is on disk"
      no_sarif() {
        findings.scan_gate "container-scan" "4" "/nonexistent.sarif"
      }
      When call no_sarif
      The status should equal 4
    End

    It "returns 0 when the policy gate records a passing stage"
      gate_pass() {
        local sarif="$BRIK_WORKSPACE/scan-gate.sarif"
        printf '%s' '{"version":"2.1.0","runs":[{"tool":{"driver":{"name":"t"}},"results":[]}]}' \
          > "$sarif"
        export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
        findings.scan_gate "scan" "1" "$sarif"
      }
      When call gate_pass
      The status should be success
    End

    It "returns CHECK_FAILED when the policy gate records failing findings"
      gate_fail() {
        local sarif="$BRIK_WORKSPACE/scan-gate-fail.sarif"
        cp "$GRYPE" "$sarif"
        export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
        findings.scan_gate "scan" "0" "$sarif"
      }
      When call gate_fail
      The status should equal 10
    End
  End

  # ---------------------------------------------------------------------------
  # findings.gate -- empty stage name + non-flock read path (L639-641, L666)
  # ---------------------------------------------------------------------------
  Describe "findings.gate"
    It "rejects an empty stage name"
      When call findings.gate ""
      The status should equal 2
      The stderr should include "stage must not be empty"
    End

    Describe "without flock available"
      # The backend is populated by findings.process BEFORE PATH isolation
      # (process needs jq, cp, mktemp, ...). Then PATH is reduced to a mock
      # bin that carries only jq, hiding flock so findings.gate takes the
      # plain jq read branch instead of the flock-wrapped one.
      It "reads failing findings without flock and fails on a non-zero count"
        gate_no_flock_fail() {
          local sarif="$BRIK_WORKSPACE/gate.sarif"
          cp "$GRYPE" "$sarif"
          export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
          findings.process "scan" "$sarif" >/dev/null 2>&1
          mock.setup
          mock.preserve_cmds
          local jq_path
          jq_path="$(command -v jq 2>/dev/null)"
          [[ -n "$jq_path" ]] && ln -s "$jq_path" "${MOCK_BIN}/jq"
          mock.isolate
          findings.gate "scan"
          local rc=$?
          mock.cleanup
          return "$rc"
        }
        When call gate_no_flock_fail
        The status should equal 10
      End

      It "reads failing findings without flock and passes on a zero count"
        gate_no_flock_pass() {
          local sarif="$BRIK_WORKSPACE/gate-pass.sarif"
          printf '%s' '{"version":"2.1.0","runs":[{"tool":{"driver":{"name":"t"}},"results":[]}]}' \
            > "$sarif"
          export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
          findings.process "scan" "$sarif" >/dev/null 2>&1
          mock.setup
          mock.preserve_cmds
          local jq_path
          jq_path="$(command -v jq 2>/dev/null)"
          [[ -n "$jq_path" ]] && ln -s "$jq_path" "${MOCK_BIN}/jq"
          mock.isolate
          findings.gate "scan"
          local rc=$?
          mock.cleanup
          return "$rc"
        }
        When call gate_no_flock_pass
        The status should be success
      End
    End
  End

  # ---------------------------------------------------------------------------
  # findings.from_json -- converter sourcing / definition / IO failures
  # (L728-748)
  # ---------------------------------------------------------------------------
  Describe "findings.from_json converter failures"
    setup_fj() {
      FJ_TMP="$(mktemp -d)"
      FJ_INPUT="$FJ_TMP/input.json"
      FJ_OUTPUT="$FJ_TMP/output.sarif"
      printf '%s' '{"results":[]}' > "$FJ_INPUT"
    }
    cleanup_fj() { rm -rf "$FJ_TMP"; }
    Before 'setup_fj'
    After 'cleanup_fj'

    It "fails CONFIG_ERROR when the converter does not define to_sarif"
      # A converter file that exists but never defines the expected
      # findings.converters.<tool>.to_sarif function. Placed next to a
      # real converter dir so the dispatcher path resolution finds it.
      stub_no_fn() {
        local conv_dir="${BRIK_HOME}/lib/transverse/findings/converters"
        local stub="${conv_dir}/erpstub.sh"
        printf '%s\n' '# intentionally defines nothing' > "$stub"
        findings.from_json erpstub "$FJ_INPUT" "$FJ_OUTPUT"
        local rc=$?
        rm -f "$stub"
        return "$rc"
      }
      When call stub_no_fn
      The status should equal 7
      The stderr should include "did not define"
    End

    It "fails when sourcing the converter errors out"
      # A converter file whose body returns a non-zero status when sourced
      # drives the source-failure branch of the dispatcher.
      stub_bad_source() {
        local conv_dir="${BRIK_HOME}/lib/transverse/findings/converters"
        local stub="${conv_dir}/erpbadsrc.sh"
        printf '%s\n' 'return 4' > "$stub"
        findings.from_json erpbadsrc "$FJ_INPUT" "$FJ_OUTPUT"
        local rc=$?
        rm -f "$stub"
        return "$rc"
      }
      When call stub_bad_source
      The status should not equal 0
      The stderr should include "failed to source converter"
    End

    It "fails IO when the output directory cannot be created"
      # ruff is a real converter; the input exists so the dispatcher
      # reaches the mkdir -p of the output's parent. The parent is a
      # regular file, so directory creation fails.
      bad_out_dir() {
        local blocker
        blocker="$(mktemp)"
        local bad_out="${blocker}/sub/out.sarif"
        findings.from_json ruff "$FJ_INPUT" "$bad_out"
        local rc=$?
        rm -f "$blocker"
        return "$rc"
      }
      When call bad_out_dir
      The status should equal 6
      The stderr should include "cannot create output directory"
    End

    It "fails when the converter itself returns non-zero"
      # A converter that defines to_sarif but the function exits non-zero
      # drives the "converter failed" branch.
      stub_failing_fn() {
        local conv_dir="${BRIK_HOME}/lib/transverse/findings/converters"
        local stub="${conv_dir}/erpfail.sh"
        printf '%s\n' 'findings.converters.erpfail.to_sarif() { return 1; }' > "$stub"
        findings.from_json erpfail "$FJ_INPUT" "$FJ_OUTPUT"
        local rc=$?
        rm -f "$stub"
        return "$rc"
      }
      When call stub_failing_fn
      The status should not equal 0
      The stderr should include "converter failed"
    End
  End

  # ---------------------------------------------------------------------------
  # findings.merge_pipeline -- jq missing, mv failures
  # (L805-807, L856-859, L880-883)
  # ---------------------------------------------------------------------------
  Describe "findings.merge_pipeline error paths"
    It "fails with MISSING_DEP when jq is absent"
      merge_no_jq() {
        local ws
        ws="$(mktemp -d)"
        mkdir -p "$ws/brik-artifacts"
        mock.setup
        mock.preserve_cmds
        mock.isolate
        findings.merge_pipeline "$ws"
        local rc=$?
        mock.cleanup
        rm -rf "$ws"
        return "$rc"
      }
      When call merge_no_jq
      The status should equal 3
      The stderr should include "jq is required"
    End

    Describe "mv failure on the aggregate write"
      # A failing mv intercepts the post-jq move. mock.activate prepends
      # MOCK_BIN so jq/mktemp/mkdir still resolve from the system PATH.
      setup_bad_mv() {
        mock.setup
        mock.create_failing "mv"
        mock.activate
      }
      cleanup_bad_mv() { mock.cleanup; }
      Before 'setup_bad_mv'
      After  'cleanup_bad_mv'

      It "fails IO on the empty-aggregate path when mv cannot write"
        # No source SARIF: the empty-aggregate jq init runs, then mv fails.
        merge_empty_bad_mv() {
          local ws
          ws="$(mktemp -d)"
          mkdir -p "$ws/brik-artifacts"
          findings.merge_pipeline "$ws"
        }
        When call merge_empty_bad_mv
        The status should equal 6
        The stderr should include "cannot write"
      End

      It "fails IO on the non-empty path when mv cannot write"
        # A real stage SARIF makes the jq -s merge branch run before mv.
        merge_nonempty_bad_mv() {
          local ws
          ws="$(mktemp -d)"
          mkdir -p "$ws/brik-artifacts/sast"
          printf '%s\n' '{"version":"2.1.0","runs":[{"tool":{"driver":{"name":"semgrep"}},"results":[]}]}' \
            > "$ws/brik-artifacts/sast/findings.sarif"
          findings.merge_pipeline "$ws"
        }
        When call merge_nonempty_bad_mv
        The status should equal 6
        The stderr should include "cannot write"
      End
    End
  End
End

#shellcheck shell=bash disable=SC2148,SC2317,SC2329

Describe "transverse/findings.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/pipeline/report.sh"
  Include "$BRIK_HOME/lib/transverse/sarif.sh"
  Include "$BRIK_HOME/lib/transverse/findings.sh"

  FIX="${BRIK_HOME}/spec/fixtures/sarif"

  setup_env() {
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"
    export BRIK_WORKSPACE
    BRIK_WORKSPACE="$(mktemp -d)"
    export BRIK_RUN_ID="findings-spec"
    report.init >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -rf "$BRIK_LOG_DIR" "$BRIK_WORKSPACE"
    unset BRIK_RUN_ID
  }
  Before 'setup_env'
  After 'cleanup_env'

  read_business() {
    local stage="$1" key="$2"
    jq -c --arg s "$stage" --arg k "$key" \
      '.stages[] | select(.name == $s) | .business[$k] // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }

  Describe "API surface"
    It "declares findings.from_sarif"
      When call declare -f findings.from_sarif
      The status should be success
      The output should not be blank
    End

    It "declares findings.from_json"
      When call declare -f findings.from_json
      The status should be success
      The output should not be blank
    End

    It "declares findings.apply_policy"
      When call declare -f findings.apply_policy
      The status should be success
      The output should not be blank
    End

    It "declares findings.aggregate"
      When call declare -f findings.aggregate
      The status should be success
      The output should not be blank
    End

    It "declares findings.expiring_soon"
      When call declare -f findings.expiring_soon
      The status should be success
      The output should not be blank
    End

    It "declares findings.merge_pipeline"
      When call declare -f findings.merge_pipeline
      The status should be success
      The output should not be blank
    End
  End

  Describe "findings.from_sarif"
    It "rejects missing arguments"
      When call findings.from_sarif
      The status should equal 2
      The error should include "missing arguments"
    End

    It "rejects an empty stage name"
      When call findings.from_sarif "" "$FIX/semgrep.sarif"
      The status should equal 2
      The error should include "stage must not be empty"
    End

    It "rejects a nonexistent SARIF file"
      When call findings.from_sarif "sast" "/nonexistent/file.sarif"
      The status should equal 6
      The error should include "not found"
    End

    It "rejects an invalid SARIF document"
      bad_sarif() {
        local tmp
        tmp="$(mktemp).sarif"
        printf '{"not": "sarif"}' > "$tmp"
        findings.from_sarif "sast" "$tmp"
        local rc=$?
        rm -f "$tmp"
        return "$rc"
      }
      When call bad_sarif
      The status should equal 7
      The error should include "invalid SARIF"
    End

    It "accepts a valid SARIF fixture"
      When call findings.from_sarif "sast" "$FIX/semgrep.sarif"
      The status should be success
    End
  End

  Describe "findings.apply_policy (P1 passthrough)"
    It "rejects missing arguments"
      When call findings.apply_policy
      The status should equal 2
      The error should include "missing arguments"
    End

    It "rejects a nonexistent input file"
      bad_input() {
        local out
        out="$(mktemp).sarif"
        findings.apply_policy "/nonexistent.sarif" "$out"
        local rc=$?
        rm -f "$out"
        return "$rc"
      }
      When call bad_input
      The status should equal 6
      The error should include "input not found"
    End

    It "writes a valid SARIF to the output path"
      pass_through() {
        local out
        out="$(mktemp).sarif"
        findings.apply_policy "$FIX/semgrep.sarif" "$out" || { rm -f "$out"; return 1; }
        sarif.is_valid "$out"
        local rc=$?
        rm -f "$out"
        return "$rc"
      }
      When call pass_through
      The status should be success
    End
  End

  Describe "findings.aggregate"
    It "rejects missing arguments"
      When call findings.aggregate
      The status should equal 2
      The error should include "missing arguments"
    End

    It "rejects an empty stage name"
      When call findings.aggregate "" "$FIX/semgrep.sarif"
      The status should equal 2
      The error should include "stage must not be empty"
    End

    It "is a silent no-op when the SARIF file does not exist"
      When call findings.aggregate "sast" "/nonexistent.sarif"
      The status should be success
    End

    It "records business.findings.total from a SARIF fixture"
      run_aggregate() {
        findings.aggregate "sast" "$FIX/semgrep.sarif" >/dev/null 2>&1
        read_business "sast" "findings" | jq -r '.total // empty'
      }
      When call run_aggregate
      The output should not be blank
    End

    It "records business.findings.by_severity with the standard buckets"
      run_aggregate() {
        findings.aggregate "sast" "$FIX/semgrep.sarif" >/dev/null 2>&1
        read_business "sast" "findings" | jq -c '.by_severity'
      }
      When call run_aggregate
      The output should include "critical"
      The output should include "high"
      The output should include "medium"
      The output should include "low"
      The output should include "info"
    End

    It "records business.findings.cwe as a JSON array"
      run_aggregate() {
        findings.aggregate "sast" "$FIX/semgrep.sarif" >/dev/null 2>&1
        read_business "sast" "findings" | jq -r '.cwe | type'
      }
      When call run_aggregate
      The output should equal "array"
    End

    It "records business.report.format as sarif"
      run_aggregate() {
        findings.aggregate "sast" "$FIX/semgrep.sarif" >/dev/null 2>&1
        read_business "sast" "report" | jq -r '.format'
      }
      When call run_aggregate
      The output should equal "sarif"
    End

    It "records business.report.path relative to BRIK_WORKSPACE when nested under it"
      run_aggregate() {
        local nested="$BRIK_WORKSPACE/brik-artifacts/sast/sast.sarif"
        mkdir -p "$(dirname "$nested")"
        cp "$FIX/semgrep.sarif" "$nested"
        findings.aggregate "sast" "$nested" >/dev/null 2>&1
        read_business "sast" "report" | jq -r '.path'
      }
      When call run_aggregate
      The output should equal "brik-artifacts/sast/sast.sarif"
    End

    It "is idempotent across repeated calls"
      run_aggregate_twice() {
        findings.aggregate "sast" "$FIX/semgrep.sarif" >/dev/null 2>&1
        findings.aggregate "sast" "$FIX/semgrep.sarif" >/dev/null 2>&1
        jq -r '[.stages[] | select(.name == "sast")] | length' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_aggregate_twice
      The output should equal "1"
    End
  End

  Describe "stub functions"
    It "findings.from_json signals not-yet-implemented (P5 scope)"
      When call findings.from_json
      The status should not be success
      The error should include "not implemented"
    End

    It "findings.expiring_soon returns 0 when no allowlist is loaded"
      When call findings.expiring_soon
      The status should be success
    End

    It "findings.merge_pipeline signals not-yet-implemented (P6 scope)"
      When call findings.merge_pipeline
      The status should not be success
      The error should include "not implemented"
    End
  End

  # ---------------------------------------------------------------------------
  # findings.apply_policy with built-in presets (chantier 20260508 P2)
  # ---------------------------------------------------------------------------
  Describe "findings.apply_policy built-in presets"
    GRYPE="${BRIK_HOME}/spec/fixtures/sarif/grype-fixstate.sarif"

    setup_policy_env() {
      OUT="$(mktemp).sarif"
      unset BRIK_QUALITY_FINDINGS_POLICY BRIK_SECURITY_SEVERITY_THRESHOLD
    }
    cleanup_policy_env() { rm -f "$OUT"; }
    Before 'setup_policy_env'
    After 'cleanup_policy_env'

    # Result post apply_policy is "failing" when its output suppressions[] is
    # absent or empty. "ignored" otherwise; brikSource on the appended entry
    # discriminates between policy.built-in.* and pre-existing tool_native.
    count_failing() {
      jq -r '[.runs[0].results[] | select(((.suppressions // []) | length) == 0)] | length' "$OUT"
    }
    count_ignored_with_source() {
      local src="$1"
      jq -r --arg s "$src" \
        '[.runs[0].results[] | (.suppressions // [])[] | select(.properties.brikSource == $s)] | length' \
        "$OUT"
    }

    Describe "pragmatic preset (default)"
      It "produces a valid SARIF document"
        apply_pragmatic() {
          export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1 || return 1
          sarif.is_valid "$OUT"
        }
        When call apply_pragmatic
        The status should be success
      End

      It "marks 2 findings as failing (critical+fixed and high+fixed)"
        run_count_failing() {
          export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          count_failing
        }
        When call run_count_failing
        The output should equal "2"
      End

      It "tags 2 findings as policy.built-in.no-upstream-fix"
        run_count() {
          export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          count_ignored_with_source "policy.built-in.no-upstream-fix"
        }
        When call run_count
        The output should equal "2"
      End

      It "tags 1 finding as policy.built-in.vendor-wont-fix"
        run_count() {
          export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          count_ignored_with_source "policy.built-in.vendor-wont-fix"
        }
        When call run_count
        The output should equal "1"
      End

      It "tags 2 findings as policy.built-in.below-severity (medium < high floor)"
        run_count() {
          export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          count_ignored_with_source "policy.built-in.below-severity"
        }
        When call run_count
        The output should equal "2"
      End

      It "preserves the pre-existing tool_native suppression untouched"
        run_count() {
          export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          count_ignored_with_source "tool_native"
        }
        When call run_count
        The output should equal "1"
      End

      It "uses the chantier preference order (severity floor before fix-state)"
        # CVE-2026-0006 (medium fixed) and CVE-2026-0007 (medium not-fixed)
        # both fall below the severity floor; pragmatic must tag them as
        # below-severity, not no-upstream-fix, so the report explains the
        # structural decision (we don't track that severity bucket).
        check_ordering() {
          export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          jq -r '
            .runs[0].results[]
            | select(.ruleId == "CVE-2026-0007")
            | .suppressions[0].properties.brikSource
          ' "$OUT"
        }
        When call check_ordering
        The output should equal "policy.built-in.below-severity"
      End

      It "applies the same preset by default (no env var set)"
        no_env() {
          unset BRIK_QUALITY_FINDINGS_POLICY
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          count_failing
        }
        When call no_env
        The output should equal "2"
      End
    End

    Describe "strict preset"
      It "fails 5 findings (everything at or above severity floor)"
        run_count() {
          export BRIK_QUALITY_FINDINGS_POLICY="strict"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          count_failing
        }
        When call run_count
        The output should equal "5"
      End

      It "still tags 2 findings as below-severity (severity check stays)"
        run_count() {
          export BRIK_QUALITY_FINDINGS_POLICY="strict"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          count_ignored_with_source "policy.built-in.below-severity"
        }
        When call run_count
        The output should equal "2"
      End

      It "does not tag any finding as no-upstream-fix or vendor-wont-fix"
        run_count() {
          export BRIK_QUALITY_FINDINGS_POLICY="strict"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          local nf vw
          nf="$(count_ignored_with_source "policy.built-in.no-upstream-fix")"
          vw="$(count_ignored_with_source "policy.built-in.vendor-wont-fix")"
          printf '%s\n' "${nf}+${vw}"
        }
        When call run_count
        The output should equal "0+0"
      End

      It "preserves the pre-existing tool_native suppression"
        run_count() {
          export BRIK_QUALITY_FINDINGS_POLICY="strict"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          count_ignored_with_source "tool_native"
        }
        When call run_count
        The output should equal "1"
      End
    End

    Describe "permissive preset"
      It "fails only 1 finding (critical with upstream fix)"
        run_count() {
          export BRIK_QUALITY_FINDINGS_POLICY="permissive"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          count_failing
        }
        When call run_count
        The output should equal "1"
      End

      It "tags exactly the critical not-fixed entry as no-upstream-fix"
        run_count() {
          export BRIK_QUALITY_FINDINGS_POLICY="permissive"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          count_ignored_with_source "policy.built-in.no-upstream-fix"
        }
        When call run_count
        The output should equal "1"
      End

      It "tags 5 findings as below-severity (effective floor is critical)"
        run_count() {
          export BRIK_QUALITY_FINDINGS_POLICY="permissive"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          count_ignored_with_source "policy.built-in.below-severity"
        }
        When call run_count
        The output should equal "5"
      End

      It "preserves the pre-existing tool_native suppression"
        run_count() {
          export BRIK_QUALITY_FINDINGS_POLICY="permissive"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          count_ignored_with_source "tool_native"
        }
        When call run_count
        The output should equal "1"
      End
    End

    Describe "severity floor override"
      It "respects BRIK_SECURITY_SEVERITY_THRESHOLD=medium under pragmatic"
        # With floor=medium, the medium entries (#5,#6) are no longer
        # below-severity; #6 falls into no-upstream-fix, #5 becomes failing.
        run_failing() {
          export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
          export BRIK_SECURITY_SEVERITY_THRESHOLD="medium"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          count_failing
        }
        When call run_failing
        # #0 crit fixed + #3 high fixed + #5 medium fixed = 3 failing
        The output should equal "3"
      End

      It "shifts no-upstream-fix to include medium when floor=medium"
        run_count() {
          export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
          export BRIK_SECURITY_SEVERITY_THRESHOLD="medium"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          count_ignored_with_source "policy.built-in.no-upstream-fix"
        }
        When call run_count
        # #1 crit not-fixed + #2 high not-fixed + #6 medium not-fixed = 3
        The output should equal "3"
      End
    End

    Describe "edge cases"
      It "appends justification text on the policy suppression entry"
        check_just() {
          export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          jq -r '
            .runs[0].results[]
            | select(.ruleId == "CVE-2026-0002")
            | .suppressions[0].justification
          ' "$OUT"
        }
        When call check_just
        The output should include "Brik policy"
      End

      It "uses kind=external on every appended suppression"
        check_kind() {
          export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          jq -r '
            [.runs[0].results[]
              | (.suppressions // [])[]
              | select((.properties.brikSource // "") | startswith("policy."))
              | .kind] | unique | .[]
          ' "$OUT"
        }
        When call check_kind
        The output should equal "external"
      End

      It "rejects an unknown preset name"
        bad_preset() {
          export BRIK_QUALITY_FINDINGS_POLICY="aggressive"
          findings.apply_policy "$GRYPE" "$OUT"
        }
        When call bad_preset
        The status should equal 7
        The error should include "preset"
      End

      It "rejects an unknown severity threshold value"
        bad_floor() {
          export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
          export BRIK_SECURITY_SEVERITY_THRESHOLD="hight"
          findings.apply_policy "$GRYPE" "$OUT"
        }
        When call bad_floor
        The status should equal 7
        The error should include "threshold"
      End

      It "tolerates a malformed CVSS string (downgrades to info, no crash)"
        bad_cvss_sarif() {
          local in
          in="$(mktemp).sarif"
          jq '.runs[0].results[0].properties["security-severity"] = "not-a-number"' \
            "$GRYPE" > "$in"
          export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
          findings.apply_policy "$in" "$OUT"
          local rc=$?
          rm -f "$in"
          return "$rc"
        }
        When call bad_cvss_sarif
        The status should be success
      End

      It "handles a SARIF with empty runs[] without crashing"
        empty_runs_sarif() {
          local in
          in="$(mktemp).sarif"
          printf '%s' '{"version":"2.1.0","runs":[]}' > "$in"
          export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
          findings.apply_policy "$in" "$OUT"
          local rc=$?
          rm -f "$in"
          return "$rc"
        }
        When call empty_runs_sarif
        The status should be success
      End
    End
  End

  # ---------------------------------------------------------------------------
  # findings.aggregate L4 v2 extensions (chantier 20260508 P2)
  # ---------------------------------------------------------------------------
  Describe "findings.aggregate L4 v2 fields"
    GRYPE="${BRIK_HOME}/spec/fixtures/sarif/grype-fixstate.sarif"

    setup_l4v2() {
      ANNOTATED="$(mktemp).sarif"
      export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
      unset BRIK_SECURITY_SEVERITY_THRESHOLD
      findings.apply_policy "$GRYPE" "$ANNOTATED" >/dev/null 2>&1
      findings.aggregate "container_scan" "$ANNOTATED" >/dev/null 2>&1
    }
    cleanup_l4v2() {
      rm -f "$ANNOTATED"
      unset BRIK_QUALITY_FINDINGS_POLICY
    }
    Before 'setup_l4v2'
    After 'cleanup_l4v2'

    read_findings() {
      jq -c '.stages[] | select(.name == "container_scan") | .business.findings' \
        "$BRIK_LOG_DIR/aggregate-report.json"
    }

    It "preserves L4 v1 total field"
      check_total() {
        read_findings | jq -r '.total'
      }
      When call check_total
      The output should equal "8"
    End

    It "preserves L4 v1 by_severity field"
      check_by_sev() {
        read_findings | jq -c '.by_severity'
      }
      When call check_by_sev
      The output should include "critical"
      The output should include "high"
      The output should include "medium"
    End

    It "exposes business.findings.failing"
      check_failing() {
        read_findings | jq -r '.failing'
      }
      When call check_failing
      The output should equal "2"
    End

    It "exposes business.findings.ignored.total"
      check_ign_total() {
        read_findings | jq -r '.ignored.total'
      }
      When call check_ign_total
      The output should equal "6"
    End

    It "exposes business.findings.ignored.by_source.no-upstream-fix"
      check_ign_src() {
        read_findings | jq -r '.ignored.by_source["policy.built-in.no-upstream-fix"]'
      }
      When call check_ign_src
      The output should equal "2"
    End

    It "exposes business.findings.ignored.by_source.vendor-wont-fix"
      check_ign_src() {
        read_findings | jq -r '.ignored.by_source["policy.built-in.vendor-wont-fix"]'
      }
      When call check_ign_src
      The output should equal "1"
    End

    It "exposes business.findings.ignored.by_source.below-severity"
      check_ign_src() {
        read_findings | jq -r '.ignored.by_source["policy.built-in.below-severity"]'
      }
      When call check_ign_src
      The output should equal "2"
    End

    It "exposes business.findings.ignored.by_source.tool_native"
      check_ign_src() {
        read_findings | jq -r '.ignored.by_source["tool_native"]'
      }
      When call check_ign_src
      The output should equal "1"
    End

    It "exposes business.findings.ignored.by_severity histogram"
      check_ign_sev() {
        read_findings | jq -c '.ignored.by_severity'
      }
      When call check_ign_sev
      The output should include "critical"
      The output should include "high"
      The output should include "medium"
    End

    It "balances total = failing + ignored.total"
      check_balance() {
        read_findings | jq -r '.total - (.failing + .ignored.total)'
      }
      When call check_balance
      The output should equal "0"
    End
  End

  # ---------------------------------------------------------------------------
  # findings.apply_policy with org policy cache (chantier 20260508 P3)
  # ---------------------------------------------------------------------------
  Describe "findings.apply_policy org policy integration"
    GRYPE="${BRIK_HOME}/spec/fixtures/sarif/grype-fixstate.sarif"

    setup_org_env() {
      OUT="$(mktemp).sarif"
      CACHE="$(mktemp).cache.json"
      export BRIK_POLICY_CACHE_PATH="$CACHE"
      export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
      unset BRIK_SECURITY_SEVERITY_THRESHOLD
    }
    cleanup_org_env() {
      rm -f "$OUT" "$CACHE"
      unset BRIK_POLICY_CACHE_PATH BRIK_QUALITY_FINDINGS_POLICY
    }
    Before 'setup_org_env'
    After 'cleanup_org_env'

    count_with_source() {
      jq -r --arg s "$1" \
        '[.runs[0].results[] | (.suppressions // [])[] | select(.properties.brikSource == $s)] | length' \
        "$OUT"
    }

    Describe "with a CVE allowlist"
      It "tags matching findings as policy.org.cve-allowlist"
        # CVE-2026-0001 is critical+fixed; without org policy it would fail.
        # The allowlist makes it ignored as policy.org.cve-allowlist.
        run_cve_allow() {
          printf '%s' '{
            "preset_override": null,
            "cve_allowlist": ["CVE-2026-0001"],
            "cve_entries": [{"id":"CVE-2026-0001","reason":"x","expires":"2099-12-31"}],
            "path_globs": [],
            "path_entries": [],
            "url": "file:///org",
            "loaded_at": "2026-05-08T15:00:00+0200"
          }' > "$CACHE"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          count_with_source "policy.org.cve-allowlist"
        }
        When call run_cve_allow
        The output should equal "1"
      End

      It "still applies built-in classification to other findings"
        run_mix() {
          printf '%s' '{
            "preset_override": null,
            "cve_allowlist": ["CVE-2026-0001"],
            "cve_entries": [{"id":"CVE-2026-0001","reason":"x","expires":"2099-12-31"}],
            "path_globs": [],
            "path_entries": [],
            "url": "file:///org",
            "loaded_at": "2026-05-08T15:00:00+0200"
          }' > "$CACHE"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          # Pragmatic still tags below-severity entries; CVE-2026-0006/0007 are medium.
          count_with_source "policy.built-in.below-severity"
        }
        When call run_mix
        The output should equal "2"
      End

      It "org cve-allowlist outranks built-in classification (no double tag)"
        run_org_priority() {
          # CVE-2026-0007 is medium not-fixed; without org it would tag
          # built-in below-severity (severity floor wins over fix-state in
          # pragmatic). With the CVE in the allowlist, the org tag must win
          # and below-severity must NOT be appended for that finding.
          printf '%s' '{
            "preset_override": null,
            "cve_allowlist": ["CVE-2026-0007"],
            "cve_entries": [{"id":"CVE-2026-0007","reason":"x","expires":"2099-12-31"}],
            "path_globs": [],
            "path_entries": [],
            "url": "file:///org",
            "loaded_at": "2026-05-08T15:00:00+0200"
          }' > "$CACHE"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          jq -r '
            .runs[0].results[]
            | select(.ruleId == "CVE-2026-0007")
            | (.suppressions // []) | map(.properties.brikSource) | sort | join(",")
          ' "$OUT"
        }
        When call run_org_priority
        The output should equal "policy.org.cve-allowlist"
      End
    End

    Describe "with a path allowlist"
      It "tags matching URIs as policy.org.path-allowlist"
        run_path_allow() {
          # The fixture's CVE-2026-0001 URI is "pkg:deb/python3.14"; we use
          # a glob that matches it. The compiled cache uses ^...$ regex.
          printf '%s' '{
            "preset_override": null,
            "cve_allowlist": [],
            "cve_entries": [],
            "path_globs": [
              {"glob":"pkg:deb/**","regex":"^pkg:deb/.*$","expires":"2099-12-31"}
            ],
            "path_entries": [{"glob":"pkg:deb/**","reason":"vendor pkgs","expires":"2099-12-31"}],
            "url": "file:///org",
            "loaded_at": "2026-05-08T15:00:00+0200"
          }' > "$CACHE"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          # 5 grype results have pkg:deb/* URIs (#0-#4 + #7 already pre-suppressed).
          # Pre-suppressed (#7) is respected unchanged. Among the rest #0..#4
          # match pkg:deb -> 5 results, but our path allowlist only annotates
          # findings that don't already carry suppressions. So 5 fresh
          # annotations.
          count_with_source "policy.org.path-allowlist"
        }
        When call run_path_allow
        The output should equal "5"
      End
    End

    Describe "with a preset override"
      It "uses the org preset_override instead of the project preset"
        run_override() {
          # Project sets pragmatic but the org file overrides to strict;
          # under strict, no fix-state ignore happens, so #1 (critical not-fixed)
          # becomes failing instead of ignored.
          printf '%s' '{
            "preset_override": "strict",
            "cve_allowlist": [],
            "cve_entries": [],
            "path_globs": [],
            "path_entries": [],
            "url": "file:///org",
            "loaded_at": "2026-05-08T15:00:00+0200"
          }' > "$CACHE"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          # Strict failing count = 5 (CVE-2026-0001..0005), regardless of
          # fix-state.
          jq -r '[.runs[0].results[] | select(((.suppressions // []) | length) == 0)] | length' \
            "$OUT"
        }
        When call run_override
        The output should equal "5"
      End

      It "rejects an org preset_override with an unknown value"
        bad_override() {
          printf '%s' '{
            "preset_override": "aggressive",
            "cve_allowlist": [],
            "cve_entries": [],
            "path_globs": [],
            "path_entries": [],
            "url": "file:///org",
            "loaded_at": "2026-05-08T15:00:00+0200"
          }' > "$CACHE"
          findings.apply_policy "$GRYPE" "$OUT"
        }
        When call bad_override
        The status should equal 7
        The error should include "preset"
      End
    End

    Describe "without a cache (back-compat with P2)"
      It "behaves identically to P2 when the cache path does not exist"
        run_no_cache() {
          rm -f "$CACHE"
          findings.apply_policy "$GRYPE" "$OUT" >/dev/null 2>&1
          # Pragmatic without org allowlist -> 2 failing entries, identical to
          # the P2 baseline test.
          jq -r '[.runs[0].results[] | select(((.suppressions // []) | length) == 0)] | length' \
            "$OUT"
        }
        When call run_no_cache
        The output should equal "2"
      End
    End
  End

  # ---------------------------------------------------------------------------
  # findings.process unified ingest -> policy -> aggregate (chantier 20260508 P4)
  # ---------------------------------------------------------------------------
  Describe "findings.process"
    GRYPE="${BRIK_HOME}/spec/fixtures/sarif/grype-fixstate.sarif"

    setup_proc() {
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
      export BRIK_WORKSPACE
      BRIK_WORKSPACE="$(mktemp -d)"
      export BRIK_RUN_ID="findings-process-spec"
      mkdir -p "$BRIK_WORKSPACE/brik-artifacts/container_scan"
      cp "$GRYPE" "$BRIK_WORKSPACE/brik-artifacts/container_scan/container_scan.sarif"
      export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
      unset BRIK_SECURITY_SEVERITY_THRESHOLD BRIK_POLICY_CACHE_PATH
      report.init >/dev/null 2>&1 || true
    }
    cleanup_proc() {
      rm -rf "$BRIK_LOG_DIR" "$BRIK_WORKSPACE"
      unset BRIK_RUN_ID BRIK_QUALITY_FINDINGS_POLICY
    }
    Before 'setup_proc'
    After 'cleanup_proc'

    read_business() {
      local stage="$1" key="$2"
      jq -c --arg s "$stage" --arg k "$key" \
        '.stages[] | select(.name == $s) | .business[$k] // empty' \
        "$BRIK_LOG_DIR/aggregate-report.json"
    }

    It "is declared as a public function"
      When call declare -f findings.process
      The status should be success
      The output should not be blank
    End

    It "rejects missing arguments"
      When call findings.process
      The status should equal 2
      The error should include "missing arguments"
    End

    It "rejects an empty stage name"
      When call findings.process "" "$GRYPE"
      The status should equal 2
      The error should include "stage must not be empty"
    End

    It "is a silent no-op when the tool SARIF is missing"
      When call findings.process "container_scan" "/nonexistent.sarif"
      The status should be success
    End

    It "writes brik-artifacts/<stage>/findings.sarif alongside the tool SARIF"
      run_proc() {
        findings.process "container_scan" \
          "$BRIK_WORKSPACE/brik-artifacts/container_scan/container_scan.sarif" >/dev/null 2>&1
        test -f "$BRIK_WORKSPACE/brik-artifacts/container_scan/findings.sarif"
      }
      When call run_proc
      The status should be success
    End

    It "preserves the tool SARIF unchanged"
      run_proc() {
        local in="$BRIK_WORKSPACE/brik-artifacts/container_scan/container_scan.sarif"
        local before; before="$(jq -S . "$in")"
        findings.process "container_scan" "$in" >/dev/null 2>&1
        local after; after="$(jq -S . "$in")"
        [[ "$before" == "$after" ]]
      }
      When call run_proc
      The status should be success
    End

    It "produces a findings.sarif annotated with policy.built-in.* suppressions"
      run_proc() {
        findings.process "container_scan" \
          "$BRIK_WORKSPACE/brik-artifacts/container_scan/container_scan.sarif" >/dev/null 2>&1
        jq -r '
          [.runs[0].results[]
            | (.suppressions // [])[]
            | select((.properties.brikSource // "") | startswith("policy.built-in."))]
          | length
        ' "$BRIK_WORKSPACE/brik-artifacts/container_scan/findings.sarif"
      }
      When call run_proc
      # Pragmatic on grype-fixstate: 2 no-upstream-fix + 1 vendor-wont-fix + 2 below-severity = 5 brik-tagged entries.
      The output should equal "5"
    End

    It "records L4 v2 business.findings.failing from the annotated SARIF"
      run_proc() {
        findings.process "container_scan" \
          "$BRIK_WORKSPACE/brik-artifacts/container_scan/container_scan.sarif" >/dev/null 2>&1
        read_business "container_scan" "findings" | jq -r '.failing'
      }
      When call run_proc
      # Pragmatic baseline on the fixture: 2 failing.
      The output should equal "2"
    End

    It "records L4 v2 business.findings.ignored.by_source from the annotated SARIF"
      run_proc() {
        findings.process "container_scan" \
          "$BRIK_WORKSPACE/brik-artifacts/container_scan/container_scan.sarif" >/dev/null 2>&1
        read_business "container_scan" "findings" \
          | jq -r '.ignored.by_source["policy.built-in.no-upstream-fix"]'
      }
      When call run_proc
      The output should equal "2"
    End

    It "falls back to aggregate-only when the tool SARIF is structurally invalid"
      run_proc_bad_sarif() {
        local in
        in="$BRIK_WORKSPACE/brik-artifacts/container_scan/container_scan.sarif"
        printf '{"not":"sarif"}' > "$in"
        findings.process "container_scan" "$in"
        local rc=$?
        # No findings.sarif should be created on the policy-skipped path.
        local out_sarif="$BRIK_WORKSPACE/brik-artifacts/container_scan/findings.sarif"
        if [[ -f "$out_sarif" ]]; then
          rc=99
        fi
        return "$rc"
      }
      When call run_proc_bad_sarif
      The status should be success
    End
  End

  # ---------------------------------------------------------------------------
  # findings.gate -- pass/fail decision from business.findings.failing
  # ---------------------------------------------------------------------------
  Describe "findings.gate"
    GRYPE="${BRIK_HOME}/spec/fixtures/sarif/grype-fixstate.sarif"

    setup_gate() {
      export BRIK_LOG_DIR
      BRIK_LOG_DIR="$(mktemp -d)"
      export BRIK_WORKSPACE
      BRIK_WORKSPACE="$(mktemp -d)"
      export BRIK_RUN_ID="findings-gate-spec"
      export BRIK_QUALITY_FINDINGS_POLICY="pragmatic"
      unset BRIK_SECURITY_SEVERITY_THRESHOLD BRIK_POLICY_CACHE_PATH
      report.init >/dev/null 2>&1 || true
    }
    cleanup_gate() {
      rm -rf "$BRIK_LOG_DIR" "$BRIK_WORKSPACE"
      unset BRIK_RUN_ID BRIK_QUALITY_FINDINGS_POLICY
    }
    Before 'setup_gate'
    After 'cleanup_gate'

    It "is declared as a public function"
      When call declare -f findings.gate
      The status should be success
      The output should not be blank
    End

    It "rejects missing arguments"
      When call findings.gate
      The status should equal 2
      The error should include "missing argument"
    End

    It "returns 0 when no backend report exists yet (early pipeline)"
      no_backend() {
        rm -f "$BRIK_LOG_DIR/aggregate-report.json"
        findings.gate "container_scan"
      }
      When call no_backend
      The status should be success
    End

    It "returns 0 when the stage has no business.findings recorded"
      empty_stage() {
        # Backend exists but stage entry is absent.
        findings.gate "container_scan"
      }
      When call empty_stage
      The status should be success
    End

    It "returns 0 when business.findings.failing is 0"
      gate_pass() {
        # Process the grype fixture under pragmatic: pragmatic ignores all
        # but the 2 fixed entries; we then mutate the cache to mark even
        # those as ignored. Easier: install a synthetic backend with
        # failing=0 directly.
        local sarif
        sarif="$BRIK_WORKSPACE/x.sarif"
        cp "$GRYPE" "$sarif"
        findings.process "container_scan" "$sarif" >/dev/null 2>&1
        # Override failing to 0 to simulate a fully-policy-ignored run.
        local backend="$BRIK_LOG_DIR/aggregate-report.json"
        local tmp; tmp="$(mktemp)"
        jq '
          .stages |= map(
            if .name == "container_scan" then
              .business.findings.failing = 0
            else . end
          )
        ' "$backend" > "$tmp" && mv "$tmp" "$backend"
        findings.gate "container_scan"
      }
      When call gate_pass
      The status should be success
    End

    It "returns BRIK_EXIT_CHECK_FAILED when business.findings.failing is non-zero"
      gate_fail() {
        local sarif
        sarif="$BRIK_WORKSPACE/x.sarif"
        cp "$GRYPE" "$sarif"
        findings.process "container_scan" "$sarif" >/dev/null 2>&1
        # Pragmatic on the fixture leaves 2 results failing.
        findings.gate "container_scan"
      }
      When call gate_fail
      The status should equal 10
    End
  End
End

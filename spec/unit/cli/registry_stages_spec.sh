#shellcheck shell=bash
# Contract for `brik registry stages` (Lot 4 of chantier
# 20260526_pipeline-invariants-centralization.md).
#
# Emits the structural stage list as JSON for adapter consumption:
# every entry carries id, display_name, runner_class, parallel_group,
# and needs[] derived from the manifests + runner_classes.yml.
# The Jenkins driver (brikDriver.stagesList) reads this output at
# pipeline start; the GitLab adapter relies on the same data through
# the static jobs/*.yml templates (verified by the parity specs).

Describe "brik registry stages"
  BRIK_BIN="${BRIK_HOME}/bin/brik"

  jq_missing() { ! command -v jq >/dev/null 2>&1; }

  run_stages_json() {
    "$BRIK_BIN" registry stages --format json
  }

  Describe "exit code + JSON shape"
    It "exits 0"
      When call run_stages_json
      The status should be success
      The output should be present
    End

    It "emits valid JSON"
      Skip if "jq not installed" jq_missing
      valid_json() { run_stages_json | jq empty; }
      When call valid_json
      The status should be success
    End

    It "returns 12 stage entries"
      Skip if "jq not installed" jq_missing
      count_stages() { run_stages_json | jq '. | length'; }
      When call count_stages
      The output should equal "12"
    End

    It "every entry declares the required fields (id, display_name, runner_class, parallel_group, needs)"
      Skip if "jq not installed" jq_missing
      all_have_fields() {
        run_stages_json | jq -e '
          all(.[];
              has("id") and has("display_name") and has("runner_class")
              and has("parallel_group") and has("needs"))
        '
      }
      When call all_have_fields
      The output should equal "true"
    End
  End

  Describe "field values match the manifests"
    It "promote has runner_class=deploy"
      Skip if "jq not installed" jq_missing
      promote_class() { run_stages_json | jq -r '.[] | select(.id == "promote") | .runner_class'; }
      When call promote_class
      The output should equal "deploy"
    End

    It "lint has runner_class=stack"
      Skip if "jq not installed" jq_missing
      lint_class() { run_stages_json | jq -r '.[] | select(.id == "lint") | .runner_class'; }
      When call lint_class
      The output should equal "stack"
    End

    It "lint declares parallel_group=verify (shared with sast/scan/test)"
      Skip if "jq not installed" jq_missing
      lint_group() { run_stages_json | jq -r '.[] | select(.id == "lint") | .parallel_group'; }
      When call lint_group
      The output should equal "verify"
    End

    It "sast, scan, test share the same parallel_group as lint"
      Skip if "jq not installed" jq_missing
      verify_count() {
        run_stages_json | jq '[.[] | select(.parallel_group == "verify") | .id] | length'
      }
      When call verify_count
      The output should equal "4"
    End

    It "promote.needs includes container-scan (from placement.after)"
      Skip if "jq not installed" jq_missing
      promote_needs() {
        run_stages_json | jq -e '.[] | select(.id == "promote") | .needs | index("container-scan") != null'
      }
      When call promote_needs
      The output should equal "true"
    End

    It "init.display_name carries the canonical UI label"
      Skip if "jq not installed" jq_missing
      init_display() {
        run_stages_json | jq -r '.[] | select(.id == "init") | .display_name'
      }
      When call init_display
      The output should equal "Init"
    End

    It "container-scan.display_name is human-readable (not the raw id)"
      Skip if "jq not installed" jq_missing
      cs_display() {
        run_stages_json | jq -r '.[] | select(.id == "container-scan") | .display_name'
      }
      When call cs_display
      The output should equal "Container Scan"
    End
  End

  Describe "ordering"
    It "stages are returned in topological order (init first)"
      Skip if "jq not installed" jq_missing
      first_stage() { run_stages_json | jq -r '.[0].id'; }
      When call first_stage
      The output should equal "init"
    End

    It "notify is the last stage"
      Skip if "jq not installed" jq_missing
      last_stage() { run_stages_json | jq -r '.[-1].id'; }
      When call last_stage
      The output should equal "notify"
    End
  End
End

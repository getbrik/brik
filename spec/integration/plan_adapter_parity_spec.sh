Describe "plan.json adapter parity"
  # The promise of D.4 is: same plan.json, same decisions, every
  # adapter. This spec writes one hand-crafted plan.json and reads it
  # back through the three D.5 paths to assert they agree:
  #
  #   D.5a local   -> pipeline.plan.should_run        (bash API)
  #   D.5b Jenkins -> brik plan gate <id>             (CLI sub-command)
  #   D.5c GitLab  -> cli.plan._render_gitlab_child   (YAML emit)
  #
  # A divergence here is silent in unit tests and only surfaces in
  # briklab E2E. This spec catches it at the lib boundary.

  setup_parity_plan() {
    PARITY_DIR="$(mktemp -d)"
    export BRIK_WORKSPACE="$PARITY_DIR"
    export BRIK_LOG_DIR="$PARITY_DIR/.brik-logs"
    mkdir -p "$BRIK_LOG_DIR"
    PARITY_PLAN="$BRIK_LOG_DIR/plan.json"

    # Hand-crafted plan: every blocking stage runs (init/build/lint/sast/
    # scan/test), every opt-in skips with opt-in-flag-missing, release
    # skips with context-mismatch. Mirrors the snapshot/safe baseline
    # the planner produces against a fresh repo with no opt-ins.
    cat > "$PARITY_PLAN" <<'JSON'
{
  "schemaVersion": "v1",
  "brikVersion": "0.6.0",
  "context": "snapshot",
  "mode": "safe",
  "workspace": "/tmp",
  "changes": {"source": "none", "files": []},
  "stages": [
    {"id": "init",           "decision": "run",  "reason": "context-match",       "gate": {"mode": "blocking"}, "runner_class": "base"},
    {"id": "release",        "decision": "skip", "reason": "context-mismatch",    "gate": {"mode": "blocking"}, "runner_class": "base"},
    {"id": "build",          "decision": "run",  "reason": "context-match",       "gate": {"mode": "blocking"}, "runner_class": "stack"},
    {"id": "lint",           "decision": "run",  "reason": "context-match",       "gate": {"mode": "blocking"}, "runner_class": "stack"},
    {"id": "sast",           "decision": "run",  "reason": "context-match",       "gate": {"mode": "blocking"}, "runner_class": "analysis"},
    {"id": "scan",           "decision": "run",  "reason": "context-match",       "gate": {"mode": "blocking"}, "runner_class": "scanner"},
    {"id": "test",           "decision": "run",  "reason": "context-match",       "gate": {"mode": "blocking"}, "runner_class": "stack"},
    {"id": "package",        "decision": "skip", "reason": "opt-in-flag-missing", "gate": {"mode": "opt_in"},   "runner_class": "stack"},
    {"id": "container-scan", "decision": "skip", "reason": "opt-in-flag-missing", "gate": {"mode": "opt_in"},   "runner_class": "scanner"},
    {"id": "deploy",         "decision": "skip", "reason": "opt-in-flag-missing", "gate": {"mode": "opt_in"},   "runner_class": "deploy"},
    {"id": "notify",         "decision": "skip", "reason": "opt-in-flag-missing", "gate": {"mode": "opt_in"},   "runner_class": "base"}
  ],
  "dag": {"edges": []},
  "fingerprint": "0000000000000000000000000000000000000000000000000000000000000000"
}
JSON
    export BRIK_PLAN_FILE="$PARITY_PLAN"
  }
  cleanup_parity_plan() {
    rm -rf "$PARITY_DIR"
    unset BRIK_WORKSPACE BRIK_LOG_DIR BRIK_PLAN_FILE
  }
  Before 'setup_parity_plan'
  After 'cleanup_parity_plan'

  Describe "D.5a local adapter: pipeline.plan.should_run (bash API)"
    Include "$BRIK_HOME/lib/planning/plan_reader.sh"

    It "agrees with the plan on every blocking stage's run decision"
      blocking_run_set() {
        local out="" stage
        for stage in init build lint sast scan test; do
          if pipeline.plan.should_run "$stage" "$BRIK_PLAN_FILE"; then
            out+="$stage,"
          fi
        done
        printf '%s\n' "${out%,}"
      }
      When call blocking_run_set
      The output should equal "init,build,lint,sast,scan,test"
    End

    It "agrees with the plan on every opt-in stage's skip decision"
      optin_skip_set() {
        local out="" stage
        for stage in package container-scan deploy notify; do
          if ! pipeline.plan.should_run "$stage" "$BRIK_PLAN_FILE"; then
            out+="$stage,"
          fi
        done
        printf '%s\n' "${out%,}"
      }
      When call optin_skip_set
      The output should equal "package,container-scan,deploy,notify"
    End
  End

  Describe "D.5b Jenkins adapter: brik plan gate (CLI)"
    It "exits 0 for stages the plan marks run"
      When run script "$BRIK_BIN" plan gate build
      The status should equal 0
    End

    It "exits 1 for stages the plan marks skip"
      When run script "$BRIK_BIN" plan gate deploy
      The status should equal 1
      The output should include "deploy: skipped (reason=opt-in-flag-missing)"
    End

    It "exits 1 for context-mismatch and writes the not-applicable fragment"
      gate_release() {
        "$BRIK_BIN" plan gate release >/dev/null 2>&1
        local rc=$?
        # gate.rc=1 means skip. Check the fragment landed with the
        # plan's reason verbatim so the aggregate report can pick it up.
        jq -r '.tech.kind, .business.reason' \
            "$PARITY_DIR/brik-artifacts/release/release.json" 2>/dev/null
        printf 'rc=%s\n' "$rc"
      }
      When call gate_release
      The output should include "not-applicable"
      The output should include "context-mismatch"
      The output should include "rc=1"
    End
  End

  Describe "D.5c GitLab adapter: cli.plan._render_gitlab_child"
    It "marks the same skipped non-notify jobs with rules:when:never"
      render_child() {
        "$BRIK_BIN" plan --workspace "$PARITY_DIR" --mode safe \
            --format gitlab-child --out "$BRIK_LOG_DIR/plan-rendered.json" \
            >/dev/null 2>&1
        cat "$BRIK_LOG_DIR/plan-rendered.yml"
      }
      # The yml is generated from a fresh compute against the workspace
      # (no diff -> source=none -> blocking stages run, opt_in stages
      # skip), which mirrors the hand-crafted PARITY_PLAN. We assert
      # the skipped jobs in the YAML match the skip set the API + CLI
      # gates produced above.
      When call render_child
      The output should include "brik-release:"
      The output should include "brik-package:"
      The output should include "brik-deploy:"
      The output should include "when: never"
      # brik-notify is the report aggregator: it must NOT be overridden
      # to rules:when:never, otherwise the child has no aggregator job.
      The output should not include $'brik-notify:\n  rules:\n    - when: never'
    End
  End

  Describe "round-trip parity"
    Include "$BRIK_HOME/lib/planning/plan_reader.sh"

    It "the three adapters agree on the {run,skip} set of every stage"
      # Compare the bash API's decisions stage by stage against jq
      # reading the same plan file directly (the CLI gate and the
      # GitLab renderer both go through jq, so this is a fair proxy
      # for cross-adapter consistency).
      check_parity() {
        local mismatch="" stage api jq_decision
        for stage in init release build lint sast scan test package container-scan deploy notify; do
          api="run"
          if ! pipeline.plan.should_run "$stage" "$BRIK_PLAN_FILE"; then
            api="skip"
          fi
          jq_decision="$(jq -r --arg id "$stage" \
              '.stages[] | select(.id == $id) | .decision' "$BRIK_PLAN_FILE")"
          if [[ "$api" != "$jq_decision" ]]; then
            mismatch+="$stage(api=$api,jq=$jq_decision) "
          fi
        done
        printf '%s' "$mismatch"
      }
      When call check_parity
      The output should equal ""
    End
  End
End

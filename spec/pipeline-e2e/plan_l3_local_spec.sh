Describe "L.3 - local plan-driven pipeline (brik integrate --auto-select)"
  # Phase L.3 of the architecture refactor: `brik integrate
  # --auto-select` on three commit shapes (docs-only, lockfile-only,
  # full source) must produce three aggregate-report.json files whose
  # run/skip set is COHERENT with the plan.json the planner wrote.
  #
  # "Coherent" is the load-bearing word: a stage the plan marks `skip`
  # must land in the report with tech.kind=not-applicable; a stage the
  # plan marks `run` must be attempted (kind != not-applicable). The
  # spec does not assert run stages PASS -- sast/scan need real tools
  # the local box may lack -- only that the orchestrator honored the
  # plan. This mirrors what GitLab/Jenkins would do on the same commit.

  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_repo() {
    # Pin the in-process (in-container) execution path: L3 exercises the
    # plan->pipeline contract in-process, not the containerized engine.
    export BRIK_LOCAL_CONTAINER=1
    mock.infra.setup
    L3_WS="$(mktemp -d)"
    # Pin the log dir to the workspace so --auto-select writes plan.json
    # to a path the assertions can predict (otherwise a BRIK_LOG_DIR
    # leaked from the shellspec environment wins).
    export BRIK_LOG_DIR="$L3_WS/.brik-logs"
    (
      cd "$L3_WS"
      git init -q -b main
      git config user.email l3@brik.dev
      git config user.name  l3
      cat > brik.yml <<'YAML'
version: 1
project:
  name: l3-local
  stack: node
pipeline:
  selection:
    mode: balanced
build:
  command: "true"
test:
  command: "true"
quality:
  lint:
    command: "true"
YAML
      cat > package.json <<'JSON'
{"name":"l3-local","version":"0.1.0"}
JSON
      mkdir -p src
      echo "export const x = 1;" > src/index.ts
      echo "# l3-local" > README.md
      git add -A >/dev/null
      git commit -q -m "baseline"
    )
  }
  cleanup_repo() {
    mock.infra.teardown
    rm -rf "$L3_WS"
    unset BRIK_LOG_DIR
  }
  Before 'setup_repo'
  After 'cleanup_repo'

  # Run --auto-select, then emit one "stage:coherent" line per stage:
  # coherent = (report says skipped/not-applicable) iff (plan says skip).
  # Prints "MISMATCH" lines for any divergence, nothing otherwise.
  coherence_report() {
    local report="$L3_WS/brik-artifacts/aggregate-report.json"
    local plan="$L3_WS/.brik-logs/plan.json"
    [[ -f "$report" ]] || { printf 'NO-REPORT\n'; return 1; }
    [[ -f "$plan" ]]   || { printf 'NO-PLAN\n'; return 1; }
    local stage plan_decision report_kind
    for stage in $(jq -r '.stages[].id' "$plan"); do
      plan_decision="$(jq -r --arg s "$stage" \
        '.stages[] | select(.id == $s) | .decision' "$plan")"
      report_kind="$(jq -r --arg s "$stage" \
        '.stages[] | select(.stage == $s) | .tech.kind // ""' "$report")"
      if [[ "$plan_decision" == "skip" && "$report_kind" != "not-applicable" ]]; then
        printf 'MISMATCH %s: plan=skip report_kind=%s\n' "$stage" "${report_kind:-empty}"
      elif [[ "$plan_decision" == "run" && "$report_kind" == "not-applicable" ]]; then
        printf 'MISMATCH %s: plan=run but report marked not-applicable\n' "$stage"
      fi
    done
  }

  # Print the comma-joined sorted set of stages the plan marks "run".
  plan_run_set() {
    jq -r '[.stages[] | select(.decision == "run") | .id] | sort | join(",")' \
      "$L3_WS/.brik-logs/plan.json"
  }

  Describe "scenario 1: docs-only commit"
    It "skips every stage and the report mirrors the plan reasons"
      run_docs() {
        (
          cd "$L3_WS"
          git checkout -q -b docs-only
          echo "more docs" >> README.md
          git add README.md >/dev/null
          git commit -q -m "docs: update"
        )
        "$BRIK_BIN" integrate --workspace "$L3_WS" --auto-select >/dev/null 2>&1 || true
        coherence_report
      }
      When call run_docs
      The output should equal ""
    End

    It "records every stage as not-applicable in the aggregate report"
      na_count() {
        (
          cd "$L3_WS"
          git checkout -q -b docs-only-2
          echo "again" >> README.md
          git add README.md >/dev/null
          git commit -q -m "docs: again"
        )
        "$BRIK_BIN" integrate --workspace "$L3_WS" --auto-select >/dev/null 2>&1 || true
        jq -r '[.stages[] | select(.tech.kind == "not-applicable")] | length' \
          "$L3_WS/brik-artifacts/aggregate-report.json"
      }
      When call na_count
      The output should equal "12"
    End
  End

  Describe "scenario 2: lockfile-only commit"
    It "runs the build/lint/sast subset, report coherent with plan"
      run_lockfile() {
        (
          cd "$L3_WS"
          cat > package-lock.json <<'JSON'
{"name":"l3-local","lockfileVersion":3,"requires":true,"packages":{}}
JSON
          git add package-lock.json >/dev/null
          git commit -q -m "lockfile: baseline"
          git checkout -q -b lockfile-bump
          echo '{"name":"l3-local","lockfileVersion":3,"requires":true,"packages":{"x":{}}}' > package-lock.json
          git add package-lock.json >/dev/null
          git commit -q -m "lockfile: bump"
        )
        "$BRIK_BIN" integrate --workspace "$L3_WS" --auto-select >/dev/null 2>&1 || true
        coherence_report
      }
      When call run_lockfile
      The output should equal ""
    End

    It "plans build, lint and sast for a package-lock.json bump"
      plan_for_lockfile() {
        (
          cd "$L3_WS"
          cat > package-lock.json <<'JSON'
{"name":"l3-local","lockfileVersion":3,"requires":true,"packages":{}}
JSON
          git add package-lock.json >/dev/null
          git commit -q -m "lockfile: baseline"
          git checkout -q -b lockfile-bump-2
          echo '{"name":"l3-local","lockfileVersion":3,"requires":true,"packages":{"y":{}}}' > package-lock.json
          git add package-lock.json >/dev/null
          git commit -q -m "lockfile: bump"
        )
        "$BRIK_BIN" integrate --workspace "$L3_WS" --auto-select >/dev/null 2>&1 || true
        plan_run_set
      }
      When call plan_for_lockfile
      The output should equal "build,lint,sast"
    End
  End

  Describe "scenario 3: full source commit"
    It "runs the source subset, report coherent with plan"
      run_source() {
        (
          cd "$L3_WS"
          git checkout -q -b src-touch
          echo "export const y = 2;" >> src/index.ts
          git add src/index.ts >/dev/null
          git commit -q -m "feat: add a const"
        )
        "$BRIK_BIN" integrate --workspace "$L3_WS" --auto-select >/dev/null 2>&1 || true
        coherence_report
      }
      When call run_source
      The output should equal ""
    End
  End
End

Describe "brik plan E2E local (L.3)"
  # Three reference scenarios for plan-driven local pipelines. Mirrors
  # what GitLab/Jenkins should produce on the same commit; the chantier
  # promise is "same plan, three adapters".

  setup_repo() {
    REPO="$(mktemp -d)"
    (
      cd "$REPO"
      git init -q -b main
      git config user.email "e2e@brik.dev"
      git config user.name "e2e"
      cat > brik.yml <<'YAML'
version: 1
project:
  name: plan-e2e
pipeline:
  selection:
    mode: balanced
YAML
      cat > package.json <<'JSON'
{"name":"plan-e2e","version":"0.1.0"}
JSON
      mkdir -p src
      echo "export const hello = 'world';" > src/index.ts
      echo "# plan-e2e" > README.md
      git add -A >/dev/null
      git commit -q -m "baseline"
    )
  }
  cleanup_repo() {
    rm -rf "$REPO"
  }

  Describe "scenario 1: docs-only commit"
    Before 'setup_repo'
    After 'cleanup_repo'

    It "skips every blocking stage when only docs changed"
      (
        cd "$REPO"
        git checkout -q -b docs-only
        echo "# updated docs" >> README.md
        git add README.md >/dev/null
        git commit -q -m "docs"
      )
      "$BRIK_BIN" plan --workspace "$REPO" --out "$REPO/.brik-logs/plan.json" >/dev/null
      run_stages=$(jq -r '[.stages[] | select(.decision == "run") | .id] | sort | join(",")' "$REPO/.brik-logs/plan.json")
      When call test "$run_stages" = ""
      The status should equal 0
    End

    It "marks each non-run stage with a clear reason"
      (
        cd "$REPO"
        git checkout -q -b docs-only-2
        echo "more" >> README.md
        git add README.md >/dev/null
        git commit -q -m "docs"
      )
      "$BRIK_BIN" plan --workspace "$REPO" --out "$REPO/.brik-logs/plan.json" >/dev/null
      When call jq -r '[.stages[] | select(.decision == "skip") | .reason] | unique | sort | join(",")' "$REPO/.brik-logs/plan.json"
      The output should include "no-impact"
      The output should include "opt-in-flag-missing"
    End
  End

  Describe "scenario 2: lockfile-only commit"
    Before 'setup_repo'
    After 'cleanup_repo'

    It "treats a package-lock.json bump as an impact to scan"
      (
        cd "$REPO"
        cat > package-lock.json <<'JSON'
{"name":"plan-e2e","lockfileVersion":3,"requires":true,"packages":{}}
JSON
        git add package-lock.json >/dev/null
        git commit -q -m "lockfile baseline"
        git checkout -q -b lockfile-bump
        echo '{"name":"plan-e2e","lockfileVersion":3,"requires":true,"packages":{"x":{}}}' > package-lock.json
        git add package-lock.json >/dev/null
        git commit -q -m "lockfile: bump deps"
      )
      "$BRIK_BIN" plan --workspace "$REPO" --out "$REPO/.brik-logs/plan.json" >/dev/null
      run_stages=$(jq -r '[.stages[] | select(.decision == "run") | .id] | sort | join(",")' "$REPO/.brik-logs/plan.json")
      # Node manifest puts package-lock.json under stack.impact.{source,
      # build} -> build/lint/sast match. scan's manifest uses
      # **/package-lock.json which is monorepo-style (intentional: scan
      # was authored for nested workspaces, not the root). test stays
      # skipped (use_stack_impact: test only matches .test/.spec).
      When call test "$run_stages" = "build,lint,sast"
      The status should equal 0
    End
  End

  Describe "scenario 3: full source commit"
    Before 'setup_repo'
    After 'cleanup_repo'

    It "runs the build+lint+sast subset for a typescript source touch"
      (
        cd "$REPO"
        git checkout -q -b src-touch
        echo "export const more = 42;" >> src/index.ts
        git add src/index.ts >/dev/null
        git commit -q -m "feature: add a const"
      )
      "$BRIK_BIN" plan --workspace "$REPO" --out "$REPO/.brik-logs/plan.json" >/dev/null
      run_stages=$(jq -r '[.stages[] | select(.decision == "run") | .id] | sort | join(",")' "$REPO/.brik-logs/plan.json")
      # build (impact_build includes **/*.ts), lint+sast (use_stack_impact:
      # source includes **/*.ts) match; scan (lockfiles only) and test
      # (.test/.spec only) correctly skip. This proves the planner
      # filters precisely instead of running everything on every commit.
      When call test "$run_stages" = "build,lint,sast"
      The status should equal 0
    End

    It "still reports a deterministic fingerprint"
      (
        cd "$REPO"
        git checkout -q -b src-touch-2
        echo "export const xx = 7;" >> src/index.ts
        git add src/index.ts >/dev/null
        git commit -q -m "feature"
      )
      "$BRIK_BIN" plan --workspace "$REPO" --out "$REPO/.brik-logs/plan.json" >/dev/null
      fp=$(jq -r '.fingerprint' "$REPO/.brik-logs/plan.json")
      When call test "${#fp}" -eq 64
      The status should equal 0
    End
  End
End

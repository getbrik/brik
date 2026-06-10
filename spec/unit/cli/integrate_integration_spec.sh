Describe "brik integrate - integration"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  # --- plan-driven pipeline (cli.integrate.run --plan / --auto-select) -------
  # Covers run.sh argument handling for --plan and --auto-select plus the
  # plan-driven block: a valid --plan path, a missing --plan path, and
  # --auto-select which runs the planner first.
  Describe "brik integrate --plan"
    Include "$BRIK_HOME/spec/support/mock_helper.sh"

    setup() {
      mock.setup
      mock.infra.setup
      mock.create_script "npm" 'echo "mock npm: $*"'
      mock.create_exit "node" 0
      mock.create_script "npx" 'echo "mock npx: $*"'
      for tool in semgrep osv-scanner gitleaks eslint prettier tsc; do
        mock.create_script "$tool" 'echo "mock ${0##*/}: $*"'
      done
      mock.activate
      WORKSPACE="$(mktemp -d)"
      printf '{"name":"cli-test","version":"1.0.0","scripts":{"build":"echo ok","test":"echo ok"}}\n' > "${WORKSPACE}/package.json"
      mkdir -p "${WORKSPACE}/node_modules"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\ntest:\n  framework: npm\n' > "${WORKSPACE}/brik.yml"
      ( cd "$WORKSPACE" && git init -q && git config user.email t@t \
          && git config user.name t && git add -A \
          && git commit -q -m baseline )
      PLAN_FILE="${WORKSPACE}/computed-plan.json"
      "$BRIK_BIN" plan --workspace "$WORKSPACE" --mode safe --out "$PLAN_FILE" >/dev/null 2>&1
    }
    cleanup() {
      mock.cleanup
      mock.infra.teardown
      rm -rf "$WORKSPACE"
    }
    Before 'setup'
    After 'cleanup'

    It "runs the pipeline against an existing plan file"
      When run script "$BRIK_BIN" integrate --workspace "$WORKSPACE" --plan "$PLAN_FILE"
      The status should be success
      The stdout should include "Pipeline Summary"
      The stderr should be present
    End

    It "errors when the --plan file does not exist"
      When run script "$BRIK_BIN" integrate --workspace "$WORKSPACE" --plan "$WORKSPACE/missing-plan.json"
      The status should equal 2
      The stderr should include "plan file not found"
    End

    It "errors when --plan has no argument"
      When run script "$BRIK_BIN" integrate --workspace "$WORKSPACE" --plan
      The status should equal 2
      The stderr should be present
    End
  End

  Describe "brik integrate --auto-select"
    Include "$BRIK_HOME/spec/support/mock_helper.sh"

    setup() {
      mock.setup
      mock.infra.setup
      mock.create_script "npm" 'echo "mock npm: $*"'
      mock.create_exit "node" 0
      mock.create_script "npx" 'echo "mock npx: $*"'
      for tool in semgrep osv-scanner gitleaks eslint prettier tsc; do
        mock.create_script "$tool" 'echo "mock ${0##*/}: $*"'
      done
      mock.activate
      WORKSPACE="$(mktemp -d)"
      printf '{"name":"cli-test","version":"1.0.0","scripts":{"build":"echo ok","test":"echo ok"}}\n' > "${WORKSPACE}/package.json"
      mkdir -p "${WORKSPACE}/node_modules"
      printf 'version: 1\nproject:\n  name: cli-test\n  stack: node\ntest:\n  framework: npm\n' > "${WORKSPACE}/brik.yml"
      ( cd "$WORKSPACE" && git init -q && git config user.email t@t \
          && git config user.name t && git add -A \
          && git commit -q -m baseline )
      # Pin BRIK_LOG_DIR under the workspace so --auto-select writes the
      # generated plan.json to a deterministic, asserted location.
      export BRIK_LOG_DIR="${WORKSPACE}/.brik-logs"
    }
    cleanup() {
      mock.cleanup
      mock.infra.teardown
      rm -rf "$WORKSPACE"
      unset BRIK_LOG_DIR
    }
    Before 'setup'
    After 'cleanup'

    It "runs the planner first then executes the pipeline"
      When run script "$BRIK_BIN" integrate --workspace "$WORKSPACE" --auto-select
      The status should be success
      The stdout should include "Pipeline Summary"
      The stderr should be present
      The path "$WORKSPACE/.brik-logs/plan.json" should be file
    End

    It "passes opt-in flags through to the planner"
      When run script "$BRIK_BIN" integrate --workspace "$WORKSPACE" --auto-select --with-deploy
      The status should be success
      The stdout should be present
      The stderr should be present
    End

    It "refuses to run the pipeline when the auto-select planner fails"
      # A workspace plan_writer stub that returns non-zero makes
      # cli.plan.run fail, so cli.integrate.run aborts before setup.
      mkdir -p "$WORKSPACE/.brik/lib/planning"
      {
        printf '#!/usr/bin/env bash\n'
        printf '_BRIK_MODULE_PLANNING_PLAN_WRITER_LOADED=1\n'
        printf 'plan_writer.write() { return 1; }\n'
      } > "$WORKSPACE/.brik/lib/planning/plan_writer.sh"
      When run script "$BRIK_BIN" integrate --workspace "$WORKSPACE" --auto-select
      The status should equal 1
      The stderr should include "auto-select planner failed"
    End
  End

End

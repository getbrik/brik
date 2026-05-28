Describe "stages.init env publishing"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/pipeline/report.sh"
  Include "$BRIK_HOME/lib/pipeline/pipeline-env.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/stages/init.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_env() {
    export BRIK_CONFIG_DIR
    BRIK_CONFIG_DIR="$(mktemp -d)"
    export BRIK_CONFIG_FILE="$BRIK_CONFIG_DIR/brik.yml"
    printf 'version: 1\nproject:\n  name: test-project\n  stack: node\n' > "$BRIK_CONFIG_FILE"
    mock.workspace.setup
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"
    export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
    export BRIK_PLATFORM="gitlab"
    export BRIK_LOG_LEVEL="info"
    export BRIK_RUN_ID="init-spec-fixture"
    unset GITLAB_USER_EMAIL GITLAB_USER_NAME CHANGE_AUTHOR_EMAIL CHANGE_AUTHOR_DISPLAY_NAME
    config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    report.init >/dev/null 2>&1 || true
    pipeline.env.init >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -rf "$BRIK_CONFIG_DIR" "$BRIK_LOG_DIR"
    mock.workspace.teardown
    unset BRIK_RUN_ID BRIK_PIPELINE_ENV BRIK_CONFIG_DIR 2>/dev/null || true
  }
  Before 'setup_env'
  After 'cleanup_env'

  # ---------------------------------------------------------------------------
  # Cross-stage env publishing via report.record env (chantier env-channels).
  # init writes its dotenv keys through the env section of the report backend;
  # the post-stage projection hook mirrors them into BRIK_PIPELINE_ENV.
  # ---------------------------------------------------------------------------
  Describe "env section publishing"
    read_init_env() {
      local key="$1"
      jq -r --arg k "$key" \
        '.stages[] | select(.stage == "init") | .env[$k] // empty' \
        "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
    }

    It "records git identity into report.env"
      run_init_records_env_identity() {
        local ctx
        ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
        stages.init "$ctx" >/dev/null 2>&1 || return $?
        printf '%s|%s' \
          "$(read_init_env BRIK_GIT_USER_EMAIL)" \
          "$(read_init_env BRIK_GIT_USER_NAME)"
      }
      When call run_init_records_env_identity
      The output should equal "brik-ci@brik.local|Brik CI"
    End

    It "records every dotenv key into report.env"
      run_init_records_all_env_keys() {
        local ctx
        ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
        stages.init "$ctx" >/dev/null 2>&1 || return $?
        jq -r '.stages[] | select(.stage == "init") | .env | keys | sort | join(",")' \
          "$BRIK_LOG_DIR/aggregate-report.json"
      }
      When call run_init_records_all_env_keys
      # Lot 3 of chantier 20260526 added 5 runner-image keys (BRIK_IMG_*)
      # to expose the runner_classes.yml mapping as CI variables for
      # downstream GitLab jobs' image: directives. Pushes the per-job
      # dotenv past GitLab's default 20-variable propagation limit;
      # briklab raises the PlanLimit to 50 via
      # briklab/scripts/lib/setup/gitlab.sh::configure_dotenv_limit.
      # Adopters consuming Brik with a stock GitLab must apply the same
      # bump (documented in chantier 20260526).
      The output should equal "BRIK_BUILD_STACK,BRIK_BUILD_STACK_VERSION,BRIK_CI_IMAGE,BRIK_DEPLOY_ENABLED,BRIK_GIT_USER_EMAIL,BRIK_GIT_USER_NAME,BRIK_IMG_ANALYSIS,BRIK_IMG_BASE,BRIK_IMG_DEPLOY,BRIK_IMG_SCANNER,BRIK_IMG_STACK,BRIK_IS_CANDIDATE,BRIK_PACKAGE_ENABLED,BRIK_PROJECT_NAME,BRIK_PROJECT_VERSION,BRIK_RELEASE_PROFILE,BRIK_TEST_COVERAGE_DIR,BRIK_TEST_COVERAGE_FORMAT,BRIK_TEST_JUNIT_PATH,BRIK_TEST_REPORTS_ENABLED"
    End

    It "no longer creates brik-init.env"
      run_init_no_dotenv() {
        local ctx
        ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
        stages.init "$ctx" >/dev/null 2>&1 || return $?
        if [[ -f "${BRIK_WORKSPACE}/brik-init.env" ]]; then
          printf 'present\n'
        else
          printf 'absent\n'
        fi
      }
      When call run_init_no_dotenv
      The output should equal "absent"
    End

    It "projects every recorded env key into pipeline.env via the post-stage hook"
      run_init_projects_all_keys() {
        local ctx
        ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
        stages.init "$ctx" >/dev/null 2>&1 || return $?
        _stage.run._project_env "init" >/dev/null 2>&1 || true
        wc -l < "$BRIK_PIPELINE_ENV" | tr -d ' '
      }
      When call run_init_projects_all_keys
      # 15 legacy + 5 runner-image keys (BRIK_IMG_BASE/STACK/ANALYSIS/SCANNER/DEPLOY)
      # added by Lot 3 of chantier 20260526.
      The output should equal "20"
    End
  End

  Describe "deprecation warning for legacy *.enabled=false keys"
    # Only quality.lint.enabled is exercised here: it is the single key the
    # config schema declares. The runtime also reads .security.sast.enabled,
    # .security.scan.enabled and .security.container_scan.enabled, but the
    # schema does not declare them, so brik validate rejects any brik.yml
    # that tries to set them. The warning helper still checks all four keys
    # defensively in case a future schema iteration accepts them.
    It "logs a deprecation warning when quality.lint.enabled=false is present"
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
quality:
  lint:
    enabled: false
YAML
      run_init_legacy_lint() {
        config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
        local ctx
        ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
        stages.init "$ctx" >/dev/null
      }
      When call run_init_legacy_lint
      The error should include "quality.lint.enabled"
      The error should include "deprecated"
    End

    It "does not warn when no legacy enabled key is present"
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
YAML
      run_init_clean() {
        config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
        local ctx
        ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
        stages.init "$ctx" 2>&1 >/dev/null | grep -c "deprecated" || true
      }
      When call run_init_clean
      The output should equal "0"
    End

    It "does not warn when the key is set to true (the default)"
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
quality:
  lint:
    enabled: true
YAML
      run_init_explicit_true() {
        config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
        local ctx
        ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
        stages.init "$ctx" 2>&1 >/dev/null | grep -c "deprecated" || true
      }
      When call run_init_explicit_true
      The output should equal "0"
    End
  End
End

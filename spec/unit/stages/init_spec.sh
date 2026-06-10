Describe "stages.init"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/pipeline/report.sh"
  Include "$BRIK_HOME/lib/pipeline/pipeline-env.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/transverse/infra.sh"
  Include "$BRIK_HOME/lib/stages/init.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_env() {
    # jv detects YAML by file extension, so the fixture must live in
    # a *.yml file rather than a bare mktemp tempfile.
    export BRIK_CONFIG_DIR
    BRIK_CONFIG_DIR="$(mktemp -d)"
    export BRIK_CONFIG_FILE="$BRIK_CONFIG_DIR/brik.yml"
    printf 'version: 1\nproject:\n  name: test-project\n  stack: node\n' > "$BRIK_CONFIG_FILE"
    mock.workspace.setup
    mock.infra.setup
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
    mock.infra.teardown
    unset BRIK_RUN_ID BRIK_PIPELINE_ENV BRIK_CONFIG_DIR 2>/dev/null || true
  }

  # Helper for the schema-validation test below: skip if jv is unavailable.
  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  read_init_stack() {
    jq -r '.stages[] | select(.stage == "init") | .tech.stack // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }

  read_init_tech() {
    local key="$1"
    jq -r --arg k "$key" \
      '.stages[] | select(.stage == "init") | .tech[$k] // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }

  read_init_business() {
    local key="$1"
    jq -r --arg k "$key" \
      '.stages[] | select(.stage == "init") | .business[$k] // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }

  read_init_business_path() {
    local path="$1"
    jq -r ".stages[] | select(.stage == \"init\") | .business${path} // empty" \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }
  Before 'setup_env'
  After 'cleanup_env'

  It "is callable as a function"
    callable_check() { declare -f stages.init >/dev/null; }
    When call callable_check
    The status should be success
  End

  It "returns 0 on success with valid config"
    run_init() {
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1
    }
    When call run_init
    The status should be success
  End

  It "records init.tech.stack in the pipeline report"
    run_init_check() {
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      read_init_stack
    }
    When call run_init_check
    The output should equal "node"
  End

  It "records init.tech.stack_version from .project.stack_version"
    run_init_stack_version() {
      printf 'version: 1\nproject:\n  name: t\n  stack: node\n  stack_version: "20"\n' > "$BRIK_CONFIG_FILE"
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      read_init_tech "stack_version"
    }
    When call run_init_stack_version
    The output should equal "20"
  End

  It "records init.tech.config_file with the active config path"
    run_init_config_file() {
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      read_init_tech "config_file"
    }
    When call run_init_config_file
    The output should equal "$BRIK_CONFIG_FILE"
  End

  It "records init.tech.config_valid as a JSON boolean true"
    run_init_config_valid() {
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      jq -c '.stages[] | select(.stage == "init") | .tech.config_valid' \
        "$BRIK_LOG_DIR/aggregate-report.json"
    }
    When call run_init_config_valid
    The output should equal "true"
  End

  It "records init.tech.prereqs_present with yq and jq booleans"
    run_init_prereqs() {
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      jq -c '.stages[] | select(.stage == "init") | .tech.prereqs_present | {yq, jq}' \
        "$BRIK_LOG_DIR/aggregate-report.json"
    }
    When call run_init_prereqs
    The output should equal '{"yq":true,"jq":true}'
  End

  # The infrastructure referential is mandatory: init validates it eagerly
  # and records its fingerprint so the run's evidence pins the environment
  # declaration it executed against.
  It "fails closed when no referential is configured"
    run_init_no_infra() {
      unset BRIK_INFRA_DIR BRIK_INFRA_REPO
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null
    }
    When call run_init_no_infra
    The status should equal "$BRIK_EXIT_INVALID_ENV"
    The stderr should include "no infrastructure referential configured"
  End

  It "fails closed on an invalid referential instance"
    run_init_bad_infra() {
      printf 'apiVersion: wrong/v0\nkind: Referential\nprofile: p-lab\n' \
        > "$BRIK_INFRA_DIR/referential.yml"
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null
    }
    When call run_init_bad_infra
    The status should equal "$BRIK_EXIT_CONFIG_ERROR"
    The stderr should include "unexpected apiVersion"
  End

  It "records init.tech.infra_fingerprint for the validated instance"
    run_init_infra_fp() {
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      read_init_tech "infra_fingerprint"
    }
    When call run_init_infra_fp
    The output should equal "$(infra.fingerprint "$BRIK_INFRA_DIR")"
  End
End

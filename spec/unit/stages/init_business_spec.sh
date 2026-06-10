Describe "stages.init business section"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/pipeline/report.sh"
  Include "$BRIK_HOME/lib/pipeline/pipeline-env.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/transverse/infra.sh"
  Include "$BRIK_HOME/lib/stages/init.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_env() {
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

  jv_missing() { ! command -v jv >/dev/null 2>&1; }

  read_init_stack() {
    jq -r '.stages[] | select(.stage == "init") | .tech.stack // empty' \
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

  It "records init.business.project_name from .project.name"
    run_init_project_name() {
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      read_init_business "project_name"
    }
    When call run_init_project_name
    The output should equal "test-project"
  End

  It "records init.business.platform from BRIK_PLATFORM"
    run_init_business_platform() {
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      read_init_business "platform"
    }
    When call run_init_business_platform
    The output should equal "gitlab"
  End

  It "records init.business.commit as a nested object from BRIK_COMMIT_*"
    run_init_commit() {
      export BRIK_COMMIT_SHA="abcdef0123456789abcdef0123456789abcdef01"
      export BRIK_COMMIT_SHORT_SHA="abcdef01"
      export BRIK_COMMIT_REF="main"
      export BRIK_COMMIT_BRANCH="main"
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      jq -c '.stages[] | select(.stage == "init") | .business.commit' \
        "$BRIK_LOG_DIR/aggregate-report.json"
    }
    When call run_init_commit
    The output should equal '{"sha":"abcdef0123456789abcdef0123456789abcdef01","short_sha":"abcdef01","ref":"main","branch":"main"}'
  End

  It "records init.business.commit.author from BRIK_COMMIT_AUTHOR"
    run_init_commit_author() {
      export BRIK_COMMIT_SHA="abc"
      export BRIK_COMMIT_AUTHOR="Carol Tester"
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      read_init_business_path '.commit.author'
    }
    When call run_init_commit_author
    The output should equal "Carol Tester"
  End

  It "records init.business.commit.author_email from BRIK_COMMIT_AUTHOR_EMAIL"
    run_init_commit_author_email() {
      export BRIK_COMMIT_SHA="abc"
      export BRIK_COMMIT_AUTHOR_EMAIL="carol@example.com"
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      read_init_business_path '.commit.author_email'
    }
    When call run_init_commit_author_email
    The output should equal "carol@example.com"
  End

  It "records init.business.commit.timestamp from BRIK_COMMIT_TIMESTAMP"
    run_init_commit_timestamp() {
      export BRIK_COMMIT_SHA="abc"
      export BRIK_COMMIT_TIMESTAMP="2026-05-04T09:15:30+02:00"
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      read_init_business_path '.commit.timestamp'
    }
    When call run_init_commit_timestamp
    The output should equal "2026-05-04T09:15:30+02:00"
  End

  It "records init.business.commit.message_subject from BRIK_COMMIT_MESSAGE_SUBJECT"
    run_init_commit_subject() {
      export BRIK_COMMIT_SHA="abc"
      export BRIK_COMMIT_MESSAGE_SUBJECT="fix: regression in detector"
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      read_init_business_path '.commit.message_subject'
    }
    When call run_init_commit_subject
    The output should equal "fix: regression in detector"
  End

  It "omits init.business.commit.author when BRIK_COMMIT_AUTHOR is unset"
    run_init_commit_author_omitted() {
      export BRIK_COMMIT_SHA="abc"
      unset BRIK_COMMIT_AUTHOR
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      jq -c '.stages[] | select(.stage == "init") | .business.commit | has("author")' \
        "$BRIK_LOG_DIR/aggregate-report.json"
    }
    When call run_init_commit_author_omitted
    The output should equal "false"
  End

  It "records init.business.pipeline as a nested object from BRIK_PIPELINE_*"
    run_init_pipeline_ref() {
      export BRIK_PIPELINE_ID="42"
      export BRIK_PIPELINE_URL="https://gitlab.example.com/p/-/pipelines/42"
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      jq -c '.stages[] | select(.stage == "init") | .business.pipeline' \
        "$BRIK_LOG_DIR/aggregate-report.json"
    }
    When call run_init_pipeline_ref
    The output should equal '{"id":"42","url":"https://gitlab.example.com/p/-/pipelines/42"}'
  End

  It "records init.business.triggered_by from BRIK_TRIGGERED_BY"
    run_init_triggered() {
      export BRIK_TRIGGERED_BY="alice"
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      read_init_business "triggered_by"
    }
    When call run_init_triggered
    The output should equal "alice"
  End

  It "returns 7 when brik.yml is missing"
    run_init_no_config() {
      export BRIK_CONFIG_FILE="/nonexistent/brik.yml"
      local ctx
      ctx="$(mktemp)"
      stages.init "$ctx" 2>/dev/null
    }
    When call run_init_no_config
    The status should equal 7
  End

  It "logs project name"
    run_init_log() {
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx"
    }
    When call run_init_log
    The error should include "project: test-project"
  End

  It "logs platform from BRIK_PLATFORM"
    run_init_platform() {
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx"
    }
    When call run_init_platform
    The error should include "platform: gitlab"
  End

  It "auto-detects stack when config says auto"
    run_init_auto() {
      # Override config to return 'auto' for stack. Use a .yml-extensioned
      # path because stages.init now invokes jv for schema validation, and
      # jv detects format by extension.
      local orig_config="$BRIK_CONFIG_FILE"
      local tmpdir
      tmpdir="$(mktemp -d)"
      BRIK_CONFIG_FILE="$tmpdir/brik.yml"
      # Omit .project.stack to trigger auto-detect path (the schema does not
      # accept "auto" as a stack value -- absence of the field is the trigger,
      # via the default in config.get '.project.stack' 'auto').
      printf 'version: 1\nproject:\n  name: test-project\n' > "$BRIK_CONFIG_FILE"
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      # Mock stacks.detect to return 'node'
      brik.use() { :; }
      stacks.detect() { printf 'node'; return 0; }
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" 2>/dev/null
      read_init_stack
      rm -rf "$tmpdir"
      BRIK_CONFIG_FILE="$orig_config"
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    When call run_init_auto
    The output should equal "node"
  End

  It "returns 3 when yq is not available"
    run_init_no_yq() {
      # Hide yq from PATH
      local orig_path="$PATH"
      PATH="/usr/bin:/bin"
      # Ensure yq is not found
      if command -v yq >/dev/null 2>&1; then
        PATH="$orig_path"
        # yq is a builtin or in /usr/bin - skip
        return 3
      fi
      local ctx
      ctx="$(mktemp)"
      stages.init "$ctx" 2>/dev/null
      local rc=$?
      PATH="$orig_path"
      return "$rc"
    }
    When call run_init_no_yq
    The status should equal 3
  End

  It "logs init stage complete"
    run_init_complete() {
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx"
    }
    When call run_init_complete
    The error should include "init stage complete"
  End

  It "writes BRIK_GIT_USER_EMAIL from brik.yml git.user.email"
    run_init_git_yml() {
      printf 'version: 1\nproject:\n  name: t\n  stack: node\ngit:\n  user:\n    email: from-yml@example.com\n    name: From Yml\n' > "$BRIK_CONFIG_FILE"
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      _stage.run._project_env "init" >/dev/null 2>&1 || true
      grep '^BRIK_GIT_USER_EMAIL=' "$BRIK_PIPELINE_ENV" | tail -1
    }
    When call run_init_git_yml
    The output should equal "BRIK_GIT_USER_EMAIL=from-yml@example.com"
  End

  It "falls back to GITLAB_USER_EMAIL when brik.yml has no git block"
    run_init_gitlab_fallback() {
      export GITLAB_USER_EMAIL="ci-user@gitlab.example.com"
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      _stage.run._project_env "init" >/dev/null 2>&1 || true
      grep '^BRIK_GIT_USER_EMAIL=' "$BRIK_PIPELINE_ENV" | tail -1
      unset GITLAB_USER_EMAIL
    }
    When call run_init_gitlab_fallback
    The output should equal "BRIK_GIT_USER_EMAIL=ci-user@gitlab.example.com"
  End

  It "falls back to brik-ci@brik.local when nothing else is set"
    run_init_default_fallback() {
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx" >/dev/null 2>&1 || return $?
      _stage.run._project_env "init" >/dev/null 2>&1 || true
      grep '^BRIK_GIT_USER_EMAIL=' "$BRIK_PIPELINE_ENV" | tail -1
    }
    When call run_init_default_fallback
    The output should equal "BRIK_GIT_USER_EMAIL=brik-ci@brik.local"
  End

  It "returns 7 when brik.yml violates the JSON Schema"
    Skip if "jv not installed" jv_missing
    run_init_with_invalid_schema() {
      printf 'version: 99\nproject:\n  name: bogus\n  unknown_top_level: true\n' \
        > "$BRIK_CONFIG_FILE"
      local ctx
      ctx="$(context.create "init")" 2>/dev/null || ctx="$(mktemp)"
      stages.init "$ctx"
    }
    When call run_init_with_invalid_schema
    The status should equal 7
    The error should include "validation failed"
  End
End

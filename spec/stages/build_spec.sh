Describe "stages.build"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/transverse/artifact.sh"
  Include "$BRIK_HOME/lib/stages/build.sh"

  setup_env() {
    export BRIK_CONFIG_FILE
    BRIK_CONFIG_FILE="$(mktemp)"
    printf 'version: 1\nproject:\n  name: test\n  stack: node\n' > "$BRIK_CONFIG_FILE"
    export BRIK_WORKSPACE
    BRIK_WORKSPACE="$(mktemp -d)"
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"
    export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
    export BRIK_PLATFORM="gitlab"
    export BRIK_RUN_ID="build-spec-fixture"
    config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    report.init >/dev/null 2>&1 || true
  }
  cleanup_env() {
    rm -f "$BRIK_CONFIG_FILE"
    rm -rf "$BRIK_WORKSPACE" "$BRIK_LOG_DIR"
    unset BRIK_RUN_ID 2>/dev/null || true
  }

  read_build_tech() {
    local key="$1"
    jq -r --arg k "$key" \
      '.stages[] | select(.name == "build") | .tech[$k] // empty' \
      "$BRIK_LOG_DIR/pipeline-report.json" 2>/dev/null
  }
  Before 'setup_env'
  After 'cleanup_env'

  It "is callable as a function"
    callable_check() { declare -f stages.build >/dev/null; }
    When call callable_check
    The status should be success
  End

  It "records build.tech.stack from BRIK_BUILD_STACK"
    run_build_records_stack() {
      brik.use() { :; }
      stacks.node.build() { return 0; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" >/dev/null 2>&1
      read_build_tech "stack"
    }
    When call run_build_records_stack
    The output should equal "node"
  End

  It "records build.tech.tool from .build.tool"
    run_build_records_tool() {
      printf 'version: 1\nproject:\n  name: test\n  stack: node\nbuild:\n  tool: vite\n' \
        > "$BRIK_CONFIG_FILE"
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      brik.use() { :; }
      stacks.node.build() { return 0; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" >/dev/null 2>&1
      read_build_tech "tool"
    }
    When call run_build_records_tool
    The output should equal "vite"
  End

  It "records build.tech.command from .build.command when set"
    run_build_records_command() {
      printf 'version: 1\nproject:\n  name: test\n  stack: node\nbuild:\n  command: make build-prod\n' \
        > "$BRIK_CONFIG_FILE"
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" >/dev/null 2>&1
      read_build_tech "command"
    }
    When call run_build_records_command
    The output should equal "make build-prod"
  End

  It "records build.tech.command as <stack-default> when no override"
    run_build_records_default_command() {
      brik.use() { :; }
      stacks.node.build() { return 0; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" >/dev/null 2>&1
      read_build_tech "command"
    }
    When call run_build_records_default_command
    The output should equal "<stack-default>"
  End

  It "returns 0 when the stack build fn succeeds"
    run_build_success() {
      brik.use() { :; }
      stacks.node.build() { return 0; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" >/dev/null 2>&1
    }
    When call run_build_success
    The status should be success
  End

  It "returns non-zero when the stack build fn fails"
    run_build_failure() {
      brik.use() { :; }
      stacks.node.build() { return 1; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" >/dev/null 2>&1
    }
    When call run_build_failure
    The status should be failure
  End

  It "logs stack name"
    run_build_log_stack() {
      brik.use() { :; }
      stacks.node.build() { return 0; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx"
    }
    When call run_build_log_stack
    The error should include "running build (stack=node)"
  End

  It "calls config.export_build_vars to export BRIK_BUILD_STACK"
    run_build_check_export() {
      brik.use() { :; }
      stacks.node.build() { return 0; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" >/dev/null 2>&1
      printf '%s' "${BRIK_BUILD_STACK:-}"
    }
    When call run_build_check_export
    The output should equal "node"
  End

  It "runs build.command override instead of the stack module"
    run_build_override() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
build:
  command: "printf 'override-ran'"
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      brik.use() { :; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" 2>/dev/null
    }
    When call run_build_override
    The output should include "override-ran"
  End

  It "returns config error when stack module does not provide a build fn"
    run_build_missing_fn() {
      brik.use() { :; }
      unset -f stacks.node.build 2>/dev/null
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" 2>/dev/null
      local rc=$?
      printf '%s' "$rc"
    }
    When call run_build_missing_fn
    The output should equal "7"
  End

  It "returns IO_FAILURE when BRIK_WORKSPACE does not exist"
    run_build_no_workspace() {
      brik.use() { :; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      export BRIK_WORKSPACE="/nonexistent/brik-workspace-$$"
      stages.build "$ctx" 2>/dev/null
      printf '%s' "$?"
    }
    When call run_build_no_workspace
    The output should equal "6"
  End

  It "returns CONFIG_ERROR when auto-detect finds no stack"
    run_build_auto_fail() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      brik.use() { :; }
      stacks.detect() { return 1; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" 2>/dev/null
      printf '%s' "$?"
    }
    When call run_build_auto_fail
    The output should equal "7"
  End

  It "returns CONFIG_ERROR when stack module cannot be loaded"
    run_build_unsupported() {
      brik.use() {
        case "$1" in
          stacks.cobol) return 1 ;;
          *) return 0 ;;
        esac
      }
      export BRIK_BUILD_STACK="cobol"
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" 2>/dev/null
      printf '%s' "$?"
    }
    When call run_build_unsupported
    The output should equal "7"
  End

  It "forwards --tool to the stack build fn when build.tool is set"
    run_build_tool() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
build:
  tool: yarn
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      brik.use() { :; }
      local ARGS_LOG=""
      stacks.node.build() { ARGS_LOG="$*"; return 0; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" >/dev/null 2>&1
      printf '%s' "$ARGS_LOG"
    }
    When call run_build_tool
    The output should include "--tool yarn"
  End

  It "omits --tool when build.tool is auto"
    run_build_tool_auto() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: node
build:
  tool: auto
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
      brik.use() { :; }
      local ARGS_LOG=""
      stacks.node.build() { ARGS_LOG="$*"; return 0; }
      local ctx
      ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
      stages.build "$ctx" >/dev/null 2>&1
      printf '%s' "$ARGS_LOG"
    }
    When call run_build_tool_auto
    The output should not include "--tool"
  End

  Describe "with java stack"
    setup_java() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: java
YAML
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_java'

    It "loads java stack module"
      run_build_java() {
        local loaded_modules=""
        brik.use() { loaded_modules="${loaded_modules} $1"; }
        stacks.java.build() { return 0; }
        local ctx
        ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
        stages.build "$ctx" >/dev/null 2>&1
        printf '%s' "$loaded_modules"
      }
      When call run_build_java
      The output should include "stacks.java"
    End
  End

  Describe "business.artifact recording"
    It "records build.business.artifact when dist/ exists after build"
      run_build_artifact_dist() {
        mkdir -p "$BRIK_WORKSPACE/dist"
        printf 'console.log(1)\n' > "$BRIK_WORKSPACE/dist/main.js"
        brik.use() { :; }
        stacks.node.build() { return 0; }
        local ctx
        ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
        stages.build "$ctx" >/dev/null 2>&1
        jq -r '.stages[] | select(.name == "build") | .business.artifact.name // "<missing>"' \
          "$BRIK_LOG_DIR/pipeline-report.json"
      }
      When call run_build_artifact_dist
      The output should equal "dist"
    End

    It "records build.business.artifact.type as directory for dist/"
      run_build_artifact_type() {
        mkdir -p "$BRIK_WORKSPACE/dist"
        printf 'x\n' > "$BRIK_WORKSPACE/dist/file.txt"
        brik.use() { :; }
        stacks.node.build() { return 0; }
        local ctx
        ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
        stages.build "$ctx" >/dev/null 2>&1
        jq -r '.stages[] | select(.name == "build") | .business.artifact.type // "<missing>"' \
          "$BRIK_LOG_DIR/pipeline-report.json"
      }
      When call run_build_artifact_type
      The output should equal "directory"
    End

    It "records build.business.artifact.sha256 as a 64-char hex string"
      run_build_artifact_sha() {
        mkdir -p "$BRIK_WORKSPACE/dist"
        printf 'a\n' > "$BRIK_WORKSPACE/dist/main.js"
        brik.use() { :; }
        stacks.node.build() { return 0; }
        local ctx
        ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
        stages.build "$ctx" >/dev/null 2>&1
        jq -r '.stages[] | select(.name == "build") | .business.artifact.sha256 // "<missing>"' \
          "$BRIK_LOG_DIR/pipeline-report.json"
      }
      When call run_build_artifact_sha
      The output should match pattern '[a-f0-9]*'
      The length of output should equal 64
    End

    It "prefers target/ when dist/ is absent (Java convention)"
      run_build_artifact_target() {
        mkdir -p "$BRIK_WORKSPACE/target"
        printf 'binary\n' > "$BRIK_WORKSPACE/target/app.jar"
        brik.use() { :; }
        stacks.java.build() { return 0; }
        cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: test
  stack: java
YAML
        config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
        local ctx
        ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
        stages.build "$ctx" >/dev/null 2>&1
        jq -r '.stages[] | select(.name == "build") | .business.artifact.name // "<missing>"' \
          "$BRIK_LOG_DIR/pipeline-report.json"
      }
      When call run_build_artifact_target
      The output should equal "target"
    End

    It "omits build.business.artifact when no conventional dir exists"
      run_build_artifact_omit() {
        brik.use() { :; }
        stacks.node.build() { return 0; }
        local ctx
        ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
        stages.build "$ctx" >/dev/null 2>&1
        jq -r '[.stages[] | select(.name == "build") | .business.artifact // null | select(. != null)] | length' \
          "$BRIK_LOG_DIR/pipeline-report.json"
      }
      When call run_build_artifact_omit
      The output should equal "0"
    End

    It "omits build.business.artifact when stack build fn fails"
      run_build_artifact_skip_on_fail() {
        mkdir -p "$BRIK_WORKSPACE/dist"
        printf 'x\n' > "$BRIK_WORKSPACE/dist/file.txt"
        brik.use() { :; }
        stacks.node.build() { return 1; }
        local ctx
        ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
        stages.build "$ctx" >/dev/null 2>&1
        jq -r '[.stages[] | select(.name == "build") | .business.artifact // null | select(. != null)] | length' \
          "$BRIK_LOG_DIR/pipeline-report.json"
      }
      When call run_build_artifact_skip_on_fail
      The output should equal "0"
    End
  End

  Describe "tech.cache_hit recording"
    It "records build.tech.cache_hit as JSON true when BRIK_BUILD_CACHE_HIT=true"
      run_build_cache_hit_true() {
        export BRIK_BUILD_CACHE_HIT="true"
        brik.use() { :; }
        stacks.node.build() { return 0; }
        local ctx
        ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
        stages.build "$ctx" >/dev/null 2>&1
        unset BRIK_BUILD_CACHE_HIT
        jq -c '.stages[] | select(.name == "build") | .tech.cache_hit' \
          "$BRIK_LOG_DIR/pipeline-report.json"
      }
      When call run_build_cache_hit_true
      The output should equal "true"
    End

    It "records build.tech.cache_hit as JSON false when BRIK_BUILD_CACHE_HIT=false"
      run_build_cache_hit_false() {
        export BRIK_BUILD_CACHE_HIT="false"
        brik.use() { :; }
        stacks.node.build() { return 0; }
        local ctx
        ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
        stages.build "$ctx" >/dev/null 2>&1
        unset BRIK_BUILD_CACHE_HIT
        jq -c '.stages[] | select(.name == "build") | .tech.cache_hit' \
          "$BRIK_LOG_DIR/pipeline-report.json"
      }
      When call run_build_cache_hit_false
      The output should equal "false"
    End

    It "omits build.tech.cache_hit when BRIK_BUILD_CACHE_HIT is unset"
      run_build_cache_hit_omit() {
        unset BRIK_BUILD_CACHE_HIT
        brik.use() { :; }
        stacks.node.build() { return 0; }
        local ctx
        ctx="$(context.create "build")" 2>/dev/null || ctx="$(mktemp)"
        stages.build "$ctx" >/dev/null 2>&1
        jq -r '.stages[] | select(.name == "build") | .tech | has("cache_hit")' \
          "$BRIK_LOG_DIR/pipeline-report.json"
      }
      When call run_build_cache_hit_omit
      The output should equal "false"
    End
  End
End

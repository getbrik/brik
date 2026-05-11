#shellcheck shell=bash
# SC20 acceptance for the release stage trigger gating.
#
# Verifies that .release.trigger flags in brik.yml change stages.release
# behavior end-to-end:
#   - trigger block absent  -> stage runs (legacy compat)
#   - trigger.on-main=true on main branch -> stage runs without a tag
#   - trigger.on-tag=true on a feature branch without tag -> stage skipped
#
# Each scenario stubs the actual release work (git interactions) but
# lets the stage entry point itself decide whether to short-circuit.

Describe "stages.release SC20 trigger gating"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_HOME/lib/pipeline/stage.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/transverse/config.sh"
  Include "$BRIK_HOME/lib/transverse/gating.sh"
  Include "$BRIK_HOME/lib/stages/release.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  setup_rel_env() {
    export BRIK_CONFIG_FILE
    BRIK_CONFIG_FILE="$(mktemp)"
    mock.workspace.setup
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"
    export BRIK_PROJECT_DIR="$BRIK_WORKSPACE"
    export BRIK_PLATFORM="gitlab"
    export BRIK_RUN_ID="release-gating-spec"
    unset BRIK_COMMIT_TAG BRIK_COMMIT_BRANCH BRIK_TRIGGER_MANUAL BRIK_DEFAULT_BRANCH
    unset BRIK_RELEASE_TRIGGER_CONFIGURED \
          BRIK_RELEASE_TRIGGER_ON_TAG \
          BRIK_RELEASE_TRIGGER_ON_MAIN \
          BRIK_RELEASE_TRIGGER_MANUAL
    report.init >/dev/null 2>&1 || true
  }
  cleanup_rel_env() {
    rm -f "$BRIK_CONFIG_FILE"
    rm -rf "$BRIK_LOG_DIR"
    mock.workspace.teardown
    unset BRIK_RUN_ID BRIK_PLATFORM BRIK_PROJECT_DIR
    unset BRIK_RELEASE_TRIGGER_CONFIGURED \
          BRIK_RELEASE_TRIGGER_ON_TAG \
          BRIK_RELEASE_TRIGGER_ON_MAIN \
          BRIK_RELEASE_TRIGGER_MANUAL
    unset BRIK_COMMIT_TAG BRIK_COMMIT_BRANCH BRIK_TRIGGER_MANUAL BRIK_DEFAULT_BRANCH
  }
  Before 'setup_rel_env'
  After  'cleanup_rel_env'

  # Neutralize the actual release work; the gate decides whether the
  # stage even reaches it.
  _stub_release_internals() {
    brik.use() { :; }
    git.tag_exists() { return 1; }
    version.next() { printf '1.0.0'; }
  }

  read_release_status() {
    jq -r '.stages[] | select(.name == "release") | .tech.status // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json"
  }
  read_release_kind() {
    jq -r '.stages[] | select(.name == "release") | .tech.kind // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json"
  }

  Describe "trigger absent (legacy compat)"
    setup_no_trigger() {
      printf 'version: 1\nproject:\n  name: x\n  stack: node\nrelease:\n  strategy: semver\n' \
        > "$BRIK_CONFIG_FILE"
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_no_trigger'

    It "runs the release body even on a feature branch (no trigger configured)"
      do_run() {
        _stub_release_internals
        export BRIK_COMMIT_BRANCH="feat/x"
        local ctx
        ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
        stages.release "$ctx" >/dev/null 2>&1
        read_release_kind
      }
      When call do_run
      # The body proceeds; tech.kind is therefore NOT "not-applicable".
      The output should not equal "not-applicable"
    End
  End

  Describe "trigger.on-main=true on the default branch"
    setup_on_main() {
      printf 'version: 1\nproject:\n  name: x\n  stack: node\nrelease:\n  trigger:\n    on-tag: false\n    on-main: true\n  strategy: semver\n' \
        > "$BRIK_CONFIG_FILE"
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_on_main'

    It "runs the release body when BRIK_COMMIT_BRANCH=main (no tag required)"
      do_run() {
        _stub_release_internals
        export BRIK_COMMIT_BRANCH="main"
        local ctx
        ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
        stages.release "$ctx" >/dev/null 2>&1
        read_release_kind
      }
      When call do_run
      The output should not equal "not-applicable"
    End

    It "skips with tech.status=skipped + kind=not-applicable on a feature branch"
      do_skip() {
        _stub_release_internals
        export BRIK_COMMIT_BRANCH="feat/x"
        local ctx
        ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
        stages.release "$ctx" >/dev/null 2>&1
        printf '%s,%s' "$(read_release_status)" "$(read_release_kind)"
      }
      When call do_skip
      The output should equal "skipped,not-applicable"
    End
  End

  Describe "trigger.on-tag=true with a tag set"
    setup_on_tag() {
      printf 'version: 1\nproject:\n  name: x\n  stack: node\nrelease:\n  trigger:\n    on-tag: true\n    on-main: false\n  strategy: semver\n' \
        > "$BRIK_CONFIG_FILE"
      config.read "$BRIK_CONFIG_FILE" >/dev/null 2>&1 || true
    }
    Before 'setup_on_tag'

    It "runs the release body when BRIK_COMMIT_TAG is set"
      do_run() {
        _stub_release_internals
        export BRIK_COMMIT_TAG="v1.0.0"
        local ctx
        ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
        stages.release "$ctx" >/dev/null 2>&1
        read_release_kind
      }
      When call do_run
      The output should not equal "not-applicable"
    End

    It "skips on a feature branch without a tag"
      do_skip() {
        _stub_release_internals
        export BRIK_COMMIT_BRANCH="feat/x"
        local ctx
        ctx="$(context.create "release")" 2>/dev/null || ctx="$(mktemp)"
        stages.release "$ctx" >/dev/null 2>&1
        read_release_kind
      }
      When call do_skip
      The output should equal "not-applicable"
    End
  End
End

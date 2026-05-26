Describe "stages/promote.sh (Phase 9.B)"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/tools.sh"
  Include "$BRIK_PIPELINE_LIB/context.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_PIPELINE_LIB/report.sh"
  Include "$BRIK_TRANSVERSE_LIB/config.sh"
  Include "$BRIK_HOME/lib/stages/promote.sh"
  Include "$BRIK_HOME/spec/support/mock_helper.sh"

  read_status() {
    jq -r '.stages[] | select(.stage == "promote") | .tech.status // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }
  read_kind() {
    jq -r '.stages[] | select(.stage == "promote") | .tech.kind // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }
  read_business_key() {
    jq -r --arg k "$1" '.stages[] | select(.stage == "promote") | .business[$k] // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }
  read_env_key() {
    jq -r --arg k "$1" '.stages[] | select(.stage == "promote") | .env[$k] // empty' \
      "$BRIK_LOG_DIR/aggregate-report.json" 2>/dev/null
  }

  write_valid_config() {
    cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: promote-spec
  stack: node
release:
  candidate:
    docker:
      registry: candidate.example.com
      image: myteam/api
  release:
    docker:
      registry: release.example.com
      image: myteam/api
YAML
  }

  setup_promote() {
    export BRIK_CONFIG_FILE
    BRIK_CONFIG_FILE="$(mktemp)"
    CTX_FILE="$(mktemp)"
    export BRIK_LOG_DIR
    BRIK_LOG_DIR="$(mktemp -d)"
    export BRIK_RUN_ID="promote-spec-fixture"
    export BRIK_PROJECT_VERSION="1.2.3"
    # The promote stage self-skips when BRIK_COMMIT_TAG is empty
    # (gate.contexts=[release] enforcement in the legacy non-plan path).
    # Set a synthetic tag so every promote test exercises the real path
    # rather than the not-a-release-context shortcut.
    export BRIK_COMMIT_TAG="v1.2.3"
    report.init >/dev/null 2>&1 || true
    unset BRIK_DRY_RUN
  }
  cleanup_promote() {
    rm -f "$BRIK_CONFIG_FILE" "$CTX_FILE"
    rm -rf "$BRIK_LOG_DIR"
    unset BRIK_RUN_ID BRIK_PROJECT_VERSION BRIK_DRY_RUN BRIK_COMMIT_TAG
  }
  Before 'setup_promote'
  After 'cleanup_promote'

  Describe "config validation"
    It "skips gracefully when no docker promotion config is present"
      # A project with no release.{candidate,release}.docker config has
      # not opted into the 2-zone promotion model: promote is a no-op,
      # not an error -- otherwise it would break every release pipeline.
      printf 'version: 1\nproject:\n  name: t\n' > "$BRIK_CONFIG_FILE"
      invoke() {
        stages.promote "$CTX_FILE" 2>/dev/null
        local rc=$?
        printf 'rc=%s|kind=%s' "$rc" "$(read_kind)"
      }
      When call invoke
      The output should equal "rc=0|kind=not-applicable"
    End

    It "fails with config-error when release registry is missing"
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: t
release:
  candidate:
    docker:
      registry: candidate.example.com
      image: myteam/api
YAML
      invoke() {
        stages.promote "$CTX_FILE" 2>/dev/null
        local rc=$?
        printf 'rc=%s|kind=%s' "$rc" "$(read_kind)"
      }
      When call invoke
      The output should equal "rc=7|kind=config-error"
    End
  End

  Describe "dry-run"
    It "records success + four artefact keys + promoted ref without invoking docker"
      write_valid_config
      export BRIK_DRY_RUN=true
      invoke() {
        stages.promote "$CTX_FILE" >/dev/null 2>&1
        local rc=$?
        printf '%s|%s|%s|%s|%s|%s|%s' \
          "rc=$rc" \
          "status=$(read_status)" \
          "kind=$(read_kind)" \
          "cand=$(read_business_key candidate_ref)" \
          "rel=$(read_business_key release_ref)" \
          "cand_dig=$(read_business_key candidate_digest)" \
          "promoted=$(read_env_key BRIK_PROMOTED_IMAGE_REF)"
      }
      When call invoke
      The output should equal "rc=0|status=success|kind=dry-run|cand=candidate.example.com/myteam/api:1.2.3|rel=release.example.com/myteam/api:1.2.3|cand_dig=sha256:dry-run|promoted=release.example.com/myteam/api:1.2.3"
    End
  End

  Describe "docker missing (not dry-run)"
    setup_no_docker() {
      mock.setup
      # Preserve every command the stage needs (yq for config.get,
      # jq for report.record, plus the standard utils) but leave
      # docker out -- that's what we want to detect as missing.
      local cmd cmd_path
      for cmd in yq jq mktemp mkdir chmod tr rm cat printf sed grep awk wc head tail sort uniq bash sh mv cp ln stat env true false flock date file basename dirname tee diff; do
        cmd_path="$(command -v "$cmd" 2>/dev/null)" || true
        [[ -n "$cmd_path" && ! -e "${MOCK_BIN}/${cmd}" ]] && ln -s "$cmd_path" "${MOCK_BIN}/${cmd}"
      done
      mock.isolate
    }
    teardown_no_docker() {
      mock.cleanup
    }
    Before 'setup_no_docker'
    After 'teardown_no_docker'

    It "fails with kind=missing-tool when docker is not on PATH"
      write_valid_config
      invoke() {
        stages.promote "$CTX_FILE" 2>/dev/null
        local rc=$?
        printf 'rc=%s|kind=%s' "$rc" "$(read_kind)"
      }
      When call invoke
      The output should equal "rc=3|kind=missing-tool"
    End
  End

  Describe "docker happy path"
    setup_mocks() {
      mock.setup
      # Override docker to print a fixed digest line on inspect, and
      # exit 0 on every other subcommand (pull, tag, push).
      cat > "$MOCK_BIN/docker" <<'SH'
#!/usr/bin/env bash
case "$1" in
  inspect) printf 'candidate.example.com/myteam/api@sha256:abc123def\n' ;;
  *)       exit 0 ;;
esac
SH
      chmod +x "$MOCK_BIN/docker"
      mock.activate
    }
    teardown_mocks() {
      mock.cleanup
    }
    Before 'setup_mocks'
    After 'teardown_mocks'

    It "records the four artefact keys + env.BRIK_PROMOTED_IMAGE_REF + status=success"
      write_valid_config
      invoke() {
        stages.promote "$CTX_FILE" >/dev/null 2>&1
        local rc=$?
        printf '%s|%s|%s|%s|%s|%s' \
          "rc=$rc" \
          "status=$(read_status)" \
          "cand_dig=$(read_business_key candidate_digest)" \
          "rel_ref=$(read_business_key release_ref)" \
          "rel_dig=$(read_business_key release_digest)" \
          "promoted=$(read_env_key BRIK_PROMOTED_IMAGE_REF)"
      }
      When call invoke
      The output should equal "rc=0|status=success|cand_dig=sha256:abc123def|rel_ref=release.example.com/myteam/api:1.2.3|rel_dig=sha256:abc123def|promoted=release.example.com/myteam/api:1.2.3"
    End
  End

  Describe "docker pull failure"
    setup_pullfail() {
      mock.setup
      # Override docker to fail on pull, succeed on other subcommands.
      cat > "$MOCK_BIN/docker" <<'SH'
#!/usr/bin/env bash
case "$1" in
  pull) exit 1 ;;
  *)    exit 0 ;;
esac
SH
      chmod +x "$MOCK_BIN/docker"
      mock.activate
    }
    teardown_pullfail() {
      mock.cleanup
    }
    Before 'setup_pullfail'
    After 'teardown_pullfail'

    It "records kind=candidate-not-found when pull fails"
      write_valid_config
      invoke() {
        stages.promote "$CTX_FILE" 2>/dev/null
        local rc=$?
        printf 'rc=%s|kind=%s' "$rc" "$(read_kind)"
      }
      When call invoke
      The output should equal "rc=1|kind=candidate-not-found"
    End
  End
End

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

  Describe "docker registry auth (per-zone credentials)"
    setup_auth_mocks() {
      mock.setup
      DOCKER_CALLS="$(mktemp)"
      export DOCKER_CALLS
      cat > "$MOCK_BIN/docker" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOCKER_CALLS"
case "$1" in
  inspect) printf 'r@sha256:abc\n' ;;
  login)   cat >/dev/null 2>&1 || true; exit 0 ;;
  *)       exit 0 ;;
esac
SH
      chmod +x "$MOCK_BIN/docker"
      mock.activate
    }
    teardown_auth_mocks() { rm -f "$DOCKER_CALLS"; mock.cleanup; }
    Before 'setup_auth_mocks'
    After 'teardown_auth_mocks'

    It "logs in to the candidate and release registries with the configured creds"
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: t
  stack: node
release:
  candidate:
    docker:
      registry: candidate.example.com
      image: myteam/api
      username_var: CAND_USER
      password_var: CAND_PASS
  release:
    docker:
      registry: release.example.com
      image: myteam/api
      username_var: REL_USER
      password_var: REL_PASS
YAML
      invoke() {
        export CAND_USER=cu CAND_PASS=cp REL_USER=ru REL_PASS=rp
        stages.promote "$CTX_FILE" >/dev/null 2>&1
        grep -c '^login ' "$DOCKER_CALLS"
      }
      When call invoke
      The output should equal "2"
    End

    # T5c (PD3): with a referential, the candidate/release registries match
    # Registry endpoints by authority and the login credentials resolve BY
    # TARGET (pkg.registry.resolve), with no release.*.docker.*_var in brik.yml.
    Describe "via referential (T5c/PD3)"
      Include "$BRIK_TRANSVERSE_LIB/infra.sh"
      Include "$BRIK_PACKAGE_MANAGERS_LIB/_endpoint.sh"

      setup_ref() {
        INFRA_DIR="$(mktemp -d)"
        mkdir -p "$INFRA_DIR/endpoints" "$INFRA_DIR/credentials" "$INFRA_DIR/bindings"
        printf 'apiVersion: brik.dev/referential/v1\nkind: Referential\nprofile: p-lab\n' \
          > "$INFRA_DIR/referential.yml"
        cat > "$INFRA_DIR/endpoints/cand.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Registry
name: cand
url: https://candidate.example.com
tls:
  trust: system
YAML
        cat > "$INFRA_DIR/endpoints/rel.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Registry
name: rel
url: https://release.example.com
tls:
  trust: system
YAML
        cat > "$INFRA_DIR/credentials/cand-cred.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: cand-cred
method: basic
username: env://CAND_USER
password: env://CAND_PASS
YAML
        cat > "$INFRA_DIR/credentials/rel-cred.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Credential
name: rel-cred
method: basic
username: env://REL_USER
password: env://REL_PASS
YAML
        cat > "$INFRA_DIR/bindings/ci.yml" <<'YAML'
apiVersion: brik.dev/referential/v1
kind: Binding
name: ci
endpoints:
  cand: cand-cred
  rel: rel-cred
YAML
        export BRIK_INFRA_DIR="$INFRA_DIR"
      }
      cleanup_ref() { rm -rf "$INFRA_DIR"; unset BRIK_INFRA_DIR INFRA_DIR; }
      Before 'setup_ref'
      After 'cleanup_ref'

      It "logs in to both registries with credentials resolved by target"
        cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: t
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
        invoke() {
          export CAND_USER=cu CAND_PASS=cp REL_USER=ru REL_PASS=rp
          stages.promote "$CTX_FILE" >/dev/null 2>&1
          grep -q -- "--username cu" "$DOCKER_CALLS" \
            && grep -q -- "--username ru" "$DOCKER_CALLS" \
            && grep -c '^login ' "$DOCKER_CALLS"
        }
        When call invoke
        The output should equal "2"
      End
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

  Describe "channel promotion (artifacts.channels)"
    CHAN_DIGEST="sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

    # The copy primitive's own contract is channel_copy_with_referrers_spec:
    # stub it as a function (the loader guard keeps brik.use from re-sourcing
    # the module) so this unit covers the stage's dispatch and reporting.
    _BRIK_MODULE_TRANSVERSE_CHANNEL_LOADED=1
    # Same altitude for the journal: its contract is promotion_journal_spec.
    _BRIK_MODULE_TRANSVERSE_PROMOTION_JOURNAL_LOADED=1
    promotion_journal.record_promotion() {
      printf 'record_promotion %s\n' "$*" >> "${BRIK_LOG_DIR}/journal.log"
      return "${JOURNAL_RC:-0}"
    }
    channel.copy_with_referrers() {
      printf 'copy_with_referrers %s\n' "$*" >> "${BRIK_LOG_DIR}/chan.log"
      if [[ -n "${CHAN_RC:-}" && "${CHAN_RC}" != "0" ]]; then
        return "$CHAN_RC"
      fi
      printf 'registry.release/app@%s' "$CHAN_DIGEST"
    }

    write_channels_config() {
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: promote-spec
  stack: node
artifacts:
  channels:
    candidate:
      registry: registry.internal/app
    release:
      registry: registry.release/app
YAML
    }

    It "promotes through the copy primitive and exports the digest-pinned release ref"
      write_channels_config
      invoke() {
        stages.promote "$CTX_FILE" >/dev/null 2>&1
        local rc=$?
        printf 'rc=%s|kind=%s|rel=%s|promoted=%s|' \
          "$rc" "$(read_kind)" \
          "$(read_business_key release_ref)" \
          "$(read_env_key BRIK_PROMOTED_IMAGE_REF)"
        cat "${BRIK_LOG_DIR}/chan.log"
      }
      When call invoke
      The output should equal "rc=0|kind=channel-promotion|rel=registry.release/app@${CHAN_DIGEST}|promoted=registry.release/app@${CHAN_DIGEST}|copy_with_referrers 1.2.3 candidate release"
    End

    It "honors dry-run without invoking the primitive"
      write_channels_config
      export BRIK_DRY_RUN=true
      invoke() {
        stages.promote "$CTX_FILE" >/dev/null 2>&1
        local rc=$?
        printf 'rc=%s|kind=%s|called=%s' \
          "$rc" "$(read_kind)" \
          "$([[ -f "${BRIK_LOG_DIR}/chan.log" ]] && echo yes || echo no)"
      }
      When call invoke
      The output should equal "rc=0|kind=dry-run|called=no"
    End

    It "propagates the primitive's failure (immutability refusal stays a refusal)"
      write_channels_config
      invoke() {
        CHAN_RC=10
        stages.promote "$CTX_FILE" >/dev/null 2>&1
        local rc=$?
        printf 'rc=%s|status=%s|kind=%s' "$rc" "$(read_status)" "$(read_kind)"
      }
      When call invoke
      The output should equal "rc=10|status=failure|kind=channel-promotion-failed"
    End

    It "journals artifact_promoted with the pinned digest after a successful copy"
      write_channels_config
      invoke() {
        stages.promote "$CTX_FILE" >/dev/null 2>&1 || return $?
        cat "${BRIK_LOG_DIR}/journal.log"
      }
      When call invoke
      The output should equal "record_promotion --version 1.2.3 --digest ${CHAN_DIGEST} --from-channel candidate --to-channel release"
    End

    It "fails the stage when the declared journal cannot record the promotion"
      write_channels_config
      invoke() {
        JOURNAL_RC=5
        stages.promote "$CTX_FILE" >/dev/null 2>&1
        local rc=$?
        printf 'rc=%s|status=%s|kind=%s' "$rc" "$(read_status)" "$(read_kind)"
      }
      When call invoke
      The output should equal "rc=5|status=failure|kind=journal-failed"
    End

    It "does not opt into promotion when only one channel is declared"
      cat > "$BRIK_CONFIG_FILE" <<'YAML'
version: 1
project:
  name: promote-spec
  stack: node
artifacts:
  channels:
    candidate:
      registry: registry.internal/app
YAML
      invoke() {
        stages.promote "$CTX_FILE" 2>/dev/null
        local rc=$?
        printf 'rc=%s|kind=%s' "$rc" "$(read_kind)"
      }
      When call invoke
      The output should equal "rc=0|kind=not-applicable"
    End
  End
End

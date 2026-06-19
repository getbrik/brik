#shellcheck shell=bash
# Contract for lib/transverse/deployment_journal.sh -- the DeploymentJournal.
#
# Deployed events are env-scoped, file-per-event JSON documents committed
# append-only to the state-repo via transverse.state_repo.*. Every event is
# digest-bound (anti-replay) and carries the definition_hash of the rendered
# definition that was applied (the P3 drift anchor), plus the Layer V/E refs
# and orchestrator run metadata (informational -- authority always comes from
# the signed git commit that appends the file). Events are schema-validated
# fail-closed at write AND at read
# (schemas/state/v1/deployment-event.schema.json). The state-repo functions
# are stubbed against a fake store; schema validation runs for real.

Describe "transverse.deployment_journal"
  BRIK_HOME="$(cd "${SHELLSPEC_PROJECT_ROOT}" && pwd)"
  export BRIK_HOME
  Include "${BRIK_HOME}/lib/pipeline/error.sh"

  brik.use() { :; }
  log.info()  { :; }
  log.warn()  { :; }
  log.error() { printf 'ERROR: %s\n' "$*" >&2; }
  # No referential in this unit context: the state-repo token-var resolver is a
  # legacy passthrough (echo the caller's fallback var, the second argument).
  transverse.state_repo.token_var() { printf '%s' "${2:-}"; }

  # The real config.get drives definition_hash (it reads the workspace
  # brik.yml through yq); the record_deployment group overrides it per-example.
  # Pin the self-source guards first: config.sh would otherwise pull the real
  # loader/logging and clobber the brik.use/log stubs above.
  _BRIK_LOADER_LOADED=1
  _BRIK_LOGGING_LOADED=1
  Include "${BRIK_HOME}/lib/transverse/config.sh"
  Include "${BRIK_HOME}/lib/transverse/deployment_journal.sh"

  DIGEST="sha256:4444444444444444444444444444444444444444444444444444444444444444"
  DEF_HASH="sha256:7777777777777777777777777777777777777777777777777777777777777777"
  VREF="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  EREF="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  TS="2026-06-12T09:00:00Z"

  Describe "deployment_journal.relpath"
    It "derives the day-bucketed path from the event timestamp"
      When call deployment_journal.relpath "$TS" "cafe0123deadbeef"
      The output should equal "deployments/2026/06/12/20260612T090000Z-cafe0123deadbeef.json"
    End
  End

  Describe "deployment_journal.build_event"
    It "emits a schema-valid deployed event with refs and run metadata"
      When call deployment_journal.build_event \
        --environment production --version v1.2.3 --digest "$DIGEST" \
        --definition-hash "$DEF_HASH" \
        --version-ref "$VREF" --env-config-ref "$EREF" \
        --run-id "1234" --run-url "https://ci/pipelines/1234" \
        --actor "jdoe" --timestamp "$TS"
      The status should be success
      The output should include '"type": "deployed"'
      The output should include '"environment": "production"'
      The output should include '"digest": "sha256:4444444444444444444444444444444444444444444444444444444444444444"'
      The output should include "\"definition_hash\": \"${DEF_HASH}\""
      The output should include "\"version_ref\": \"${VREF}\""
      The output should include "\"env_config_ref\": \"${EREF}\""
      The output should include '"run_id": "1234"'
      The output should include '"run_url": "https://ci/pipelines/1234"'
      The output should include '"actor": "jdoe"'
    End

    It "emits a minimal schema-valid event without the optional fields"
      When call deployment_journal.build_event \
        --environment staging --version v1.2.3 --digest "$DIGEST" \
        --definition-hash "$DEF_HASH" --timestamp "$TS"
      The status should be success
      The output should include '"type": "deployed"'
      The output should not include '"version_ref"'
      The output should not include '"run_id"'
      The output should not include '"actor"'
    End

    It "stamps the current UTC time when no timestamp is given"
      When call deployment_journal.build_event \
        --environment staging --version v1.2.3 --digest "$DIGEST" \
        --definition-hash "$DEF_HASH"
      The status should be success
      The output should match pattern '*"timestamp": "20*T*Z"*'
    End

    It "refuses a missing digest"
      When call deployment_journal.build_event \
        --environment staging --version v1.2.3 \
        --definition-hash "$DEF_HASH" --timestamp "$TS"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "digest"
    End

    It "fails closed on a tag-form digest (anti-replay: events bind to sha256)"
      When call deployment_journal.build_event \
        --environment staging --version v1.2.3 --digest "latest" \
        --definition-hash "$DEF_HASH" --timestamp "$TS"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "digest"
    End

    It "refuses a missing environment (the journal is env-scoped)"
      When call deployment_journal.build_event \
        --version v1.2.3 --digest "$DIGEST" \
        --definition-hash "$DEF_HASH" --timestamp "$TS"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "environment"
    End

    It "refuses a missing definition_hash (the drift anchor is not optional)"
      When call deployment_journal.build_event \
        --environment staging --version v1.2.3 --digest "$DIGEST" \
        --timestamp "$TS"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "definition"
    End

    It "refuses a malformed definition_hash"
      When call deployment_journal.build_event \
        --environment staging --version v1.2.3 --digest "$DIGEST" \
        --definition-hash "not-a-hash" --timestamp "$TS"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "definition"
    End

    It "fails closed when no schema validator is available"
      hide_validators() {
        command() {
          case "${2:-}" in jv|check-jsonschema) return 1 ;; esac
          builtin command "$@"
        }
        deployment_journal.build_event \
          --environment staging --version v1.2.3 --digest "$DIGEST" \
          --definition-hash "$DEF_HASH" --timestamp "$TS"
      }
      When call hide_validators
      The status should equal "$BRIK_EXIT_MISSING_DEP"
      The stderr should include "validator"
    End
  End

  Describe "deployment_journal.definition_hash"
    # The hash covers the env's canonical config block, the content of the
    # local definition files it references and the pinned image ref --
    # deterministic and location-independent, so P3 status can re-derive it
    # from the recorded refs and compare.
    setup_ws() {
      WS="$(mktemp -d)"
      WS2=""
      mkdir -p "$WS/k8s"
      cat > "$WS/brik.yml" <<'YAML'
version: 1
deploy:
  environments:
    staging:
      target: k8s
      manifest: k8s/deploy.yml
      namespace: staging
YAML
      printf 'kind: Deployment\nimage: app:old\n' > "$WS/k8s/deploy.yml"
    }
    cleanup_ws() { rm -rf "$WS" "$WS2"; }
    BeforeEach setup_ws
    AfterEach cleanup_ws

    It "emits a sha256 and is deterministic"
      twice() {
        local a b
        a="$(deployment_journal.definition_hash \
          --workspace "$WS" --environment staging --pinned "registry/app@${DIGEST}")" || return $?
        b="$(deployment_journal.definition_hash \
          --workspace "$WS" --environment staging --pinned "registry/app@${DIGEST}")" || return $?
        [[ "$a" == "$b" ]] || return 1
        printf '%s' "$a"
      }
      When call twice
      The status should be success
      The output should match pattern 'sha256:????????????????????????????????????????????????????????????????'
    End

    It "is location-independent (same definition elsewhere hashes identically)"
      relocate() {
        local a b
        a="$(deployment_journal.definition_hash \
          --workspace "$WS" --environment staging --pinned "registry/app@${DIGEST}")" || return $?
        WS2="$(mktemp -d)"
        cp -R "$WS/." "$WS2/"
        b="$(deployment_journal.definition_hash \
          --workspace "$WS2" --environment staging --pinned "registry/app@${DIGEST}")" || return $?
        [[ "$a" == "$b" ]] && printf 'same'
      }
      When call relocate
      The status should be success
      The output should equal "same"
    End

    It "changes when a referenced definition file changes"
      mutate_file() {
        local a b
        a="$(deployment_journal.definition_hash \
          --workspace "$WS" --environment staging --pinned "registry/app@${DIGEST}")" || return $?
        printf 'kind: Deployment\nimage: app:new\n' > "$WS/k8s/deploy.yml"
        b="$(deployment_journal.definition_hash \
          --workspace "$WS" --environment staging --pinned "registry/app@${DIGEST}")" || return $?
        [[ "$a" != "$b" ]] && printf 'different'
      }
      When call mutate_file
      The status should be success
      The output should equal "different"
    End

    It "changes when the env config block changes"
      mutate_config() {
        local a b
        a="$(deployment_journal.definition_hash \
          --workspace "$WS" --environment staging --pinned "registry/app@${DIGEST}")" || return $?
        yq -i '.deploy.environments.staging.namespace = "staging-2"' "$WS/brik.yml"
        b="$(deployment_journal.definition_hash \
          --workspace "$WS" --environment staging --pinned "registry/app@${DIGEST}")" || return $?
        [[ "$a" != "$b" ]] && printf 'different'
      }
      When call mutate_config
      The status should be success
      The output should equal "different"
    End

    It "changes when the pinned image ref changes"
      mutate_pin() {
        local a b
        a="$(deployment_journal.definition_hash \
          --workspace "$WS" --environment staging --pinned "registry/app@${DIGEST}")" || return $?
        b="$(deployment_journal.definition_hash \
          --workspace "$WS" --environment staging \
          --pinned "registry/app@sha256:5555555555555555555555555555555555555555555555555555555555555555")" || return $?
        [[ "$a" != "$b" ]] && printf 'different'
      }
      When call mutate_pin
      The status should be success
      The output should equal "different"
    End

    It "fails closed on an undeclared environment"
      When call deployment_journal.definition_hash \
        --workspace "$WS" --environment ghost
      The status should equal "$BRIK_EXIT_CONFIG_ERROR"
      The stderr should include "ghost"
    End
  End

  Describe "deployment_journal.publish"
    setup_pub() {
      APPEND_REC="$(mktemp)"
      COMMIT_MSG=""
      SIGNED="no"
      transverse.state_repo.clone()  { return 0; }
      transverse.state_repo.append() { printf '%s' "$2" >"$APPEND_REC"; cat >/dev/null; }
      transverse.state_repo.commit() {
        COMMIT_MSG="$2"
        case "$*" in *--sign*) SIGNED="yes" ;; esac
        return 0
      }
      transverse.state_repo.push()   { return 0; }
    }
    cleanup_pub() { rm -f "$APPEND_REC"; }
    BeforeEach setup_pub
    AfterEach cleanup_pub

    event() {
      deployment_journal.build_event \
        --environment production --version v1.2.3 --digest "$DIGEST" \
        --definition-hash "$DEF_HASH" --timestamp "$TS"
    }

    It "appends the event at its day-bucketed path and signs the commit"
      pub() {
        # herestring, not a pipe: the commit stub must run in this shell so
        # SIGNED/COMMIT_MSG survive.
        deployment_journal.publish --repo https://git/state.git --sign <<<"$(event)"
        printf '%s|%s|%s' "$(cat "$APPEND_REC")" "$SIGNED" "$COMMIT_MSG"
      }
      When call pub
      The status should be success
      The output should include "deployments/2026/06/12/20260612T090000Z-"
      The output should include "|yes|"
      The output should include "deployed production v1.2.3"
    End

    It "fails closed on an event that does not validate, without touching the store"
      pub() {
        printf '{"schema":"brik.deployment-event/v1","type":"deployed"}' \
          | deployment_journal.publish --repo https://git/state.git
        local rc=$?
        printf '%s' "$(cat "$APPEND_REC")"
        return "$rc"
      }
      When call pub
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The output should equal ""
      The stderr should include "schema"
    End

    It "dry-run consumes the event and does not append"
      pub() {
        deployment_journal.publish --repo https://git/state.git --dry-run <<<"$(event)"
        printf '%s' "$(cat "$APPEND_REC")"
      }
      When call pub
      The status should be success
      The output should equal ""
    End
  End

  Describe "deployment_journal.record_deployment"
    setup_rec() {
      PUB_REC="$(mktemp)"
      EVIDENCE_REPO=""
      EVIDENCE_SIGN="false"
      config.get() {
        case "$1" in
          .artifacts.evidence.repo)      printf '%s' "$EVIDENCE_REPO" ;;
          .artifacts.evidence.branch)    printf 'main' ;;
          .artifacts.evidence.token_var) printf 'STATE_TOKEN' ;;
          .artifacts.evidence.sign)      printf '%s' "$EVIDENCE_SIGN" ;;
          *) printf '%s' "${2:-}" ;;
        esac
      }
      deployment_journal.publish() {
        printf '%s\n' "$*" >"${PUB_REC}.args"
        cat >"$PUB_REC"
        return "${PUB_RC:-0}"
      }
    }
    cleanup_rec() { rm -f "$PUB_REC" "${PUB_REC}.args"; }
    BeforeEach setup_rec
    AfterEach cleanup_rec

    It "skips silently when the project declares no state-repo"
      rec() {
        deployment_journal.record_deployment \
          --environment production --version v1.2.3 --digest "$DIGEST" \
          --definition-hash "$DEF_HASH"
        printf '%s' "$(cat "$PUB_REC")"
      }
      When call rec
      The status should be success
      The output should equal ""
    End

    It "publishes a signed deployed event to the declared state-repo"
      rec() {
        EVIDENCE_REPO="https://git/state.git"
        EVIDENCE_SIGN="true"
        deployment_journal.record_deployment \
          --environment production --version v1.2.3 --digest "$DIGEST" \
          --definition-hash "$DEF_HASH" \
          --version-ref "$VREF" --run-id "42" --actor "jdoe" || return $?
        printf '%s||%s' "$(cat "${PUB_REC}.args")" "$(cat "$PUB_REC")"
      }
      When call rec
      The status should be success
      The output should include "--repo https://git/state.git"
      The output should include "--branch main"
      The output should include "--token-var STATE_TOKEN"
      The output should include "--sign"
      The output should include '"type": "deployed"'
      The output should include '"environment": "production"'
      The output should include '"digest": "sha256:4444444444444444444444444444444444444444444444444444444444444444"'
      The output should include "\"version_ref\": \"${VREF}\""
      The output should include '"run_id": "42"'
      The output should include '"actor": "jdoe"'
    End

    It "propagates a journal publish failure (a declared journal must record)"
      rec() {
        EVIDENCE_REPO="https://git/state.git"
        PUB_RC=5
        deployment_journal.record_deployment \
          --environment production --version v1.2.3 --digest "$DIGEST" \
          --definition-hash "$DEF_HASH"
      }
      When call rec
      The status should equal "$BRIK_EXIT_EXTERNAL_FAIL"
      The stderr should include "journal"
    End
  End

  Describe "deployment_journal.events_for"
    seed_journal() {
      JOURNAL_DIR="$(mktemp -d)"
      mkdir -p "${JOURNAL_DIR}/deployments/2026/06/12"
      deployment_journal.build_event \
        --environment staging --version v1.2.3 --digest "$DIGEST" \
        --definition-hash "$DEF_HASH" --timestamp "$TS" \
        >"${JOURNAL_DIR}/deployments/2026/06/12/a.json"
      deployment_journal.build_event \
        --environment production --version v1.2.3 --digest "$DIGEST" \
        --definition-hash "$DEF_HASH" --timestamp "$TS" \
        >"${JOURNAL_DIR}/deployments/2026/06/12/b.json"
      deployment_journal.build_event \
        --environment production --version v2.0.0 \
        --digest "sha256:5555555555555555555555555555555555555555555555555555555555555555" \
        --definition-hash "$DEF_HASH" --timestamp "$TS" \
        >"${JOURNAL_DIR}/deployments/2026/06/12/c.json"
    }
    cleanup_journal() { rm -rf "$JOURNAL_DIR"; }
    BeforeEach seed_journal
    AfterEach cleanup_journal

    It "returns only the events of the environment"
      list() { deployment_journal.events_for "$JOURNAL_DIR" --environment production | jq -r 'length'; }
      When call list
      The output should equal "2"
    End

    It "filters by digest"
      list() {
        deployment_journal.events_for "$JOURNAL_DIR" --environment production \
          --digest "$DIGEST" | jq -r '.[].version'
      }
      When call list
      The output should equal "v1.2.3"
    End

    It "returns an empty array when the journal has no deployments directory"
      empty_tree() {
        local d; d="$(mktemp -d)"
        deployment_journal.events_for "$d" --environment production
        local rc=$?
        rm -rf "$d"
        return "$rc"
      }
      When call empty_tree
      The status should be success
      The output should equal "[]"
    End

    It "fails closed when the journal contains an event that does not validate"
      poisoned() {
        printf '{"schema":"brik.deployment-event/v1","type":"deployed"}' \
          >"${JOURNAL_DIR}/deployments/2026/06/12/z.json"
        deployment_journal.events_for "$JOURNAL_DIR" --environment production
      }
      When call poisoned
      The status should equal "$BRIK_EXIT_CHECK_FAILED"
      The stderr should include "z.json"
    End
  End
End

#shellcheck shell=bash
# Contract for lib/transverse/promotion_journal.sh -- the PromotionJournal.
#
# Journal events are file-per-event JSON documents committed append-only to
# the state-repo via transverse.state_repo.*. Every event is digest-bound
# (anti-replay) and schema-validated fail-closed at write AND at read
# (schemas/state/v1/promotion-event.schema.json). The state-repo functions
# are stubbed against a fake store; schema validation runs for real.

Describe "transverse.promotion_journal"
  BRIK_HOME="$(cd "${SHELLSPEC_PROJECT_ROOT}" && pwd)"
  export BRIK_HOME
  Include "${BRIK_HOME}/lib/pipeline/error.sh"

  brik.use() { :; }
  log.info()  { :; }
  log.warn()  { :; }
  log.error() { printf 'ERROR: %s\n' "$*" >&2; }

  Include "${BRIK_HOME}/lib/transverse/promotion_journal.sh"

  DIGEST="sha256:4444444444444444444444444444444444444444444444444444444444444444"
  TS="2026-06-11T14:30:00Z"

  Describe "promotion_journal.relpath"
    It "derives the day-bucketed path from the event timestamp"
      When call promotion_journal.relpath "$TS" "cafe0123deadbeef"
      The output should equal "promotions/2026/06/11/20260611T143000Z-cafe0123deadbeef.json"
    End
  End

  Describe "promotion_journal.build_event"
    It "emits a schema-valid artifact_promoted event with its channel transition"
      When call promotion_journal.build_event \
        --type artifact_promoted --version v1.2.3 --digest "$DIGEST" \
        --from-channel candidate --to-channel release --timestamp "$TS"
      The status should be success
      The output should include '"type": "artifact_promoted"'
      The output should include '"digest": "sha256:4444444444444444444444444444444444444444444444444444444444444444"'
      The output should include '"from_channel": "candidate"'
      The output should include '"to_channel": "release"'
    End

    It "emits a schema-valid artifact_authorized_for event bound to an environment"
      When call promotion_journal.build_event \
        --type artifact_authorized_for --version v1.2.3 --digest "$DIGEST" \
        --environment production --timestamp "$TS"
      The status should be success
      The output should include '"type": "artifact_authorized_for"'
      The output should include '"environment": "production"'
    End

    It "stamps the current UTC time when no timestamp is given"
      When call promotion_journal.build_event \
        --type artifact_validated_for --version v1.2.3 --digest "$DIGEST" \
        --environment staging
      The status should be success
      The output should match pattern '*"timestamp": "20*T*Z"*'
    End

    It "refuses a missing digest"
      When call promotion_journal.build_event \
        --type artifact_promoted --version v1.2.3 \
        --from-channel candidate --to-channel release
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "digest"
    End

    It "fails closed on a tag-form digest (anti-replay: events bind to sha256)"
      When call promotion_journal.build_event \
        --type artifact_promoted --version v1.2.3 --digest "latest" \
        --from-channel candidate --to-channel release --timestamp "$TS"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "digest"
    End

    It "refuses artifact_promoted without its channel transition"
      When call promotion_journal.build_event \
        --type artifact_promoted --version v1.2.3 --digest "$DIGEST" --timestamp "$TS"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "channel"
    End

    It "refuses an eligibility event without its environment"
      When call promotion_journal.build_event \
        --type artifact_authorized_for --version v1.2.3 --digest "$DIGEST" --timestamp "$TS"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "environment"
    End

    It "refuses an unknown event type"
      When call promotion_journal.build_event \
        --type artifact_blessed --version v1.2.3 --digest "$DIGEST" --timestamp "$TS"
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "type"
    End

    It "fails closed when no schema validator is available"
      hide_validators() {
        command() {
          case "${2:-}" in jv|check-jsonschema) return 1 ;; esac
          builtin command "$@"
        }
        promotion_journal.build_event \
          --type artifact_promoted --version v1.2.3 --digest "$DIGEST" \
          --from-channel candidate --to-channel release --timestamp "$TS"
      }
      When call hide_validators
      The status should equal "$BRIK_EXIT_MISSING_DEP"
      The stderr should include "validator"
    End
  End

  Describe "promotion_journal.publish"
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
      promotion_journal.build_event \
        --type artifact_authorized_for --version v1.2.3 --digest "$DIGEST" \
        --environment production --timestamp "$TS"
    }

    It "appends the event at its day-bucketed path and signs the commit"
      pub() {
        # heredstring, not a pipe: the commit stub must run in this shell so
        # SIGNED/COMMIT_MSG survive.
        promotion_journal.publish --repo https://git/state.git --sign <<<"$(event)"
        printf '%s|%s|%s' "$(cat "$APPEND_REC")" "$SIGNED" "$COMMIT_MSG"
      }
      When call pub
      The status should be success
      The output should include "promotions/2026/06/11/20260611T143000Z-"
      The output should include "|yes|"
      The output should include "artifact_authorized_for v1.2.3"
    End

    It "fails closed on an event that does not validate, without touching the store"
      pub() {
        printf '{"schema":"brik.promotion-event/v1","type":"artifact_authorized_for"}' \
          | promotion_journal.publish --repo https://git/state.git
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
        promotion_journal.publish --repo https://git/state.git --dry-run <<<"$(event)"
        printf '%s' "$(cat "$APPEND_REC")"
      }
      When call pub
      The status should be success
      The output should equal ""
    End
  End

  Describe "promotion_journal.record_promotion"
    setup_rec() {
      PUB_REC="$(mktemp)"
      PUB_ARGS=""
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
      promotion_journal.publish() {
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
        promotion_journal.record_promotion \
          --version v1.2.3 --digest "$DIGEST" \
          --from-channel candidate --to-channel release
        printf '%s' "$(cat "$PUB_REC")"
      }
      When call rec
      The status should be success
      The output should equal ""
    End

    It "publishes a signed artifact_promoted event to the declared state-repo"
      rec() {
        EVIDENCE_REPO="https://git/state.git"
        EVIDENCE_SIGN="true"
        promotion_journal.record_promotion \
          --version v1.2.3 --digest "$DIGEST" \
          --from-channel candidate --to-channel release || return $?
        printf '%s||%s' "$(cat "${PUB_REC}.args")" "$(cat "$PUB_REC")"
      }
      When call rec
      The status should be success
      The output should include "--repo https://git/state.git"
      The output should include "--branch main"
      The output should include "--token-var STATE_TOKEN"
      The output should include "--sign"
      The output should include '"type": "artifact_promoted"'
      The output should include '"digest": "sha256:4444444444444444444444444444444444444444444444444444444444444444"'
      The output should include '"from_channel": "candidate"'
    End

    It "propagates a journal publish failure (a declared journal must record)"
      rec() {
        EVIDENCE_REPO="https://git/state.git"
        PUB_RC=5
        promotion_journal.record_promotion \
          --version v1.2.3 --digest "$DIGEST" \
          --from-channel candidate --to-channel release
      }
      When call rec
      The status should equal "$BRIK_EXIT_EXTERNAL_FAIL"
      The stderr should include "journal"
    End
  End

  Describe "promotion_journal.record_authorization"
    setup_auth() {
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
      promotion_journal.publish() {
        printf '%s\n' "$*" >"${PUB_REC}.args"
        cat >"$PUB_REC"
        return "${PUB_RC:-0}"
      }
    }
    cleanup_auth() { rm -f "$PUB_REC" "${PUB_REC}.args"; }
    BeforeEach setup_auth
    AfterEach cleanup_auth

    It "refuses to authorize when no state-repo is declared (no journal, no grant)"
      When call promotion_journal.record_authorization \
        --version v1.2.3 --digest "$DIGEST" --environment production
      The status should equal "$BRIK_EXIT_CONFIG_ERROR"
      The stderr should include "state-repo"
    End

    It "publishes a signed artifact_authorized_for event bound to digest and environment"
      rec() {
        EVIDENCE_REPO="https://git/state.git"
        EVIDENCE_SIGN="true"
        promotion_journal.record_authorization \
          --version v1.2.3 --digest "$DIGEST" --environment production || return $?
        printf '%s||%s' "$(cat "${PUB_REC}.args")" "$(cat "$PUB_REC")"
      }
      When call rec
      The status should be success
      The output should include "--repo https://git/state.git"
      The output should include "--sign"
      The output should include '"type": "artifact_authorized_for"'
      The output should include '"environment": "production"'
      The output should include '"digest": "sha256:4444444444444444444444444444444444444444444444444444444444444444"'
    End

    It "propagates a journal publish failure"
      rec() {
        EVIDENCE_REPO="https://git/state.git"
        PUB_RC=5
        promotion_journal.record_authorization \
          --version v1.2.3 --digest "$DIGEST" --environment production
      }
      When call rec
      The status should equal "$BRIK_EXIT_EXTERNAL_FAIL"
      The stderr should include "journal"
    End
  End

  Describe "promotion_journal.events_for"
    OTHER_DIGEST="sha256:5555555555555555555555555555555555555555555555555555555555555555"

    seed_journal() {
      JOURNAL_DIR="$(mktemp -d)"
      mkdir -p "${JOURNAL_DIR}/promotions/2026/06/11"
      promotion_journal.build_event \
        --type artifact_promoted --version v1.2.3 --digest "$DIGEST" \
        --from-channel candidate --to-channel release --timestamp "$TS" \
        >"${JOURNAL_DIR}/promotions/2026/06/11/a.json"
      promotion_journal.build_event \
        --type artifact_authorized_for --version v1.2.3 --digest "$DIGEST" \
        --environment production --timestamp "$TS" \
        >"${JOURNAL_DIR}/promotions/2026/06/11/b.json"
      promotion_journal.build_event \
        --type artifact_authorized_for --version v2.0.0 --digest "$OTHER_DIGEST" \
        --environment production --timestamp "$TS" \
        >"${JOURNAL_DIR}/promotions/2026/06/11/c.json"
    }
    cleanup_journal() { rm -rf "$JOURNAL_DIR"; }
    BeforeEach seed_journal
    AfterEach cleanup_journal

    It "returns only the events bound to the digest"
      list() { promotion_journal.events_for "$JOURNAL_DIR" --digest "$DIGEST" | jq -r 'length'; }
      When call list
      The output should equal "2"
    End

    It "filters by environment and type"
      list() {
        promotion_journal.events_for "$JOURNAL_DIR" --digest "$DIGEST" \
          --environment production --type artifact_authorized_for | jq -r '.[].type'
      }
      When call list
      The output should equal "artifact_authorized_for"
    End

    It "returns an empty array when the journal has no promotions directory"
      empty_tree() {
        local d; d="$(mktemp -d)"
        promotion_journal.events_for "$d" --digest "$DIGEST"
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
        printf '{"schema":"brik.promotion-event/v1","type":"artifact_promoted"}' \
          >"${JOURNAL_DIR}/promotions/2026/06/11/z.json"
        promotion_journal.events_for "$JOURNAL_DIR" --digest "$DIGEST"
      }
      When call poisoned
      The status should equal "$BRIK_EXIT_CHECK_FAILED"
      The stderr should include "z.json"
    End
  End
End

Describe "cli/authorize.sh"
  # The verb is exercised as the sourced cli.authorize.run function (not the
  # bin/brik child process) so kcov attributes the executed lines; one
  # dispatcher round-trip at the end keeps the bin/brik contract pinned.
  Include "$BRIK_HOME/lib/pipeline/logging.sh"
  Include "$BRIK_HOME/lib/pipeline/error.sh"
  Include "$BRIK_HOME/lib/pipeline/tools.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/cli/helpers.sh"
  Include "$BRIK_HOME/lib/cli/authorize.sh"
  # The dispatcher (bin/brik) owns this default; the sourced verb needs it.
  export BRIK_DEFAULT_CONFIG="brik.yml"

  PINNED_DIGEST="sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

  # The resolution primitive's contract is channel_resolve_digest_spec; the
  # journal's is promotion_journal_spec. Stub both modules (the loader guards
  # keep brik.use from sourcing them) so this unit covers the verb's parsing,
  # gates and wiring.
  _BRIK_MODULE_TRANSVERSE_CHANNEL_LOADED=1
  channel.resolve_digest() {
    printf 'resolve_digest %s\n' "$*" >> "${RESOLVE_LOG}"
    if [[ -n "${RESOLVE_RC:-}" && "${RESOLVE_RC}" != "0" ]]; then
      return "$RESOLVE_RC"
    fi
    printf 'registry.release/app@%s' "$PINNED_DIGEST"
  }
  _BRIK_MODULE_TRANSVERSE_PROMOTION_JOURNAL_LOADED=1
  promotion_journal.record_authorization() {
    printf 'record_authorization %s\n' "$*" >> "${JOURNAL_LOG}"
    return "${JOURNAL_RC:-0}"
  }

  setup_workspace() {
    WS="$(mktemp -d)"
    RESOLVE_LOG="${WS}/resolve.log"
    JOURNAL_LOG="${WS}/journal.log"
    cat > "${WS}/brik.yml" <<'YAML'
version: 1
project:
  name: authorize-verb
artifacts:
  channels:
    release:
      registry: registry.release/app
  evidence:
    repo: https://git.example/state.git
    sign: true
deploy:
  environments:
    production:
      accepts_channel: release
      target: k8s
    sandbox:
      target: compose
YAML
    INFRA="$(mktemp -d)"
    printf 'apiVersion: brik.dev/referential/v1\nkind: Referential\nprofile: p-lab\n' \
      > "$INFRA/referential.yml"
    export BRIK_INFRA_DIR="$INFRA"
  }
  cleanup_workspace() {
    rm -rf "$WS" "$INFRA"
    unset BRIK_INFRA_DIR BRIK_CONFIG_FILE WS INFRA RESOLVE_LOG JOURNAL_LOG
    unset BRIK_NOTIFY_WEBHOOK_URL
  }
  Before 'setup_workspace'
  After 'cleanup_workspace'

  It "requires --version"
    When call cli.authorize.run --for production --workspace "$WS"
    The status should equal 2
    The stderr should include "--version"
  End

  It "requires --for"
    When call cli.authorize.run --version 1.2.3 --workspace "$WS"
    The status should equal 2
    The stderr should include "--for"
  End

  It "rejects an unknown option"
    When call cli.authorize.run --version 1.2.3 --for production --bogus x --workspace "$WS"
    The status should equal 2
    The stderr should include "unknown option"
  End

  It "fails io_failure (6) when the config file is absent"
    When call cli.authorize.run --version 1.2.3 --for production --workspace "$WS" --config "${WS}/ghost.yml"
    The status should equal 6
    The stderr should include "ghost.yml"
  End

  It "fails closed (4) when no referential is configured"
    no_infra() {
      unset BRIK_INFRA_DIR
      cli.authorize.run --version 1.2.3 --for production --workspace "$WS"
    }
    When call no_infra
    The status should equal 4
    The stderr should include "brik infra init"
  End

  It "refuses an environment that accepts no channel (no digest to bind to)"
    When call cli.authorize.run --version 1.2.3 --for sandbox --workspace "$WS"
    The status should equal 7
    The stderr should include "accepts_channel"
  End

  It "resolves the digest in the accepted channel and journals the authorization"
    invoke() {
      cli.authorize.run --version 1.2.3 --for production --workspace "$WS" >/dev/null || return $?
      cat "$RESOLVE_LOG" "$JOURNAL_LOG"
    }
    When call invoke
    The output should equal "resolve_digest 1.2.3 release
record_authorization --version 1.2.3 --digest ${PINNED_DIGEST} --environment production"
    The stderr should include "authorized 1.2.3 for production"
  End

  It "prints the digest-pinned ref the grant is bound to"
    When call cli.authorize.run --version 1.2.3 --for production --workspace "$WS"
    The output should equal "registry.release/app@${PINNED_DIGEST}"
    The stderr should include "authorized"
  End

  It "fails closed when the version does not resolve in the accepted channel"
    invoke() {
      RESOLVE_RC=5
      cli.authorize.run --version 1.2.3 --for production --workspace "$WS" >/dev/null
    }
    When call invoke
    The status should equal 5
    The stderr should include "cannot resolve"
  End

  It "propagates a journal failure (no journal entry, no grant)"
    invoke() {
      JOURNAL_RC=5
      cli.authorize.run --version 1.2.3 --for production --workspace "$WS" >/dev/null
    }
    When call invoke
    The status should equal 5
  End

  It "describes the grant without journaling it on --dry-run"
    invoke() {
      cli.authorize.run --version 1.2.3 --for production --workspace "$WS" --dry-run >/dev/null || return $?
      [[ -f "$JOURNAL_LOG" ]] && echo "journaled"
      return 0
    }
    When call invoke
    The output should equal ""
    The stderr should include "[dry-run] would journal artifact_authorized_for"
  End

  Describe "notification (F4 minimal)"
    It "posts a webhook notification carrying the grant when configured"
      curl() { printf '%s\n' "$*" >> "${WS}/curl.log"; }
      invoke() {
        export BRIK_NOTIFY_WEBHOOK_URL="https://hooks.example/brik"
        cli.authorize.run --version 1.2.3 --for production --workspace "$WS" >/dev/null || return $?
        cat "${WS}/curl.log"
      }
      When call invoke
      The output should include "https://hooks.example/brik"
      The output should include "artifact_authorized_for"
      The stderr should include "authorized 1.2.3 for production"
    End

    It "keeps the grant when the webhook fails (best-effort delivery)"
      curl() { return 22; }
      invoke() {
        export BRIK_NOTIFY_WEBHOOK_URL="https://hooks.example/brik"
        cli.authorize.run --version 1.2.3 --for production --workspace "$WS" >/dev/null
      }
      When call invoke
      The status should be success
      The stderr should include "notification failed"
    End
  End

  Describe "dispatcher round-trip"
    It "wires 'brik authorize' to the verb"
      When run script "$BRIK_BIN" authorize
      The status should equal 2
      The stderr should include "--version"
    End
  End
End

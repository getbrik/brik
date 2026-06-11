Describe "cli/promote.sh"
  # The verb is exercised as the sourced cli.promote.run function (not the
  # bin/brik child process) so kcov attributes the executed lines; one
  # dispatcher round-trip at the end keeps the bin/brik contract pinned.
  Include "$BRIK_HOME/lib/pipeline/logging.sh"
  Include "$BRIK_HOME/lib/pipeline/error.sh"
  Include "$BRIK_HOME/lib/pipeline/tools.sh"
  Include "$BRIK_HOME/lib/pipeline/loader.sh"
  Include "$BRIK_HOME/lib/cli/helpers.sh"
  Include "$BRIK_HOME/lib/cli/promote.sh"
  # The dispatcher (bin/brik) owns this default; the sourced verb needs it.
  export BRIK_DEFAULT_CONFIG="brik.yml"

  PINNED_DIGEST="sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

  # The copy primitive's contract is channel_copy_with_referrers_spec: stub
  # the channel module (the loader guard keeps brik.use from sourcing it) so
  # this unit covers the verb's parsing, gates and wiring.
  _BRIK_MODULE_TRANSVERSE_CHANNEL_LOADED=1
  channel.registry() {
    case "$1" in
      candidate) printf 'registry.internal/app' ;;
      release)   printf 'registry.release/app' ;;
      *) log.error "channel '$1' has no registry configured under artifacts.channels"
         return "$BRIK_EXIT_CONFIG_ERROR" ;;
    esac
  }
  channel.copy_with_referrers() {
    printf 'copy_with_referrers %s\n' "$*" >> "${PROMOTE_LOG}"
    if [[ -n "${CHAN_RC:-}" && "${CHAN_RC}" != "0" ]]; then
      return "$CHAN_RC"
    fi
    printf 'registry.release/app@%s' "$PINNED_DIGEST"
  }
  # The journal's contract is promotion_journal_spec; stub it at the same
  # altitude as the copy primitive.
  _BRIK_MODULE_TRANSVERSE_PROMOTION_JOURNAL_LOADED=1
  promotion_journal.record_promotion() {
    printf 'record_promotion %s\n' "$*" >> "${JOURNAL_LOG}"
    return "${JOURNAL_RC:-0}"
  }

  setup_workspace() {
    WS="$(mktemp -d)"
    PROMOTE_LOG="${WS}/promote.log"
    JOURNAL_LOG="${WS}/journal.log"
    cat > "${WS}/brik.yml" <<'YAML'
version: 1
project:
  name: promote-verb
artifacts:
  channels:
    candidate:
      registry: registry.internal/app
    release:
      registry: registry.release/app
YAML
    INFRA="$(mktemp -d)"
    printf 'apiVersion: brik.dev/referential/v1\nkind: Referential\nprofile: p-lab\n' \
      > "$INFRA/referential.yml"
    export BRIK_INFRA_DIR="$INFRA"
  }
  cleanup_workspace() {
    rm -rf "$WS" "$INFRA"
    unset BRIK_INFRA_DIR BRIK_CONFIG_FILE WS INFRA PROMOTE_LOG JOURNAL_LOG
  }
  Before 'setup_workspace'
  After 'cleanup_workspace'

  It "requires --version"
    When call cli.promote.run --workspace "$WS"
    The status should equal 2
    The stderr should include "--version"
  End

  It "refuses identical --from and --to channels"
    When call cli.promote.run --version 1.2.3 --from release --to release --workspace "$WS"
    The status should equal 2
    The stderr should include "distinct"
  End

  It "rejects an unknown option"
    When call cli.promote.run --version 1.2.3 --bogus x --workspace "$WS"
    The status should equal 2
    The stderr should include "unknown option"
  End

  It "fails io_failure (6) when the config file is absent"
    When call cli.promote.run --version 1.2.3 --workspace "$WS" --config "${WS}/ghost.yml"
    The status should equal 6
    The stderr should include "ghost.yml"
  End

  It "fails closed (4) when no referential is configured"
    no_infra() {
      unset BRIK_INFRA_DIR
      cli.promote.run --version 1.2.3 --workspace "$WS"
    }
    When call no_infra
    The status should equal 4
    The stderr should include "brik infra init"
  End

  It "promotes candidate->release by default and prints the pinned ref"
    When call cli.promote.run --version 1.2.3 --workspace "$WS"
    The output should equal "registry.release/app@${PINNED_DIGEST}"
    The stderr should include "promoted 1.2.3: candidate -> release"
  End

  It "forwards channels, identity and issuer to the primitive"
    invoke() {
      cli.promote.run --version 2.0.0 --from staging-chan --to release \
        --identity 'https://ci.example/.*' --issuer 'https://oidc.example' \
        --workspace "$WS" >/dev/null || return $?
      cat "$PROMOTE_LOG"
    }
    When call invoke
    The output should equal "copy_with_referrers 2.0.0 staging-chan release --identity https://ci.example/.* --issuer https://oidc.example"
    The stderr should include "promoted"
  End

  It "journals artifact_promoted with the pinned digest and the channel pair"
    invoke() {
      cli.promote.run --version 1.2.3 --from candidate --to release --workspace "$WS" >/dev/null || return $?
      cat "$JOURNAL_LOG"
    }
    When call invoke
    The output should equal "record_promotion --version 1.2.3 --digest ${PINNED_DIGEST} --from-channel candidate --to-channel release"
    The stderr should include "promoted"
  End

  It "propagates a journal failure (a declared journal must record)"
    invoke() {
      JOURNAL_RC=5
      cli.promote.run --version 1.2.3 --workspace "$WS" >/dev/null
    }
    When call invoke
    The status should equal 5
  End

  It "propagates the primitive's failure code"
    invoke() {
      CHAN_RC=10
      cli.promote.run --version 1.2.3 --workspace "$WS"
    }
    When call invoke
    The status should equal 10
  End

  It "describes the copy without performing it on --dry-run"
    invoke() {
      cli.promote.run --version 1.2.3 --workspace "$WS" --dry-run || return $?
      [[ -f "$PROMOTE_LOG" ]] && echo "called"
      return 0
    }
    When call invoke
    The output should equal ""
    The stderr should include "[dry-run] would copy registry.internal/app:1.2.3 -> registry.release/app:1.2.3"
  End

  Describe "dispatcher round-trip"
    It "wires 'brik promote' to the verb"
      When run script "$BRIK_BIN" promote
      The status should equal 2
      The stderr should include "--version"
    End
  End
End

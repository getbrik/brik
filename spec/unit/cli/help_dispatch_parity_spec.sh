#!/usr/bin/env bash
# help_dispatch_parity_spec.sh - guards that the `brik help` Commands block
# never advertises a verb the dispatcher cannot run, and that every
# user-facing verb answers `--help` with a usage block (exit 0).

Describe "brik help / dispatch parity"

  Describe "advertised commands all dispatch"
    # Every leading verb token in the Commands: block must resolve to a real
    # dispatch case (never the 'unknown command' path). This catches help drift
    # like 'run stage' / 'run pipeline' that the dispatcher never had.
    It "advertises no command that the dispatcher rejects as unknown"
      run_check() {
        local help_text first_words verb
        help_text="$("$BRIK_BIN" help)"
        # Extract the Commands: section, take the first token of each entry.
        first_words="$(printf '%s\n' "$help_text" \
          | awk '/^Commands:/{c=1;next} c&&/^Options for /{exit} c&&/^[[:space:]]+[a-z]/{print $1}')"
        local word
        while IFS= read -r verb; do
          [[ -z "$verb" ]] && continue
          word="$("$BRIK_BIN" "$verb" --__parity_probe__ 2>&1 || true)"
          if printf '%s' "$word" | grep -q "unknown command: ${verb}"; then
            printf 'ADVERTISED-BUT-UNDISPATCHED: %s\n' "$verb"
          fi
        done <<<"$first_words"
      }
      When call run_check
      The output should equal ""
    End

    It "no longer advertises the phantom 'run' namespace"
      When run script "$BRIK_BIN" help
      The status should eq 0
      The output should not include "run stage"
      The output should not include "run pipeline"
    End

    It "rejects 'brik run' as an unknown command"
      When run script "$BRIK_BIN" run pipeline
      The status should eq 2
      The stderr should include "unknown command: run"
    End
  End

  Describe "every user-facing command answers --help"
    Parameters
      validate
      doctor
      init
      plan
      integrate
      stage
      deploy
      promote
      authorize
      status
      infra
      extension
      registry
      self-update
      self-uninstall
      version
    End

    It "prints usage and exits 0 for: $1"
      When run script "$BRIK_BIN" "$1" --help
      The status should eq 0
      The output should include "Usage:"
    End
  End

  Describe "two-word leaf subcommands answer --help"
    # The leaf subcommands have their own option parsers, distinct from their
    # parent verb. Each must honor --help with a usage block (exit 0) so the
    # "every command is self-describing" promise holds at every depth.
    It "prints usage and exits 0 for: infra init --help"
      When run script "$BRIK_BIN" infra init --help
      The status should eq 0
      The output should include "Usage: brik infra init"
    End

    It "prints usage and exits 0 for: infra validate --help"
      When run script "$BRIK_BIN" infra validate --help
      The status should eq 0
      The output should include "Usage: brik infra validate"
    End

    It "prints usage and exits 0 for: extension test --help"
      When run script "$BRIK_BIN" extension test --help
      The status should eq 0
      The output should include "Usage: brik extension test"
    End

    It "prints usage and exits 0 for: plan gate --help"
      When run script "$BRIK_BIN" plan gate --help
      The status should eq 0
      The output should include "Usage: brik plan gate"
    End
  End
End

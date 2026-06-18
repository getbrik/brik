#shellcheck shell=bash
# Contract for `brik provider test <id>` (cli.provider, D12 stage 2).
#
# Driven through the real bin/brik dispatcher (end-to-end) so the spec also
# covers the command wiring. Mirrors the style of the extension CLI specs.

Describe "brik provider test"
  BeforeAll '! [[ -f "$BRIK_HOME/lib/registry/cache/registry.json" ]] && "$BRIK_HOME/scripts/compile-registry.sh" >/dev/null 2>&1; true'

  Describe "happy path"
    It "passes for cosign-key (schema + introspection + unit conformance)"
      When run script "$BRIK_BIN" provider test cosign-key
      The status should be success
      The output should include "[OK]   schema"
      The output should include "introspect contract operations present"
      The output should include "unit-conformance cosign: C1 ok"
      The output should include "3 passed, 0 failed"
    End

    It "passes for cosign-kms-openbao (shared cosign module)"
      When run script "$BRIK_BIN" provider test cosign-kms-openbao
      The status should be success
      The output should include "0 failed"
    End

    It "lists the deferred behavioural obligations"
      When run script "$BRIK_BIN" provider test cosign-keyless
      The status should be success
      The output should include "deferred to briklab"
      The output should include "C4 keyless verify"
    End
  End

  Describe "error paths"
    It "fails (CONFIG_ERROR=7) for an unknown provider (C8)"
      When run script "$BRIK_BIN" provider test ghost-signing
      The status should equal 7
      The stderr should include "unknown provider"
    End

    It "rejects a missing provider id (INVALID_INPUT=2)"
      When run script "$BRIK_BIN" provider test
      The status should equal 2
      The stderr should include "requires a provider id"
    End

    It "rejects an unknown subcommand (INVALID_INPUT=2)"
      When run script "$BRIK_BIN" provider frobnicate
      The status should equal 2
      The stderr should include "unknown provider subcommand"
    End

    It "rejects an unknown option (INVALID_INPUT=2)"
      When run script "$BRIK_BIN" provider test --bogus
      The status should equal 2
      The stderr should include "unknown option"
    End
  End

  Describe "help"
    It "prints the provider test usage on --help"
      When run script "$BRIK_BIN" provider --help
      The status should be success
      The output should include "Usage: brik provider test"
    End
  End
End

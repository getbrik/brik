#shellcheck shell=bash
# In-process unit tests for lib/providers/_verify_contract.sh, targeting the
# fail-closed branches the conformance spec does not reach so kcov line coverage
# of providers.verify_contract climbs past 80%.
#
# providers.verify_contract <id> is presence-only introspection: resolve the
# provider -> module + contract from the registry, then assert `declare -f
# providers.<module>.<op>` for every required operation. Any defect is
# fail-closed: CONFIG_ERROR(7) for unknown provider / no module / unknown
# contract / unloadable module / missing op; INVALID_INPUT(2) for empty id.
#
# Stub strategy: the function calls only registry.* accessors, brik.use and
# log.error. We source the module (which sources registry.sh at load time),
# then redefine those helpers in-process to steer each branch. kcov does NOT
# trace subprocesses, so everything is `When call`.

Describe "providers/_verify_contract.sh internals"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_HOME/lib/registry/registry.sh"
  Include "$BRIK_HOME/lib/providers/_verify_contract.sh"

  # Reset the seam helpers after each test so stubs never leak.
  reset_seams() {
    unset -f registry.provider.exists registry.provider.module \
      registry.provider.contract registry.contract.exists \
      registry.contract.operations brik.use 2>/dev/null || true
  }
  AfterEach reset_seams

  Describe "argument validation"
    It "rejects an empty provider id (INVALID_INPUT=2, lines 37-39)"
      When call providers.verify_contract ""
      The status should equal "$BRIK_EXIT_INVALID_INPUT"
      The stderr should include "provider id required"
    End
  End

  Describe "unknown provider"
    It "fails CONFIG_ERROR=7 when the provider does not exist (lines 42-44)"
      stub() { registry.provider.exists() { return 1; }; providers.verify_contract phantom; }
      When call stub
      The status should equal "$BRIK_EXIT_CONFIG_ERROR"
      The stderr should include "unknown provider: phantom"
    End
  End

  Describe "provider declares no module (lines 51-53)"
    It "fails CONFIG_ERROR=7 when the resolved module is empty"
      stub() {
        registry.provider.exists() { return 0; }
        registry.provider.module() { printf ''; return 0; }
        registry.provider.contract() { printf 'artifact-attestation/v1'; return 0; }
        providers.verify_contract nomodule
      }
      When call stub
      The status should equal "$BRIK_EXIT_CONFIG_ERROR"
      The stderr should include "declares no module"
    End
  End

  Describe "unknown contract (lines 55-57)"
    It "fails CONFIG_ERROR=7 when the referenced contract is unknown"
      stub() {
        registry.provider.exists() { return 0; }
        registry.provider.module() { printf 'cosign'; return 0; }
        registry.provider.contract() { printf 'ghost-contract/v9'; return 0; }
        registry.contract.exists() { return 1; }
        providers.verify_contract weirdprov
      }
      When call stub
      The status should equal "$BRIK_EXIT_CONFIG_ERROR"
      The stderr should include "unknown contract: ghost-contract/v9"
    End
  End

  Describe "module unloadable (lines 60-62)"
    It "fails CONFIG_ERROR=7 when brik.use cannot load providers.<module>"
      stub() {
        registry.provider.exists() { return 0; }
        registry.provider.module() { printf 'doesnotexist'; return 0; }
        registry.provider.contract() { printf 'artifact-attestation/v1'; return 0; }
        registry.contract.exists() { return 0; }
        brik.use() { return 1; }
        providers.verify_contract brokenmod
      }
      When call stub
      The status should equal "$BRIK_EXIT_CONFIG_ERROR"
      The stderr should include "cannot load module providers.doesnotexist"
    End
  End

  Describe "operation loop (lines 66-72)"
    # Drive the loop body with a stubbed module that defines some ops, and an
    # operations stream that includes a blank line (line 67 continue), a present
    # op (line 68 declare -f succeeds) and a missing op (line 69-70 increment).
    setup_loop() {
      registry.provider.exists() { return 0; }
      registry.provider.module() { printf 'fakemod'; return 0; }
      registry.provider.contract() { printf 'fake/v1'; return 0; }
      registry.contract.exists() { return 0; }
      brik.use() { return 0; }
      # Pretend the module exposes only 'available'.
      providers.fakemod.available() { return 0; }
    }
    cleanup_loop() {
      unset -f providers.fakemod.available 2>/dev/null || true
    }
    BeforeEach setup_loop
    AfterEach cleanup_loop

    It "succeeds when every required op is present, skipping blank lines (line 72)"
      stub() {
        registry.contract.operations() { printf '\navailable\n'; }
        providers.verify_contract allpresent
      }
      When call stub
      The status should be success
    End

    It "fails CONFIG_ERROR=7 listing a missing required op (lines 69-70, 74-76)"
      stub() {
        registry.contract.operations() { printf 'available\nsign\n'; }
        providers.verify_contract onemissing
      }
      When call stub
      The status should equal "$BRIK_EXIT_CONFIG_ERROR"
      The stderr should include "missing required operation: sign"
      The stderr should include "does not satisfy"
    End
  End
End

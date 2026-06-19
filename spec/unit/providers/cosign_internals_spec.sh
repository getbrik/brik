#shellcheck shell=bash
# In-process unit tests for lib/providers/cosign.sh, targeting the branches the
# conformance spec does not reach so kcov line coverage of this thin adapter
# module climbs past 80%.
#
# cosign.sh is a thin adapter over transverse.attest: providers.cosign.{available,
# sign,verify} each guard with `brik.use transverse.attest || return $?` then
# forward to attest.<op>. conformance_unit asserts the C1 obligation.
#
# Stub strategy: source the module in-process, then redefine brik.use / attest.*
# / providers.cosign.sign so the function under test exercises exactly the
# branch we want. kcov does NOT trace subprocesses, so everything is `When call`.

Describe "providers/cosign.sh internals"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_HOME/lib/providers/cosign.sh"

  Describe "available/sign/verify forward to transverse.attest"
    # Replace brik.use with a no-op success and stub attest.* so we observe the
    # forwarded arguments and the propagated return code (happy adapter path).
    setup_ok() {
      brik.use() { return 0; }
      attest.available() { printf 'available:%s\n' "$*"; return 0; }
      attest.sign() { printf 'sign:%s\n' "$*"; return 0; }
      attest.verify() { printf 'verify:%s\n' "$*"; return 0; }
    }
    cleanup_ok() {
      unset -f brik.use attest.available attest.sign attest.verify 2>/dev/null || true
    }
    BeforeEach setup_ok
    AfterEach cleanup_ok

    It "available forwards args and returns attest.available rc (line 24)"
      When call providers.cosign.available --probe
      The status should be success
      The output should equal "available:--probe"
    End

    It "sign forwards ref + flags to attest.sign (line 30)"
      When call providers.cosign.sign img@sha256:abc --sbom /dev/null
      The status should be success
      The output should equal "sign:img@sha256:abc --sbom /dev/null"
    End

    It "verify forwards ref to attest.verify (line 37)"
      When call providers.cosign.verify img@sha256:abc --identity re
      The status should be success
      The output should equal "verify:img@sha256:abc --identity re"
    End
  End

  Describe "brik.use failure is propagated (cosign.sh lines 22-23)"
    # When transverse.attest cannot be loaded, each adapter must return the rc
    # from brik.use and never touch attest.*. This is the uncovered guard path.
    setup_fail() {
      brik.use() { return 5; }
    }
    cleanup_fail() { unset -f brik.use 2>/dev/null || true; }
    BeforeEach setup_fail
    AfterEach cleanup_fail

    It "available returns the brik.use rc when transverse.attest is unloadable"
      When call providers.cosign.available
      The status should equal 5
    End

    It "sign returns the brik.use rc when transverse.attest is unloadable"
      When call providers.cosign.sign img@sha256:abc --sbom /dev/null
      The status should equal 5
    End

    It "verify returns the brik.use rc when transverse.attest is unloadable"
      When call providers.cosign.verify img@sha256:abc
      The status should equal 5
    End
  End

  Describe "conformance_unit C1 obligation"
    It "reports C1 ok (rc 0) when sign on a mutable tag is refused with INVALID_INPUT"
      # Stub the guard + sign so sign returns the expected INVALID_INPUT code,
      # driving the happy branch (lines 63-64).
      ok_hook() {
        brik.use() { return 0; }
        providers.cosign.sign() { return "$BRIK_EXIT_INVALID_INPUT"; }
        providers.cosign.conformance_unit
      }
      When call ok_hook
      The status should be success
      The output should include "C1 ok"
    End

    It "reports C1 FAILED (rc 1) when sign does not refuse a mutable tag (lines 59,61)"
      # Stub sign to return 0 (as if it wrongly accepted the mutable tag); the
      # mismatch with BRIK_EXIT_INVALID_INPUT must hit the failure branch.
      fail_hook() {
        brik.use() { return 0; }
        providers.cosign.sign() { return 0; }
        providers.cosign.conformance_unit
      }
      When call fail_hook
      The status should equal 1
      The output should include "C1 FAILED"
      The output should include "INVALID_INPUT"
    End

    It "propagates the brik.use rc when transverse.attest is unloadable (line 53)"
      guarded_hook() {
        brik.use() { return 6; }
        providers.cosign.conformance_unit
      }
      When call guarded_hook
      The status should equal 6
    End
  End
End

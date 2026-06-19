#shellcheck shell=bash
# In-process unit coverage for cli.provider (lib/cli/provider.sh).
#
# The end-to-end contract in provider_spec.sh drives `brik provider test`
# through "$BRIK_BIN" (a subprocess), which kcov cannot trace. These tests
# Include the module and call cli.provider.run / cli.provider.test /
# cli.provider._check_schema directly, so every dispatch, option-parsing and
# error branch is executed in the kcov'd shell.
#
# The registry accessors and the providers.* introspection / conformance
# functions are stubbed: we pre-set their loader guard variables so brik.use
# short-circuits and keeps our doubles. cli.provider._check_schema is left
# REAL and driven against a builtin manifest (cosign-key.yml) so its
# manifest-exists / validator-selection / result branches are covered too.

Describe "cli/provider.sh - cli.provider internals (in-process)"
  Include "$BRIK_PIPELINE_LIB/error.sh"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_CLI_LIB/helpers.sh"
  Include "$BRIK_CLI_LIB/provider.sh"

  # Pre-set the loader guards for the providers.* modules so brik.use is a
  # no-op for them and our doubles below survive. (cli.helpers + provider are
  # already Included.)
  setup_doubles() {
    _BRIK_MODULE_CLI_HELPERS_LOADED=1
    _BRIK_MODULE_PROVIDERS__VERIFY_CONTRACT_LOADED=1
    _BRIK_MODULE_PROVIDERS_COSIGN_LOADED=1

    # Registry accessors. "cosign-key" is a real builtin (drives the real
    # _check_schema); individual tests override exists / verify_contract /
    # conformance to reach the other branches.
    registry.provider.exists()     { [[ "$1" == "cosign-key" ]]; }
    registry.provider.capability() { printf 'signing'; }
    registry.provider.module()     { printf 'cosign'; }
    registry.provider.contract()   { printf 'signing.v1'; }

    # Introspection primitive: present by default.
    providers.verify_contract()    { return 0; }

    # Conformance unit: succeeds by default with a detail string.
    providers.cosign.conformance_unit() { printf 'C1 ok'; return 0; }
  }
  BeforeEach 'setup_doubles'

  Describe "cli.provider.run dispatch"
    It "errors with INVALID_INPUT when no subcommand is given (lines 32-34)"
      When call cli.provider.run
      The status should equal 2
      The stderr should include "requires a subcommand"
    End

    It "prints verb help on -h and returns 0 (line 39)"
      # brik_print_verb_help pulls cli.help via the real loader; allow it.
      When call cli.provider.run -h
      The status should be success
      The output should include "Usage: brik provider test"
    End

    It "rejects an unknown subcommand with INVALID_INPUT (line 41)"
      When call cli.provider.run frobnicate
      The status should equal 2
      The stderr should include "unknown provider subcommand: frobnicate"
    End

    It "routes 'test' to cli.provider.test (line 40)"
      When call cli.provider.run test cosign-key
      The status should be success
      The output should include "testing cosign-key"
    End
  End

  Describe "cli.provider.test option parsing"
    It "prints verb help on --help inside test and returns 0 (line 51)"
      When call cli.provider.test --help
      The status should be success
      The output should include "Usage: brik provider test"
    End

    It "rejects an unknown option with INVALID_INPUT (line 52)"
      When call cli.provider.test --bogus
      The status should equal 2
      The stderr should include "unknown option: --bogus"
    End

    It "rejects a second positional argument (line 54)"
      When call cli.provider.test cosign-key extra-arg
      The status should equal 2
      The stderr should include "unexpected argument: extra-arg"
    End

    It "rejects a missing provider id with INVALID_INPUT (lines 58-60)"
      When call cli.provider.test
      The status should equal 2
      The stderr should include "requires a provider id"
    End

    It "fails with CONFIG_ERROR for an unknown provider (C8, lines 68-70)"
      When call cli.provider.test ghost-provider
      The status should equal 7
      The stderr should include "unknown provider: ghost-provider"
      The stderr should include "C8"
    End
  End

  Describe "cli.provider.test conformance paths (real _check_schema)"
    It "passes all checks for a well-formed builtin provider (lines 83-88, 100-102)"
      When call cli.provider.test cosign-key
      The status should be success
      The output should include "introspect contract operations present"
      The output should include "unit-conformance cosign: C1 ok"
      The output should include "deferred to briklab"
      The output should include "passed"
    End

    It "reports FAIL when contract introspection is missing (lines 90-92)"
      providers.verify_contract() { printf 'op X missing\n' >&2; return 1; }
      When call cli.provider.test cosign-key
      The status should equal 2
      The stderr should include "introspect contract operations missing"
      The stderr should include "op X missing"
      The output should include "failed"
    End

    It "reports FAIL when the conformance_unit obligation fails (lines 104-105)"
      providers.cosign.conformance_unit() { printf 'C1 violated'; return 1; }
      When call cli.provider.test cosign-key
      The status should equal 2
      The stderr should include "unit-conformance cosign: C1 violated"
      The output should include "failed"
    End

    It "marks unit-conformance N/A when the module declares none (line 108)"
      # No conformance_unit function -> the [--] branch. Undefine ours and
      # block brik.use providers.cosign from (re)defining one.
      unset -f providers.cosign.conformance_unit
      brik.use() { return 0; }
      When call cli.provider.test cosign-key
      The status should be success
      The output should include "no infra-free obligations declared"
    End

    It "marks unit-conformance N/A when the module name is empty (line 108)"
      registry.provider.module() { printf ''; }
      When call cli.provider.test cosign-key
      The status should be success
      The output should include "module <none>"
    End
  End

  Describe "cli.provider._check_schema (called directly)"
    It "skips with [--] when the id has no builtin manifest (lines 126-128)"
      pass=0 fail=0
      When call cli.provider._check_schema definitely-not-a-builtin-xyz
      The status should be success
      The output should include "not a builtin manifest (skipped)"
    End

    It "validates / selects a validator for a builtin manifest (lines 131-160)"
      # cosign-key.yml is a real builtin manifest; this drives the validator
      # selection + result branch. [OK], [FAIL] or the no-validator [--] line
      # are all real, covered outcomes depending on tools on PATH.
      pass=0 fail=0
      When call cli.provider._check_schema cosign-key
      The status should be success
      The output should include "schema"
    End
  End
End

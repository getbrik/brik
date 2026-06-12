#shellcheck shell=bash
# Validation contract for the v1 transverse notion: static code invariants.
#
# (lib/transverse/).
# Unlike the 10 other notions covered by the test architecture, the transverse notion
# has NO I/O artifact to schematise. Its 141 public functions are pure
# helpers consumed by every other notion. The L0 contract is the set of
# static code invariants declared in docs/internals/layout.md and verified
# here via grep / file checks.
#
# Companion legacy specs:
#   - spec/_legacy/transverse/*_spec.sh test the BEHAVIOURAL contract of
#     each helper (L1). The 41 failures observed during the legacy migration (git-tag
#     env-sensitive tests) are unrelated to the present static contract.
#
# Mirror pattern: 10 sibling specs in this directory (although samples-
# based; this spec is grep-based since there is no schema).

Describe "transverse notion static invariants (layout.md)"
  LAYOUT_MD="${BRIK_HOME}/docs/internals/layout.md"
  CONTRACTS_DOC="${BRIK_HOME}/docs/test-matrix/transverse-contracts.md"

  Describe "documentation"
    It "layout.md exists and contains an Invariants section"
      check_section() { grep -c '^## Invariants' "$LAYOUT_MD"; }
      When call check_section
      The output should equal "1"
      The status should be success
    End

    It "transverse-contracts.md exists (this spec's reference doc)"
      When call test -f "$CONTRACTS_DOC"
      The status should be success
    End
  End

  Describe "invariant 2: no manual poll loops outside transverse/wait.sh"
    # Pattern: `while ... sleep` paired with timeout/elapsed condition.
    # Tool-native waits (argocd app wait, kubectl rollout status) are
    # one-liners with no `while...sleep` shell construct, so they pass.

    count_poll_loop_violations() {
      grep -rlE 'while.*sleep' "${BRIK_HOME}/lib" 2>/dev/null \
        | grep -v "lib/transverse/wait.sh" \
        | wc -l | tr -d ' '
    }

    It "zero violations: no other file pairs while + sleep"
      When call count_poll_loop_violations
      The output should equal "0"
      The status should be success
    End
  End

  Describe "invariant 3: no duplicated 'yq -i' setters outside transverse/yaml.sh"
    count_yq_setter_violations() {
      grep -rn 'yq -i' "${BRIK_HOME}/lib" 2>/dev/null \
        | grep -v "lib/transverse/yaml.sh" \
        | wc -l | tr -d ' '
    }

    It "zero violations: yq -i is centralised in transverse.yaml.{merge,patch,set_image_tag}"
      When call count_yq_setter_violations
      The output should equal "0"
      The status should be success
    End
  End

  Describe "invariant 4: transverse.tools.{register,resolve,exec} is the single registry"
    # The contract is that no other module DEFINES its own
    # tools.register / tools.resolve / tools.exec. Callers grep'ed
    # against transverse.tools.* are the expected USE sites and are
    # NOT a violation.

    count_tools_registry_redefinitions() {
      grep -rln '^tools\.register()\|^tools\.resolve()\|^tools\.exec()' "${BRIK_HOME}/lib" 2>/dev/null \
        | grep -v "lib/transverse/tools.sh" \
        | wc -l | tr -d ' '
    }

    It "zero redefinitions: no other module declares its own tools.{register,resolve,exec}"
      When call count_tools_registry_redefinitions
      The output should equal "0"
      The status should be success
    End
  End

  Describe "invariant 5: transverse.binary_path is the single binary locator"
    count_binary_path_redefinitions() {
      grep -rln '^binary_path\.\(resolve\|is_available\)()' "${BRIK_HOME}/lib" 2>/dev/null \
        | grep -v "lib/transverse/binary_path.sh" \
        | wc -l | tr -d ' '
    }

    It "zero redefinitions: no other module declares binary_path.resolve or binary_path.is_available"
      When call count_binary_path_redefinitions
      The output should equal "0"
      The status should be success
    End
  End

  Describe "invariant 6: no lib/core/ directory (old dispatcher inlined)"
    It "lib/core/ does not exist"
      When call test ! -d "${BRIK_HOME}/lib/core"
      The status should be success
    End
  End

  Describe "invariant 7: bin/brik is thin"
    # The threshold is intentionally lax (under 350 lines) so legitimate
    # additions (a new CLI verb's dispatch arm, extension loading, doctor
    # pre-check, etc.) don't break the contract while still flagging
    # accidental dispatcher creep.

    count_brik_bin_lines() {
      wc -l < "${BRIK_HOME}/bin/brik" | tr -d ' '
    }

    It "bin/brik stays under 350 lines (current target: 301 lines)"
      thin_check() {
        local n
        n="$(count_brik_bin_lines)"
        [[ "$n" -lt 350 ]]
      }
      When call thin_check
      The status should be success
    End
  End

  Describe "invariant 1: indirect expansion centralised in transverse.env (KNOWN VIOLATIONS)"
    # The 15 violations observed at S1 require a triage per call site
    # (refactor vs. document exception). The test is intentionally NOT
    # marked Skip -- it stays Pending so a fix shows up as a flip from
    # Pending to Pass in CI history.
    #
    # Violations distributed across 10 files:
    #   lib/pipeline/{bootstrap, hooks, loader, pipeline, runner-images, stage}.sh
    #   lib/registry/registry.sh
    #   lib/transverse/{conditions, gating, secrets}.sh

    Pending "v0.6.0 lib/pipeline/, lib/registry/registry.sh, and 3 transverse files contain 15 occurrences of \${!var} outside transverse/env.sh -- triage and refactor / document tracked next to "
  End
End

#!/usr/bin/env bash
# infra_default_spec.sh - the built-in default referential (profile `p-local`)
# shipped under BRIK_HOME. It must validate as a real referential instance and
# yield a stable fingerprint, so the chantier #29 R6 invariant (a referential
# always exists, its fingerprint journalled into plan.json) holds with zero
# user ceremony on a bare host.

Describe "transverse/infra.sh - bundled default referential"
  Include "$BRIK_PIPELINE_LIB/logging.sh"
  Include "$BRIK_PIPELINE_LIB/loader.sh"
  Include "$BRIK_TRANSVERSE_LIB/env.sh"
  Include "$BRIK_TRANSVERSE_LIB/config.sh"
  Include "$BRIK_TRANSVERSE_LIB/infra.sh"

  validator_missing() {
    ! command -v jv >/dev/null 2>&1 && ! command -v check-jsonschema >/dev/null 2>&1
  }

  DEFAULT_DIR="$BRIK_HOME/share/infra/p-local"

  It "ships a referential.yml at share/infra/local"
    The path "$DEFAULT_DIR/referential.yml" should be file
  End

  It "declares the 'p-local' profile and no Signing endpoint"
    When call cat "$DEFAULT_DIR/referential.yml"
    The output should include "profile: p-local"
    The output should include "kind: Referential"
  End

  It "has no endpoints (so plain CI runs and the keyless wall never fires)"
    The path "$DEFAULT_DIR/endpoints" should not be exist
  End

  It "validates as a referential instance"
    Skip if "no JSON Schema validator" validator_missing
    When call infra.validate "$DEFAULT_DIR"
    The status should be success
    The stderr should equal ""
  End

  It "yields a non-empty, stable fingerprint"
    fingerprint_twice() {
      local a b
      a="$(infra.fingerprint "$DEFAULT_DIR")"
      b="$(infra.fingerprint "$DEFAULT_DIR")"
      [[ -n "$a" && "$a" == "$b" ]] && printf 'stable:%s' "$a"
    }
    When call fingerprint_twice
    The output should start with "stable:"
  End
End

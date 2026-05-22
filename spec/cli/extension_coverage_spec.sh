Describe "brik extension test (coverage-targeted paths)"
  # Companion to extension_spec.sh. Drives the branches that the happy-path
  # and primary failure suites leave uncovered: the no-subcommand error, the
  # `extension test` argument errors, the validator selection (incl. the
  # check-jsonschema branch and the no-validator error), both [FAIL] schema
  # branches, the missing-yq error, the no-exit grep on a stage module, the
  # compile-registry failure branch, and the dry-call no-symbol path.

  jv_missing() { ! command -v jv >/dev/null 2>&1; }
  cjs_missing() { ! command -v check-jsonschema >/dev/null 2>&1; }

  setup_ext() {
    EXT="$(mktemp -d)"
    mkdir -p "$EXT/stacks" "$EXT/stages" "$EXT/lib/stacks" "$EXT/lib/stages"
  }
  cleanup_ext() {
    rm -rf "$EXT"
  }
  Before 'setup_ext'
  After 'cleanup_ext'

  # A schema-valid stage manifest + matching contract-conformant module.
  write_valid_stage() {
    cat > "$EXT/stages/audit.yml" <<'YAML'
apiVersion: brik.dev/v1
kind: Stage
metadata:
  id: audit
  displayName: Audit
spec:
  module: stages.audit
  function: stages.audit
  placement:
    slot: verify
    after: [build]
    before: [package]
  runner: {class: scanner}
  gate: {mode: blocking, contexts: [snapshot, release]}
  api: {required: [stages.audit]}
YAML
    cat > "$EXT/lib/stages/audit.sh" <<'SH'
stages.audit() {
    report.record "audit" "tech" "status" "success"
    return 0
}
SH
  }

  # A stage manifest that fails schema validation: it omits the mandatory
  # `displayName`, so both jv and check-jsonschema reject it. The api block
  # is well-formed so the schema FAIL is the only failure exercised.
  write_invalid_stage() {
    cat > "$EXT/stages/audit.yml" <<'YAML'
apiVersion: brik.dev/v1
kind: Stage
metadata:
  id: audit
spec:
  module: stages.audit
  function: stages.audit
  placement:
    slot: verify
    after: [build]
    before: [package]
  runner: {class: scanner}
  gate: {mode: blocking, contexts: [snapshot, release]}
  api: {required: [stages.audit]}
YAML
    cat > "$EXT/lib/stages/audit.sh" <<'SH'
stages.audit() {
    report.record "audit" "tech" "status" "success"
    return 0
}
SH
  }

  Describe "run dispatcher: no subcommand"
    It "errors when 'brik extension' is invoked with no subcommand"
      When run script "$BRIK_BIN" extension
      The status should equal 2
      The stderr should include "requires a subcommand"
    End
  End

  Describe "test: argument errors"
    It "rejects an unknown option"
      When run script "$BRIK_BIN" extension test --bogus
      The status should equal 2
      The stderr should include "unknown option: --bogus"
    End

    It "rejects an unexpected extra argument"
      OTHER="$(mktemp -d)"
      When run script "$BRIK_BIN" extension test "$EXT" "$OTHER"
      The status should equal 2
      The stderr should include "unexpected argument:"
      rm -rf "$OTHER"
    End
  End

  # The validator-selection branches need a controlled PATH so exactly one
  # (or neither) of jv / check-jsonschema is visible. The fake bin mirrors
  # every executable currently on PATH -- portable, no hardcoded prefix --
  # so `brik extension test` and compile-registry.sh keep working; the
  # per-Describe setup then removes the validator(s) it wants hidden.
  build_fake_bin() {
    local dst="$1" dir entry base
    local -a dirs
    IFS=: read -ra dirs <<<"$PATH"
    for dir in "${dirs[@]}"; do
      [[ -d "$dir" ]] || continue
      for entry in "$dir"/*; do
        [[ -x "$entry" && ! -d "$entry" ]] || continue
        base="${entry##*/}"
        [[ -e "$dst/$base" ]] || ln -sf "$entry" "$dst/$base"
      done
    done
  }

  Describe "validator selection: check-jsonschema branch"
    setup_cjs() {
      FAKE_BIN="$(mktemp -d)"
      build_fake_bin "$FAKE_BIN"
      # Hide jv so the elif (check-jsonschema) branch is taken.
      rm -f "$FAKE_BIN/jv"
      CJS="$(command -v check-jsonschema 2>/dev/null)"
      [[ -n "$CJS" ]] && ln -sf "$CJS" "$FAKE_BIN/check-jsonschema"
      ORIG_PATH="$PATH"
      PATH="$FAKE_BIN"
    }
    cleanup_cjs() {
      PATH="$ORIG_PATH"
      rm -rf "$FAKE_BIN"
    }
    Before 'setup_cjs'
    After 'cleanup_cjs'

    It "validates a valid manifest via check-jsonschema (jv hidden)"
      Skip if "check-jsonschema not installed" cjs_missing
      write_valid_stage
      When run script "$BRIK_BIN" extension test "$EXT"
      The status should equal 0
      The output should include "[OK]   schema"
    End

    It "reports [FAIL] schema via check-jsonschema on an invalid manifest"
      Skip if "check-jsonschema not installed" cjs_missing
      write_invalid_stage
      When run script "$BRIK_BIN" extension test "$EXT"
      The status should equal 2
      The stderr should include "[FAIL] schema"
      The output should be present
    End
  End

  Describe "validator selection: no validator on PATH"
    setup_noval() {
      FAKE_BIN="$(mktemp -d)"
      build_fake_bin "$FAKE_BIN"
      # Neither jv nor check-jsonschema visible.
      rm -f "$FAKE_BIN/jv" "$FAKE_BIN/check-jsonschema"
      ORIG_PATH="$PATH"
      PATH="$FAKE_BIN"
    }
    cleanup_noval() {
      PATH="$ORIG_PATH"
      rm -rf "$FAKE_BIN"
    }
    Before 'setup_noval'
    After 'cleanup_noval'

    It "errors when no JSON Schema validator is available"
      write_valid_stage
      When run script "$BRIK_BIN" extension test "$EXT"
      The status should equal 3
      The stderr should include "no JSON Schema validator on PATH"
      The output should be present
    End
  End

  Describe "schema validation: jv [FAIL] branch"
    It "reports [FAIL] schema via jv on an invalid manifest"
      Skip if "jv not installed" jv_missing
      write_invalid_stage
      When run script "$BRIK_BIN" extension test "$EXT"
      # The jv branch pipes through sed; under pipefail the failed
      # validation aborts the run before the summary line.
      The status should not equal 0
      The stderr should include "[FAIL] schema"
      The output should be present
    End
  End

  Describe "api.required check: missing yq"
    setup_noyq() {
      FAKE_BIN="$(mktemp -d)"
      build_fake_bin "$FAKE_BIN"
      # Keep a validator so the run reaches the api.required check,
      # but hide yq so that check errors out.
      rm -f "$FAKE_BIN/yq" "$FAKE_BIN/jv"
      CJS="$(command -v check-jsonschema 2>/dev/null)"
      [[ -n "$CJS" ]] && ln -sf "$CJS" "$FAKE_BIN/check-jsonschema"
      ORIG_PATH="$PATH"
      PATH="$FAKE_BIN"
    }
    cleanup_noyq() {
      PATH="$ORIG_PATH"
      rm -rf "$FAKE_BIN"
    }
    Before 'setup_noyq'
    After 'cleanup_noyq'

    It "errors when yq is missing for the api.required check"
      Skip if "check-jsonschema not installed" cjs_missing
      write_valid_stage
      When run script "$BRIK_BIN" extension test "$EXT"
      The status should equal 3
      The stderr should include "yq required"
      The output should be present
    End
  End

  Describe "no-exit check on a stage module"
    It "passes the no-exit check for a clean stage module"
      # A lib/stages/*.sh module with no literal `exit` drives the
      # no-exit grep and lands on the [OK] no-exit branch.
      write_valid_stage
      When run script "$BRIK_BIN" extension test "$EXT"
      The status should equal 0
      The output should include "[OK]   no-exit"
    End
  End

  Describe "compile-registry failure branch"
    It "reports [FAIL] compile registry on a builtin id collision"
      # A stack manifest reusing the builtin id 'node' makes
      # compile-registry.sh abort, exercising the failure branch.
      cat > "$EXT/stacks/node.yml" <<'YAML'
apiVersion: brik.dev/v1
kind: Stack
metadata: {id: node, displayName: Override}
spec:
  detect: {markers: {any: [package.json]}}
  cache: {paths: []}
  runner: {image: x, defaultVersion: "1", versions: ["1"]}
  api: {module: stacks.node, required: [stacks.node.build]}
YAML
      When run script "$BRIK_BIN" extension test "$EXT"
      The status should equal 2
      The stderr should include "[FAIL] compile registry"
      The output should be present
    End
  End

  Describe "dry-call: function not loaded by extension lib/"
    It "fails the dry-call with no-symbol when api.required is absent from lib/"
      # The manifest requires stages.audit but lib/stages/audit.sh only
      # defines a differently-named function, so the dry-call subshell
      # cannot resolve the symbol and reports the no-symbol failure.
      cat > "$EXT/stages/audit.yml" <<'YAML'
apiVersion: brik.dev/v1
kind: Stage
metadata:
  id: audit
  displayName: Audit
spec:
  module: stages.audit
  function: stages.audit
  placement:
    slot: verify
    after: [build]
    before: [package]
  runner: {class: scanner}
  gate: {mode: blocking, contexts: [snapshot, release]}
  api: {required: [stages.audit]}
YAML
      cat > "$EXT/lib/stages/audit.sh" <<'SH'
stages.audit_other() {
    report.record "audit" "tech" "status" "success"
    return 0
}
SH
      When run script "$BRIK_BIN" extension test "$EXT"
      The status should equal 2
      The stderr should include "function not loaded by extension lib/"
      The output should be present
    End
  End
End

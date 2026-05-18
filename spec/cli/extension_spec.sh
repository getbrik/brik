Describe "brik extension test (V.2)"

  setup_ext() {
    EXT="$(mktemp -d)"
    mkdir -p "$EXT/stacks" "$EXT/stages" "$EXT/lib/stacks" "$EXT/lib/stages"
  }
  cleanup_ext() {
    rm -rf "$EXT"
  }
  Before 'setup_ext'
  After 'cleanup_ext'

  write_valid_stack() {
    cat > "$EXT/stacks/myteam.yml" <<'YAML'
apiVersion: brik.dev/v1
kind: Stack
metadata: {id: myteam, displayName: MyTeam}
spec:
  detect: {markers: {any: [myteam.toml]}}
  cache: {paths: []}
  runner: {image: ghcr.io/x, defaultVersion: "1", versions: ["1"]}
  api: {module: stacks.myteam, required: [stacks.myteam.build]}
YAML
    cat > "$EXT/lib/stacks/myteam.sh" <<'SH'
stacks.myteam.build() { return 0; }
SH
  }

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
stages.audit() { return 0; }
SH
  }

  Describe "happy path"
    It "passes when manifest, api and no-exit are correct"
      write_valid_stack
      write_valid_stage
      When run script "$BRIK_BIN" extension test "$EXT"
      The status should equal 0
      The output should include "[OK]   schema"
      The output should include "[OK]   api"
      The output should include "[OK]   no-exit"
      The output should include "[OK]   compile registry merges cleanly"
    End
  End

  Describe "stage with literal exit"
    It "fails the no-exit check"
      write_valid_stage
      cat > "$EXT/lib/stages/audit.sh" <<'SH'
stages.audit() {
    exit 0
}
SH
      When run script "$BRIK_BIN" extension test "$EXT"
      The status should equal 2
      The stderr should include "[FAIL] no-exit"
      The output should be present
    End
  End

  Describe "api.required not implemented"
    It "fails the api check"
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
  api: {required: [stages.audit_missing]}
YAML
      When run script "$BRIK_BIN" extension test "$EXT"
      The status should equal 2
      The stderr should include "stages.audit_missing NOT FOUND"
      The output should be present
    End
  End

  Describe "id collision with builtin"
    It "errors at the compile step"
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
      The stderr should include "compile registry"
      The output should be present
    End
  End

  Describe "usage errors"
    It "errors when no path is provided"
      When run script "$BRIK_BIN" extension test
      The status should equal 2
      The stderr should include "requires an extension directory"
    End

    It "errors when path does not exist"
      When run script "$BRIK_BIN" extension test /nonexistent/path
      The status should equal 2
      The stderr should include "extension dir not found"
    End

    It "rejects unknown subcommand"
      When run script "$BRIK_BIN" extension bogus
      The status should equal 2
      The stderr should include "unknown extension subcommand"
    End
  End
End

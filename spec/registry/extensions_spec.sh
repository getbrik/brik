Describe "registry extensions overlay (D.6)"

  setup_ext() {
    EXT_DIR="$(mktemp -d)"
    OUT_CACHE="$(mktemp)"
    mkdir -p "$EXT_DIR/stacks" "$EXT_DIR/stages"
  }
  cleanup_ext() {
    rm -rf "$EXT_DIR" "$OUT_CACHE"
    unset BRIK_REGISTRY_EXTENSIONS_DIRS
  }
  Before 'setup_ext'
  After 'cleanup_ext'

  Describe "baseline without extensions"
    It "produces the canonical builtin-only cache"
      When run script "$BRIK_HOME/scripts/compile-registry.sh" --output "$OUT_CACHE"
      The status should equal 0
      The output should include "stacks: 6"
      The output should include "stages: 11"
    End
  End

  Describe "with one user-supplied stack manifest"
    write_myteam_stack() {
      cat > "$EXT_DIR/stacks/myteam.yml" <<'YAML'
apiVersion: brik.dev/v1
kind: Stack
metadata:
  id: myteam
  displayName: MyTeam Stack
spec:
  detect: {markers: {any: [myteam.toml]}}
  cache: {paths: [.myteam-cache]}
  runner: {image: ghcr.io/myteam/runner, defaultVersion: "1.0", versions: ["1.0"]}
  api: {module: stacks.myteam, required: [stacks.myteam.build]}
YAML
    }
    compile_with_ext() {
      write_myteam_stack
      BRIK_REGISTRY_EXTENSIONS_DIRS="$EXT_DIR" \
        "$BRIK_HOME/scripts/compile-registry.sh" --output "$OUT_CACHE"
    }

    It "surfaces the custom stack in the compiled cache"
      compile_with_ext >/dev/null 2>&1
      When call jq -r '.stacks.myteam.metadata.id' "$OUT_CACHE"
      The output should equal "myteam"
    End

    It "preserves all builtin stacks alongside the extension"
      compile_with_ext >/dev/null 2>&1
      When call jq -r '.stacks | keys | length' "$OUT_CACHE"
      The output should equal "7"
    End
  End

  Describe "with one user-supplied stage manifest"
    write_audit_stage() {
      cat > "$EXT_DIR/stages/security-audit.yml" <<'YAML'
apiVersion: brik.dev/v1
kind: Stage
metadata:
  id: security-audit
  displayName: Security Audit
spec:
  module: stages.security_audit
  function: stages.security_audit
  placement:
    slot: verify
    group: verify
    after: [build]
    before: [package]
  runner:
    class: scanner
  gate:
    mode: blocking
    contexts: [snapshot, release]
  api:
    required: [stages.security_audit]
YAML
    }
    compile_with_audit() {
      write_audit_stage
      BRIK_REGISTRY_EXTENSIONS_DIRS="$EXT_DIR" \
        "$BRIK_HOME/scripts/compile-registry.sh" --output "$OUT_CACHE"
    }

    It "surfaces the custom stage in the compiled cache"
      compile_with_audit >/dev/null 2>&1
      When call jq -r '.stages["security-audit"].metadata.id' "$OUT_CACHE"
      The output should equal "security-audit"
    End

    It "extends the builtin stage count by one"
      compile_with_audit >/dev/null 2>&1
      When call jq -r '.stages | keys | length' "$OUT_CACHE"
      The output should equal "12"
    End
  End

  Describe "collisions with builtins"
    It "errors when an extension declares a builtin stack id"
      cat > "$EXT_DIR/stacks/node.yml" <<'YAML'
apiVersion: brik.dev/v1
kind: Stack
metadata:
  id: node
  displayName: Override
spec:
  detect: {markers: {any: [package.json]}}
  cache: {paths: []}
  runner: {image: x, defaultVersion: "1", versions: ["1"]}
  api: {module: stacks.node, required: [stacks.node.build]}
YAML
      compile_collision() {
        BRIK_REGISTRY_EXTENSIONS_DIRS="$EXT_DIR" \
          "$BRIK_HOME/scripts/compile-registry.sh" --output "$OUT_CACHE"
      }
      When call compile_collision
      The status should equal 1
      The stderr should include "collision: stacks id=node"
    End
  End

  Describe "missing extension dir"
    It "errors with a clear message"
      compile_missing_dir() {
        BRIK_REGISTRY_EXTENSIONS_DIRS="/nonexistent/path/please/dont/exist" \
          "$BRIK_HOME/scripts/compile-registry.sh" --output "$OUT_CACHE"
      }
      When call compile_missing_dir
      The status should equal 66
      The stderr should include "extension dir not found"
    End
  End
End

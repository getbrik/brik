Describe "extension stack go (L.4 OCP smoke)"
  # Proves that a third-party can add a Go stack without touching the
  # brik core. Mirrors the chantier success criterion: "a new committer
  # Go can do all of this in < 1h following the extension author guide".

  setup() {
    EXT="$(mktemp -d)/.brik-extensions/go"
    OUT="$(mktemp)"
    mkdir -p "$EXT/stacks" "$EXT/lib/stacks"
    cat > "$EXT/stacks/go.yml" <<'YAML'
apiVersion: brik.dev/v1
kind: Stack
metadata:
  id: go
  displayName: Go
spec:
  detect:
    markers:
      any: [go.mod]
  cache:
    paths: [.go-cache]
  runner:
    image: ghcr.io/getbrik/brik-runner-go
    defaultVersion: "1.22"
    versions: ["1.21", "1.22"]
  api:
    module: stacks.go
    required: [stacks.go.build, stacks.go.test]
  impact:
    source:
      - "**/*.go"
      - go.mod
      - go.sum
    test:
      - "**/*_test.go"
    build:
      - go.mod
      - go.sum
YAML
    cat > "$EXT/lib/stacks/go.sh" <<'SH'
stacks.go.build() { (cd "$1" && go build ./...); }
stacks.go.test()  { (cd "$1" && go test ./...); }
SH
  }
  cleanup() {
    rm -rf "$(dirname "$EXT")" "$OUT"
  }
  Before 'setup'
  After 'cleanup'

  It "compiles into the registry alongside builtins"
    BRIK_REGISTRY_EXTENSIONS_DIRS="$(dirname "$EXT")/go" \
      "$BRIK_HOME/scripts/compile-registry.sh" --output "$OUT" >/dev/null 2>&1
    When call jq -r '.stacks.go.metadata.id' "$OUT"
    The output should equal "go"
  End

  It "exposes the runner image declared in the manifest"
    BRIK_REGISTRY_EXTENSIONS_DIRS="$(dirname "$EXT")/go" \
      "$BRIK_HOME/scripts/compile-registry.sh" --output "$OUT" >/dev/null 2>&1
    When call jq -r '.stacks.go.spec.runner.image' "$OUT"
    The output should equal "ghcr.io/getbrik/brik-runner-go"
  End

  It "passes brik extension test end-to-end"
    When run script "$BRIK_BIN" extension test "$(dirname "$EXT")/go"
    The status should equal 0
    The output should include "[OK]   schema"
    The output should include "[OK]   api     stacks/go.yml -> stacks.go.build"
    The output should include "[OK]   api     stacks/go.yml -> stacks.go.test"
    The output should include "[OK]   compile registry merges cleanly"
  End

  It "lets brik plan detect 'go' on a go.mod workspace via overlay"
    REPO="$(mktemp -d)"
    (
      cd "$REPO"
      git init -q -b main
      git config user.email "go@brik.dev"
      git config user.name "go"
      cat > brik.yml <<'YAML'
version: 1
project:
  name: go-demo
YAML
      cat > go.mod <<'MOD'
module example.com/demo

go 1.22
MOD
      git add -A >/dev/null
      git commit -q -m "baseline"
    )
    # Compile a temp overlay cache and feed it via BRIK_REGISTRY_CACHE
    # so the live builtin cache stays untouched.
    OVERLAY_CACHE="$(mktemp)"
    BRIK_REGISTRY_EXTENSIONS_DIRS="$(dirname "$EXT")/go" \
      "$BRIK_HOME/scripts/compile-registry.sh" --output "$OVERLAY_CACHE" >/dev/null 2>&1
    PLAN_OUT="$(mktemp)"
    BRIK_REGISTRY_CACHE="$OVERLAY_CACHE" \
      "$BRIK_BIN" plan --workspace "$REPO" --out "$PLAN_OUT" >/dev/null 2>&1
    detected_stack=$(BRIK_REGISTRY_CACHE="$OVERLAY_CACHE" \
      bash -c '. '"$BRIK_HOME"'/lib/registry/registry.sh; registry.stack.detect "'"$REPO"'"')
    rm -rf "$REPO" "$OVERLAY_CACHE" "$PLAN_OUT"
    When call test "$detected_stack" = "go"
    The status should equal 0
  End
End

Describe "extension stage sbom (L.5 slot insertion smoke)"
  # Proves OCP from the stage side: an extension declares
  # spec.placement.{slot: post-build, after: [build], before: [package]}
  # and the registry's topological sort positions it accordingly.

  setup() {
    EXT="$(mktemp -d)/.brik-extensions/sbom"
    OUT="$(mktemp)"
    mkdir -p "$EXT/stages" "$EXT/lib/stages"
    cat > "$EXT/stages/sbom.yml" <<'YAML'
apiVersion: brik.dev/v1
kind: Stage
metadata:
  id: sbom
  displayName: SBOM
spec:
  module: stages.sbom
  function: stages.sbom
  placement:
    slot: post-build
    group: post-build
    after: [build]
    before: [package]
  runner:
    class: analysis
  gate:
    mode: blocking
    contexts: [snapshot, release]
  consumes: [build.artifact]
  provides: [sbom.report]
  artifacts:
    paths:
      - brik-artifacts/sbom/
  api:
    required: [stages.sbom]
YAML
    cat > "$EXT/lib/stages/sbom.sh" <<'SH'
stages.sbom() {
    # Realistic stub: degrade gracefully when the required tool is
    # absent (the L.5 success criterion explicitly asks for this).
    if ! command -v syft >/dev/null 2>&1; then
        log.warn "sbom: syft not found, skipping SBOM generation (workspace=$1)"
        return 0
    fi
    syft "$1" -o cyclonedx-json > "${BRIK_LOG_DIR:-.brik-logs}/sbom.json"
}
SH
  }
  cleanup() {
    rm -rf "$(dirname "$EXT")" "$OUT"
  }
  Before 'setup'
  After 'cleanup'

  It "compiles the sbom stage into the registry"
    BRIK_REGISTRY_EXTENSIONS_DIRS="$(dirname "$EXT")/sbom" \
      "$BRIK_HOME/scripts/compile-registry.sh" --output "$OUT" >/dev/null 2>&1
    When call jq -r '.stages.sbom.metadata.id' "$OUT"
    The output should equal "sbom"
  End

  It "declares spec.placement.slot=post-build (informational, slot enum honored)"
    BRIK_REGISTRY_EXTENSIONS_DIRS="$(dirname "$EXT")/sbom" \
      "$BRIK_HOME/scripts/compile-registry.sh" --output "$OUT" >/dev/null 2>&1
    When call jq -r '.stages.sbom.spec.placement.slot' "$OUT"
    The output should equal "post-build"
  End

  It "positions sbom between build and package in registry.stage.list"
    BRIK_REGISTRY_EXTENSIONS_DIRS="$(dirname "$EXT")/sbom" \
      "$BRIK_HOME/scripts/compile-registry.sh" --output "$OUT" >/dev/null 2>&1
    ordered=$(BRIK_REGISTRY_CACHE="$OUT" \
      bash -c '. '"$BRIK_HOME"'/lib/registry/registry.sh; registry.stage.list')
    pos_build=$(printf '%s\n' "$ordered" | grep -nx build | cut -d: -f1)
    pos_sbom=$(printf '%s\n' "$ordered" | grep -nx sbom | cut -d: -f1)
    pos_package=$(printf '%s\n' "$ordered" | grep -nx package | cut -d: -f1)
    When call test "$pos_build" -lt "$pos_sbom" -a "$pos_sbom" -lt "$pos_package"
    The status should equal 0
  End

  It "passes brik extension test end-to-end"
    When run script "$BRIK_BIN" extension test "$(dirname "$EXT")/sbom"
    The status should equal 0
    The output should include "[OK]   schema  stages/sbom.yml"
    The output should include "[OK]   api     stages/sbom.yml -> stages.sbom"
    The output should include "[OK]   no-exit lib/stages/sbom.sh"
    The output should include "[OK]   compile registry merges cleanly"
  End

  It "degrades gracefully when the required tool is absent"
    # The stub returns 0 when syft is missing; verify via dry-call.
    out="$(bash -c '. '"$EXT"'/lib/stages/sbom.sh; log.warn() { :; }; stages.sbom "/tmp"; echo "rc=$?"')"
    When call test "$out" = "rc=0"
    The status should equal 0
  End
End

#!/usr/bin/env bash
# Plug-and-play stack discovery: adding a stack manifest to an extension
# dir + recompiling the registry must be enough for brik doctor to
# detect the new stack and probe its declared tools, with no edit to
# lib/ or schemas/.

Describe "brik doctor: plug-and-play stack discovery"

  setup() {
    PNP_DIR="$(mktemp -d)"
    mkdir -p "${PNP_DIR}/ws" "${PNP_DIR}/ext/stacks"
    cat > "${PNP_DIR}/ext/stacks/foo.yml" <<'YAML'
apiVersion: brik.dev/v1
kind: Stack
metadata:
  id: foo
  displayName: Foo
spec:
  detect:
    markers:
      any: [foo.config]
  runner:
    image: registry.example/foo
    defaultVersion: "1"
    versions: ["1"]
  cache:
    paths: [.foo-cache]
  doctor:
    tools: [foo-bin-that-does-not-exist]
  api:
    required: [stacks.foo.build]
YAML
    : > "${PNP_DIR}/ws/foo.config"
    BRIK_REGISTRY_EXTENSIONS_DIRS="${PNP_DIR}/ext" \
      "${BRIK_HOME}/scripts/compile-registry.sh" \
      --output "${PNP_DIR}/cache.json" >/dev/null
    export BRIK_REGISTRY_CACHE="${PNP_DIR}/cache.json"
  }

  cleanup() {
    [[ -n "${PNP_DIR:-}" && -d "${PNP_DIR}" ]] && rm -rf "${PNP_DIR}"
    unset BRIK_REGISTRY_CACHE PNP_DIR
  }

  Before 'setup'
  After 'cleanup'

  It "detects the foo stack from the workspace marker"
    # doctor exits non-zero because foo-bin-that-does-not-exist is missing,
    # not because the stack lookup failed -- pin the exit so shellspec
    # does not flag the non-zero status as an un-asserted surprise.
    When run script "${BRIK_BIN}" doctor --workspace "${PNP_DIR}/ws"
    The status should not eq 0
    The output should include "Detected stack: foo"
  End

  It "probes the doctor.tools list declared by the extension manifest"
    # foo-bin-that-does-not-exist is intentionally not on PATH so doctor
    # reports it as missing. The point of the assertion is that the
    # probe ran at all -- proving doctor reads the extension manifest.
    When run script "${BRIK_BIN}" doctor --workspace "${PNP_DIR}/ws"
    The status should not eq 0
    The output should include "foo-bin-that-does-not-exist"
    The output should include "MISSING"
  End
End

#!/usr/bin/env bash
# Shared helpers for the registry contract test harness.
#
# ADR-002 (Contract testing Bash) pins the registry public API surface
# at the v1 contract. Concrete value tests (e.g. "node has package.json
# as marker") live in spec/registry/registry_spec.sh. This harness adds
# the second layer: BEHAVIOURAL invariants that any registry must
# satisfy regardless of which manifests are loaded.
#
# Two contract scenarios are exercised by the specs in this directory:
#
#   1. builtin-only:     no extensions loaded, only lib/registry/manifests/*
#   2. builtin+extension: builtin set plus one synthetic stack + one stage
#
# Each scenario goes through contract.scenario.setup which:
#   - mktemps a manifest dir,
#   - drops synthetic manifests in stacks/<id>.yml / stages/<id>.yml,
#   - runs scripts/compile-registry.sh against it,
#   - sets BRIK_REGISTRY_CACHE so the next registry.use reads it.

# Write a syntactically valid synthetic stack manifest.
# Args: $1 = stack id (kebab-case), $2 = target file path.
contract.write_stack() {
    local id="$1" path="$2"
    cat > "$path" <<YAML
apiVersion: brik.dev/v1
kind: Stack
metadata:
  id: ${id}
  displayName: ${id}-display
  owner: contract-test
spec:
  detect:
    markers:
      any: [${id}.toml]
  runner:
    image: registry.example/${id}
    defaultVersion: "1"
    versions: ["1"]
  cache:
    paths: [.${id}-cache]
  impact:
    source: ["**/*.${id}"]
    test:   ["**/*.spec.${id}"]
    build:  [${id}.toml]
  api:
    required:
      - stacks.${id}.build
      - stacks.${id}.test
YAML
}

# Write a syntactically valid synthetic stage manifest.
# Args: $1 = stage id, $2 = target file path, $3 (optional) = after-stage id.
contract.write_stage() {
    local id="$1" path="$2" after="${3:-init}"
    cat > "$path" <<YAML
apiVersion: brik.dev/v1
kind: Stage
metadata:
  id: ${id}
  displayName: ${id}-display
spec:
  module: stages.${id}
  function: stages.${id}
  placement:
    slot: ${id}
    after: [${after}]
  runner:
    class: base
  gate:
    mode: always
  api:
    required: [stages.${id}]
YAML
}

# Build a contract scenario.
#
# Args: $1 = scenario name ("builtin-only" | "builtin+extension")
#
# Side effects (exported):
#   - BRIK_REGISTRY_CACHE points at a fresh compiled cache,
#   - CONTRACT_EXT_DIR is the extension manifest dir (when applicable),
#   - CONTRACT_STACK_ID / CONTRACT_STAGE_ID hold the synthetic ids.
contract.scenario.setup() {
    local name="$1"
    CONTRACT_EXT_DIR="$(mktemp -d)"
    CONTRACT_STACK_ID="contract-stack"
    CONTRACT_STAGE_ID="contract-stage"
    BRIK_REGISTRY_CACHE="$(mktemp)"

    case "$name" in
        builtin-only)
            unset BRIK_REGISTRY_EXTENSIONS_DIRS
            "${BRIK_HOME}/scripts/compile-registry.sh" \
                --output "$BRIK_REGISTRY_CACHE" >/dev/null
            ;;
        builtin+extension)
            mkdir -p "$CONTRACT_EXT_DIR/stacks" "$CONTRACT_EXT_DIR/stages"
            contract.write_stack "$CONTRACT_STACK_ID" \
                "$CONTRACT_EXT_DIR/stacks/${CONTRACT_STACK_ID}.yml"
            contract.write_stage "$CONTRACT_STAGE_ID" \
                "$CONTRACT_EXT_DIR/stages/${CONTRACT_STAGE_ID}.yml"
            BRIK_REGISTRY_EXTENSIONS_DIRS="$CONTRACT_EXT_DIR" \
                "${BRIK_HOME}/scripts/compile-registry.sh" \
                --output "$BRIK_REGISTRY_CACHE" >/dev/null
            ;;
        *)
            echo "contract.scenario.setup: unknown scenario '$name'" >&2
            return 1
            ;;
    esac

    export BRIK_REGISTRY_CACHE CONTRACT_EXT_DIR
    export CONTRACT_STACK_ID CONTRACT_STAGE_ID

    if declare -f _registry._reset >/dev/null 2>&1; then
        _registry._reset
    fi
    registry.use
}

contract.scenario.teardown() {
    [[ -n "${CONTRACT_EXT_DIR:-}" && -d "$CONTRACT_EXT_DIR" ]] && rm -rf "$CONTRACT_EXT_DIR"
    [[ -n "${BRIK_REGISTRY_CACHE:-}" && -f "$BRIK_REGISTRY_CACHE" ]] && rm -f "$BRIK_REGISTRY_CACHE"
    unset BRIK_REGISTRY_CACHE BRIK_REGISTRY_EXTENSIONS_DIRS
    unset CONTRACT_EXT_DIR CONTRACT_STACK_ID CONTRACT_STAGE_ID
    if declare -f _registry._reset >/dev/null 2>&1; then
        _registry._reset
    fi
}

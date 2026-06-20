#!/usr/bin/env bash
# @module cli.provider
# @description CLI entrypoint for `brik provider test <id>` (unit
#   conformance). Proves, without real infrastructure, that a provider
#   satisfies its capability contract:
#
#   1. The provider exists in the registry (unknown id -> CONFIG_ERROR).
#   2. Its builtin manifest validates against
#      schemas/registry/v1/provider.schema.json.
#   3. Runtime introspection: providers.verify_contract proves the module
#      exposes every operation the contract requires (presence-only).
#   4. Capability unit conformance: if the provider module declares
#      providers.<module>.conformance_unit, run its infra-free obligations
#      (cosign: C1 -- signing a mutable tag is refused with INVALID_INPUT).
#   5. List the obligations DEFERRED to behavioural conformance (briklab,
#      stage 3): C2/C3/C5/C7, plus C4 (proven by the conformance spec with a
#      keyless fixture, not a live referential).
#
# Mirrors cli.extension.test: [OK]/[FAIL] lines, pass/fail counters, returns
# BRIK_EXIT_INVALID_INPUT when any check fails. The harness itself is
# capability-agnostic; capability-specific vectors live in the provider
# module, never here -- so the artifact-attestation pilot does not freeze its
# semantics into the framework.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_PROVIDER_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_PROVIDER_LOADED=1

cli.provider.run() {
    brik.use cli.helpers

    if [[ $# -eq 0 ]]; then
        brik_error "'brik provider' requires a subcommand. Usage: brik provider test <id>"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi

    local subcmd="$1"; shift
    case "$subcmd" in
        -h|--help) brik_print_verb_help "provider test"; return 0 ;;
        test) cli.provider.test "$@" ;;
        *) brik_usage_error "unknown provider subcommand: $subcmd" || return "$?" ;;
    esac
}

cli.provider.test() {
    brik.use cli.helpers

    local provider_id=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) brik_print_verb_help "provider test"; return 0 ;;
            -*) brik_usage_error "unknown option: $1" || return "$?" ;;
            *)  if [[ -z "$provider_id" ]]; then provider_id="$1"; shift
                else brik_usage_error "unexpected argument: $1" || return "$?"; fi ;;
        esac
    done

    if [[ -z "$provider_id" ]]; then
        brik_error "'brik provider test' requires a provider id"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi

    # Registry accessors + the introspection primitive.
    brik.use providers._verify_contract

    # C8: an unknown provider is a configuration error, surfaced before any
    # other check (nothing downstream can resolve).
    if ! registry.provider.exists "$provider_id"; then
        brik_error "unknown provider: ${provider_id} (CONFIG_ERROR; obligation C8)"
        return "${BRIK_EXIT_CONFIG_ERROR}"
    fi

    local capability module contract
    capability="$(registry.provider.capability "$provider_id")"
    module="$(registry.provider.module "$provider_id")"
    contract="$(registry.provider.contract "$provider_id")"

    local pass=0 fail=0
    printf '[brik provider] testing %s (capability=%s, module=%s, contract=%s)\n' \
        "$provider_id" "$capability" "${module:-<none>}" "${contract:-<none>}"

    # --- Check 1: manifest schema ---
    cli.provider._check_schema "$provider_id"

    # --- Check 2: runtime introspection (presence of contract operations) ---
    if providers.verify_contract "$provider_id" 2>/dev/null; then
        printf '  [OK]   introspect contract operations present (%s)\n' "$contract"
        pass=$((pass + 1))
    else
        printf '  [FAIL] introspect contract operations missing\n' >&2
        providers.verify_contract "$provider_id" 2>&1 1>/dev/null | sed 's/^/         /' >&2
        fail=$((fail + 1))
    fi

    # --- Check 3: capability unit conformance (infra-free obligations) ---
    if [[ -n "$module" ]] && brik.use "providers.${module}" 2>/dev/null \
       && declare -f "providers.${module}.conformance_unit" >/dev/null 2>&1; then
        local detail rc
        detail="$("providers.${module}.conformance_unit" 2>&1)"; rc=$?
        if [[ "$rc" -eq 0 ]]; then
            printf '  [OK]   unit-conformance %s: %s\n' "$module" "$detail"
            pass=$((pass + 1))
        else
            printf '  [FAIL] unit-conformance %s: %s\n' "$module" "$detail" >&2
            fail=$((fail + 1))
        fi
    else
        printf '  [--]   unit-conformance no infra-free obligations declared for module %s\n' "${module:-<none>}"
    fi

    # --- Deferred obligations (behavioural conformance, briklab stage 3) ---
    printf '  [..]   deferred to briklab (real infra): C2 fail-closed verify, C3 sign/verify round-trip, C5 key confinement, C7 no-secret-argv\n'
    printf '  [..]   deferred to conformance spec (keyless fixture): C4 keyless verify without identity/issuer -> INVALID_INPUT\n'

    printf '\n[brik provider] %d passed, %d failed\n' "$pass" "$fail"
    [[ "$fail" -gt 0 ]] && return "${BRIK_EXIT_INVALID_INPUT}"
    return 0
}

# Validate the provider's builtin manifest against the provider schema.
cli.provider._check_schema() {
    local id="$1"
    local manifest="${BRIK_HOME}/lib/registry/manifests/providers/${id}.yml"
    local schema="${BRIK_HOME}/schemas/registry/v1/provider.schema.json"

    if [[ ! -f "$manifest" ]]; then
        printf '  [--]   schema     %s.yml not a builtin manifest (skipped)\n' "$id"
        return 0
    fi

    local validator=""
    if command -v jv >/dev/null 2>&1; then validator="jv"
    elif command -v check-jsonschema >/dev/null 2>&1; then validator="check-jsonschema"
    else
        printf '  [--]   schema     no JSON Schema validator on PATH (jv/check-jsonschema); skipped\n'
        return 0
    fi

    local ok=1
    if [[ "$validator" == "jv" ]]; then
        # jv reads YAML directly; fall back to a yq->json tempfile if needed.
        if command -v yq >/dev/null 2>&1; then
            local _tmpd instance
            _tmpd="$(mktemp -d)"; instance="$_tmpd/instance.json"
            yq -o=json '.' "$manifest" > "$instance" 2>/dev/null \
                && jv "$schema" "$instance" >/dev/null 2>&1 || ok=0
            rm -rf "$_tmpd"
        else
            jv "$schema" "$manifest" >/dev/null 2>&1 || ok=0
        fi
    else
        check-jsonschema --schemafile "$schema" "$manifest" >/dev/null 2>&1 || ok=0
    fi

    if [[ "$ok" -eq 1 ]]; then
        printf '  [OK]   schema     providers/%s.yml\n' "$id"
        pass=$((pass + 1))
    else
        printf '  [FAIL] schema     providers/%s.yml\n' "$id" >&2
        fail=$((fail + 1))
    fi
}

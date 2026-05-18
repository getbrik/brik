#!/usr/bin/env bash
# @module cli.extension
# @description CLI entrypoint for `brik extension test <path>`.
#   Per ADR-002 (contract testing) and chantier V.2, a Brik extension
#   ships a directory with stacks/ and stages/ manifests plus an
#   optional lib/ tree of Bash modules. This command runs the contract
#   harness so an author can verify their extension before publishing.
#
# Checks performed:
#   1. Every <ext>/stacks/*.yml validates against
#      schemas/registry/v1/stack.schema.json.
#   2. Every <ext>/stages/*.yml validates against
#      schemas/registry/v1/stage.schema.json.
#   3. For each manifest, every function listed in spec.api.required is
#      defined somewhere under <ext>/lib/ (or the brik builtin lib/).
#   4. No <ext>/lib/stages/*.sh contains a literal `exit ` (must use
#      `return`). Stages are dispatched via stage.run; calling exit
#      terminates the pipeline orchestrator.
#   5. The manifest set compiles cleanly with
#      BRIK_REGISTRY_EXTENSIONS_DIRS=<ext> (no collision with builtins).

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_EXTENSION_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_EXTENSION_LOADED=1

cli.extension.run() {
    brik.use cli.helpers

    if [[ $# -eq 0 ]]; then
        brik_error "'brik extension' requires a subcommand. Usage: brik extension test <path>"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi

    local subcmd="$1"; shift
    case "$subcmd" in
        test) cli.extension.test "$@" ;;
        *) brik_usage_error "unknown extension subcommand: $subcmd" || return "$?" ;;
    esac
}

cli.extension.test() {
    brik.use cli.helpers

    local ext_dir=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -*) brik_usage_error "unknown option: $1" || return "$?" ;;
            *)  if [[ -z "$ext_dir" ]]; then ext_dir="$1"; shift
                else brik_usage_error "unexpected argument: $1" || return "$?"; fi ;;
        esac
    done

    if [[ -z "$ext_dir" ]]; then
        brik_error "'brik extension test' requires an extension directory"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi
    if [[ ! -d "$ext_dir" ]]; then
        brik_error "extension dir not found: $ext_dir"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi

    local pass=0 fail=0
    local stack_schema="${BRIK_HOME}/schemas/registry/v1/stack.schema.json"
    local stage_schema="${BRIK_HOME}/schemas/registry/v1/stage.schema.json"

    printf '[brik extension] testing %s\n' "$ext_dir"

    local validator=""
    if command -v jv >/dev/null 2>&1; then validator="jv"
    elif command -v check-jsonschema >/dev/null 2>&1; then validator="check-jsonschema"
    else
        brik_error "no JSON Schema validator on PATH (install jv or check-jsonschema)"
        return "${BRIK_EXIT_MISSING_DEP}"
    fi

    cli.extension._validate_kind() {
        local kind="$1" schema="$2"
        local dir="${ext_dir}/${kind}"
        [[ -d "$dir" ]] || return 0
        local f rel
        for f in "$dir"/*.yml; do
            [[ -f "$f" ]] || continue
            rel="${f#"${ext_dir}/"}"
            if [[ "$validator" == "jv" ]]; then
                if jv "$schema" "$f" >/dev/null 2>&1; then
                    printf '  [OK]   schema  %s\n' "$rel"
                    pass=$((pass + 1))
                else
                    printf '  [FAIL] schema  %s\n' "$rel" >&2
                    jv "$schema" "$f" 2>&1 | sed 's/^/         /' >&2
                    fail=$((fail + 1))
                fi
            else
                if check-jsonschema --schemafile "$schema" "$f" >/dev/null 2>&1; then
                    printf '  [OK]   schema  %s\n' "$rel"
                    pass=$((pass + 1))
                else
                    printf '  [FAIL] schema  %s\n' "$rel" >&2
                    fail=$((fail + 1))
                fi
            fi
        done
    }

    cli.extension._validate_kind stacks "$stack_schema"
    cli.extension._validate_kind stages "$stage_schema"

    cli.extension._check_api_required() {
        local f rel ids fn found
        for f in "${ext_dir}/stacks"/*.yml "${ext_dir}/stages"/*.yml; do
            [[ -f "$f" ]] || continue
            rel="${f#"${ext_dir}/"}"
            ids="$(yq -r '.spec.api.required[]?' "$f" 2>/dev/null)"
            [[ -z "$ids" ]] && continue
            while IFS= read -r fn; do
                [[ -z "$fn" ]] && continue
                found=0
                # grep -rE catches both "fn()" and "function fn()" forms.
                local pat="(^|[[:space:]])${fn}[[:space:]]*\("
                if grep -qrE "$pat" "${ext_dir}" 2>/dev/null \
                   || grep -qrE "$pat" "${BRIK_HOME}/lib" 2>/dev/null; then
                    found=1
                fi
                if [[ "$found" -eq 1 ]]; then
                    printf '  [OK]   api     %s -> %s\n' "$rel" "$fn"
                    pass=$((pass + 1))
                else
                    printf '  [FAIL] api     %s -> %s NOT FOUND\n' "$rel" "$fn" >&2
                    fail=$((fail + 1))
                fi
            done <<<"$ids"
        done
    }

    if command -v yq >/dev/null 2>&1; then
        cli.extension._check_api_required
    else
        brik_error "yq required for api.required check"
        return "${BRIK_EXIT_MISSING_DEP}"
    fi

    # No literal `exit ` in stage modules. Stages run inside stage.run
    # which traps non-zero returns; an exit would short-circuit the
    # orchestrator, lose the stage's report fragment, and skip the
    # finally block.
    cli.extension._check_no_exit() {
        local stages_dir="${ext_dir}/lib/stages"
        [[ -d "$stages_dir" ]] || return 0
        local f rel bad
        for f in "$stages_dir"/*.sh; do
            [[ -f "$f" ]] || continue
            rel="${f#"${ext_dir}/"}"
            # grep exits 1 when it finds nothing; that's the success case
            # for "no-exit", so swallow it under errexit.
            bad="$( { grep -nE '(^|[[:space:]])exit([[:space:]]|$)' "$f" 2>/dev/null \
                | grep -vE '^[[:space:]]*[0-9]+:[[:space:]]*#' \
                | head -1; } || true)"
            if [[ -n "$bad" ]]; then
                printf '  [FAIL] no-exit %s: %s\n' "$rel" "$bad" >&2
                fail=$((fail + 1))
            else
                printf '  [OK]   no-exit %s\n' "$rel"
                pass=$((pass + 1))
            fi
        done
    }
    cli.extension._check_no_exit

    cli.extension._check_compile() {
        local out
        out="$(mktemp -t brik-ext-cache.XXXXXX)"
        local err
        if err="$(BRIK_REGISTRY_EXTENSIONS_DIRS="$ext_dir" \
                 "${BRIK_HOME}/scripts/compile-registry.sh" --output "$out" 2>&1)"; then
            printf '  [OK]   compile registry merges cleanly\n'
            pass=$((pass + 1))
        else
            printf '  [FAIL] compile registry: %s\n' "$err" >&2
            fail=$((fail + 1))
        fi
        rm -f "$out"
    }
    cli.extension._check_compile

    printf '\n[brik extension] %d passed, %d failed\n' "$pass" "$fail"
    [[ "$fail" -gt 0 ]] && return "${BRIK_EXIT_INVALID_INPUT}"
    return 0
}

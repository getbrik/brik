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

    # Dry-call (ADR-002 mécanisme 1 critère 3). For each function listed
    # in spec.api.required, source the extension's lib/*.sh in a subshell
    # with a stub report.record + log.* (so the call is observable and
    # silent), invoke the function with a minimal workspace fixture, and
    # check rc=0 plus at least one report.record entry landed.
    #
    # The fixture is intentionally minimal: a tempdir workspace with
    # brik.yml + the manifest's first detect marker (if a stack) or no
    # extra file (if a stage). Side-effect tools (npm, mvn, ...) are
    # masked off PATH so a stack-build wrapper degrades to the report
    # contract check rather than launching a real build.
    cli.extension._check_dry_call() {
        local f rel ids fn marker
        for f in "${ext_dir}/stacks"/*.yml "${ext_dir}/stages"/*.yml; do
            [[ -f "$f" ]] || continue
            rel="${f#"${ext_dir}/"}"
            ids="$(yq -r '.spec.api.required[]?' "$f" 2>/dev/null || true)"
            [[ -z "$ids" ]] && continue
            marker=""
            if [[ "$rel" == stacks/* ]]; then
                marker="$(yq -r '.spec.detect.markers.any[0] // ""' "$f" 2>/dev/null || true)"
            fi
            while IFS= read -r fn; do
                [[ -z "$fn" ]] && continue
                cli.extension._dry_call_one "$rel" "$fn" "$marker"
            done <<<"$ids"
        done
    }

    cli.extension._dry_call_one() {
        local manifest_rel="$1" fn="$2" marker="$3"
        local ext_lib_root="${ext_dir}/lib"
        local ws record_log out
        ws="$(mktemp -d -t brik-ext-dry.XXXXXX)"
        record_log="$(mktemp -t brik-ext-record.XXXXXX)"
        printf 'version: 1\nproject:\n  name: %s\n' "ext-dry" > "$ws/brik.yml"
        [[ -n "$marker" && "$marker" != *"*"* ]] && : > "$ws/$marker"

        # The dry-call subshell keeps stubbed report.record + log.* in
        # scope, sources every .sh under <ext>/lib/ (so api.required
        # symbols become available regardless of file layout), then
        # invokes the function with a clean PATH (mktemp+coreutils only).
        # `|| true` keeps `set -e` from short-circuiting when the
        # subshell exits with no-symbol (rc=1). We rely on the textual
        # output (`no-symbol` vs `rc=<n>`) to decide pass/fail, not on
        # the subshell rc itself.
        out="$(BRIK_WORKSPACE="$ws" \
               BRIK_CONFIG_FILE="$ws/brik.yml" \
               BRIK_EXT_RECORD_LOG="$record_log" \
               PATH="/usr/bin:/bin" \
            bash -c '
                set +e
                shopt -s globstar nullglob
                report.record() { printf "%s\t%s\t%s\t%s\n" "${1-}" "${2-}" "${3-}" "${4-}" >> "$BRIK_EXT_RECORD_LOG"; }
                log.info()  { :; }
                log.warn()  { :; }
                log.error() { :; }
                log.debug() { :; }
                for f in "$1"/**/*.sh "$1"/*.sh; do
                    [[ -f "$f" ]] && . "$f" 2>/dev/null
                done
                if ! declare -f "$2" >/dev/null 2>&1; then
                    printf "no-symbol\n"
                    exit 1
                fi
                "$2" >/dev/null 2>&1
                printf "rc=%s\n" "$?"
            ' _ "$ext_lib_root" "$fn" 2>&1)" || true
        rm -rf "$ws"

        local record_lines=0
        [[ -s "$record_log" ]] && record_lines="$(wc -l <"$record_log" | tr -d ' ')"
        rm -f "$record_log"

        if [[ "$out" == *"no-symbol"* ]]; then
            printf '  [FAIL] dry-call %s -> %s: function not loaded by extension lib/\n' \
                "$manifest_rel" "$fn" >&2
            fail=$((fail + 1))
            return
        fi
        # Strip everything up to the last "rc=" so the rc capture is
        # robust to extra stderr from sourcing.
        local rc_line="${out##*rc=}"
        local call_rc="${rc_line%%[!0-9]*}"
        [[ -z "$call_rc" ]] && call_rc=99
        if [[ "$call_rc" -ne 0 ]]; then
            printf '  [FAIL] dry-call %s -> %s: rc=%s on happy-path fixture\n' \
                "$manifest_rel" "$fn" "$call_rc" >&2
            fail=$((fail + 1))
            return
        fi
        if [[ "$record_lines" -eq 0 ]]; then
            printf '  [FAIL] dry-call %s -> %s: no report.record entry on happy-path\n' \
                "$manifest_rel" "$fn" >&2
            fail=$((fail + 1))
            return
        fi
        printf '  [OK]   dry-call %s -> %s (rc=0, %s record entries)\n' \
            "$manifest_rel" "$fn" "$record_lines"
        pass=$((pass + 1))
    }

    if [[ -d "${ext_dir}/lib" ]]; then
        cli.extension._check_dry_call
    fi

    printf '\n[brik extension] %d passed, %d failed\n' "$pass" "$fail"
    [[ "$fail" -gt 0 ]] && return "${BRIK_EXIT_INVALID_INPUT}"
    return 0
}

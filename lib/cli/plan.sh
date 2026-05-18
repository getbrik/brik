#!/usr/bin/env bash
# @module cli.plan
# @description CLI entrypoint for "brik plan". Computes the per-stage
#   selection plan and writes it as plan.json (default
#   ${BRIK_WORKSPACE}/.brik-logs/plan.json).
#
# Supported flags:
#   --workspace <d>     workspace root (default $PWD)
#   --mode <m>          safe (default) | balanced | aggressive
#   --out <path>        write plan.json to <path> instead of the default
#   --explain           print a human-readable summary to stdout (no file)
#   --validate-only     compute the plan and validate it against the schema
#   --format <fmt>      reserved (gitlab-child lands in D.5c)
#   --with-release|--with-package|--with-deploy   opt-in gates

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_PLAN_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_PLAN_LOADED=1

cli.plan.run() {
    brik.use cli.helpers
    brik.use planning.plan_writer
    brik.use planning.plan_reader

    # Sub-command dispatch. The default sub-command "compute" is implicit
    # (no first arg) for backward compat with the v0.6 contract documented
    # in D.4.7. The "gate" sub-command was added in D.5b to support
    # adapters that orchestrate stages outside of pipeline.run (Jenkins
    # Groovy, GitLab YAML); it returns 0=run, 1=skip and records the
    # skip fragment so the aggregate-report still sees the stage.
    if [[ $# -gt 0 ]]; then
        case "$1" in
            gate) shift; cli.plan.gate "$@"; return $? ;;
        esac
    fi

    local workspace="${BRIK_WORKSPACE:-$PWD}"
    local mode=""
    local out="" explain=false validate_only=false format=""
    local with_release=false with_package=false with_deploy=false
    local -a passthrough=()
    local mode_from_cli=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --workspace) brik_require_arg "--workspace" "${2-}" || return "$?"
                         workspace="$2"; shift 2 ;;
            --mode)      brik_require_arg "--mode" "${2-}" || return "$?"
                         mode="$2"; mode_from_cli=true; shift 2 ;;
            --out)       brik_require_arg "--out" "${2-}" || return "$?"
                         out="$2"; shift 2 ;;
            --explain)         explain=true; shift ;;
            --validate-only)   validate_only=true; shift ;;
            --format)    brik_require_arg "--format" "${2-}" || return "$?"
                         format="$2"; shift 2 ;;
            --with-release)    with_release=true; shift ;;
            --with-package)    with_package=true; shift ;;
            --with-deploy)     with_deploy=true; shift ;;
            *) brik_usage_error "unknown option: $1" || return "$?" ;;
        esac
    done

    # When --mode is not given, read pipeline.selection.mode from the
    # project's brik.yml via config.get. This makes the schema leaf
    # .pipeline.selection.mode a concrete runtime consumer (drift detector
    # matches the literal path inside config.get). The per-stage override
    # map .pipeline.selection.stages is also consulted; v0.6 does not yet
    # merge those into the manifest globs (planned in a later sprint).
    if [[ "$mode_from_cli" == "false" ]]; then
        brik.use transverse.config
        local _cfg="${workspace}/brik.yml"
        if [[ -f "$_cfg" ]]; then
            BRIK_CONFIG_FILE="$_cfg" mode="$(config.get '.pipeline.selection.mode' 'safe' 2>/dev/null || printf 'safe')"
            BRIK_CONFIG_FILE="$_cfg" config.get '.pipeline.selection.stages' '' >/dev/null 2>&1 || true
        fi
        [[ -z "$mode" ]] && mode="safe"
    fi

    # --format=gitlab-child is documented to land in D.5c (GitLab child
    # pipeline emission). Emit a clear, exit-coded error so users don't
    # interpret silence as success.
    if [[ -n "$format" && "$format" != "json" ]]; then
        printf '[brik plan] --format=%s is reserved for D.5c (not yet implemented in v0.6)\n' \
            "$format" >&2
        return "${BRIK_EXIT_INVALID_INPUT:-64}"
    fi

    passthrough+=(--workspace "$workspace" --mode "$mode")
    $with_release && passthrough+=(--with-release)
    $with_package && passthrough+=(--with-package)
    $with_deploy  && passthrough+=(--with-deploy)

    if [[ -z "$out" && "$explain" == "false" && "$validate_only" == "false" ]]; then
        out="${workspace}/.brik-logs/plan.json"
    fi

    local tmp_json
    tmp_json="$(mktemp -t brik-plan-out.XXXXXX)"

    if ! plan_writer.write -- "${passthrough[@]}" >"$tmp_json"; then
        rm -f "$tmp_json"
        return "${BRIK_EXIT_INVALID_INPUT:-64}"
    fi

    if [[ "$validate_only" == "true" ]]; then
        local schema="${BRIK_HOME}/schemas/plan/v1/plan.schema.json"
        if command -v jv >/dev/null 2>&1; then
            if jv "$schema" "$tmp_json" >/dev/null 2>&1; then
                rm -f "$tmp_json"
                printf 'plan.json: valid against schema\n'
                return 0
            else
                jv "$schema" "$tmp_json" >&2 || true
                rm -f "$tmp_json"
                printf 'plan.json: schema validation failed\n' >&2
                return "${BRIK_EXIT_INVALID_INPUT:-64}"
            fi
        elif command -v check-jsonschema >/dev/null 2>&1; then
            if check-jsonschema --schemafile "$schema" "$tmp_json" >/dev/null 2>&1; then
                rm -f "$tmp_json"
                printf 'plan.json: valid against schema\n'
                return 0
            else
                rm -f "$tmp_json"
                return "${BRIK_EXIT_INVALID_INPUT:-64}"
            fi
        else
            rm -f "$tmp_json"
            printf '[brik plan] no JSON Schema validator available (install jv or check-jsonschema)\n' >&2
            return "${BRIK_EXIT_MISSING_DEP:-69}"
        fi
    fi

    if [[ "$explain" == "true" ]]; then
        cli.plan._render_explain "$tmp_json"
        rm -f "$tmp_json"
        return 0
    fi

    if [[ -n "$out" ]]; then
        mkdir -p "$(dirname "$out")"
        mv "$tmp_json" "$out"
        printf 'plan: %s\n' "$out"
    else
        cat "$tmp_json"
        rm -f "$tmp_json"
    fi
    return 0
}

# Gate sub-command: decide run|skip for <stage_id> against the active plan.
#
# Returns:
#   0 -> stage should run (caller proceeds with brik run stage <id>)
#   1 -> stage should skip; this function has already written a per-stage
#        fragment to the report with tech.status=skipped, tech.kind=
#        not-applicable, business.reason=<plan reason>, so the aggregate
#        still shows the stage as a deliberate skip.
#   2  -> usage error (no stage id, missing plan when --strict)
#
# When BRIK_PLAN_FILE is unset or empty, the gate returns 0 (run) so a
# pre-D.4 setup or a misconfigured CI still behaves like v0.5.x.
# Pass --strict to error out on a missing plan instead (callers that
# *require* a plan to exist, e.g. dynamic-child orchestrators in D.5c).
#
# Usage: cli.plan.gate <stage_id> [--strict]
cli.plan.gate() {
    brik.use cli.helpers
    brik.use planning.plan_reader
    brik.use pipeline.report

    local stage_id="" strict=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --strict) strict=true; shift ;;
            -*)       brik_usage_error "unknown option: $1" || return "$?" ;;
            *)        if [[ -z "$stage_id" ]]; then stage_id="$1"; shift
                      else brik_usage_error "unexpected argument: $1" || return "$?"; fi ;;
        esac
    done

    if [[ -z "$stage_id" ]]; then
        brik_error "'brik plan gate' requires a stage id"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi

    # Resolve a plan path: explicit env wins, otherwise the well-known
    # workspace location. No plan file => default to "run" unless --strict.
    local plan_file="${BRIK_PLAN_FILE:-}"
    if [[ -z "$plan_file" ]]; then
        local _ws="${BRIK_WORKSPACE:-$PWD}"
        [[ -f "$_ws/.brik-logs/plan.json" ]] && plan_file="$_ws/.brik-logs/plan.json"
    fi
    if [[ -z "$plan_file" || ! -f "$plan_file" ]]; then
        if [[ "$strict" == "true" ]]; then
            brik_error "plan file not found (BRIK_PLAN_FILE unset and no .brik-logs/plan.json)"
            return "${BRIK_EXIT_INVALID_INPUT}"
        fi
        return 0
    fi

    if pipeline.plan.should_run "$stage_id" "$plan_file"; then
        return 0
    fi

    # The plan says skip. Record a fragment so the aggregate-report.json
    # shows the stage as a deliberate skip with a machine-readable reason.
    # report.init is idempotent; calling it here covers orchestrators
    # (Jenkins, GitLab) that gate stages outside of pipeline.run.
    report.init >/dev/null 2>&1 || true
    local reason
    reason="$(pipeline.plan.reason "$stage_id" "$plan_file" 2>/dev/null || true)"
    report.record "$stage_id" "tech" "status" "skipped"        2>/dev/null || true
    report.record "$stage_id" "tech" "kind"   "not-applicable" 2>/dev/null || true
    [[ -n "$reason" ]] && \
        report.record "$stage_id" "business" "reason" "$reason" 2>/dev/null || true
    # Write the per-stage fragment so Notify can pick it up via
    # report.aggregate_fragments (Jenkins stash/unstash, GitLab artifacts).
    report.write_fragment "$stage_id" 2>/dev/null || true

    printf '[brik plan] %s: skipped (reason=%s)\n' "$stage_id" "${reason:-unknown}"
    return 1
}

# Render a human-friendly summary of the plan to stdout.
# Intentionally narrow: enough to spot "did I get balanced filtering?"
# and "which stages run?" without unwrapping the whole JSON.
cli.plan._render_explain() {
    local plan="$1"
    command -v jq >/dev/null 2>&1 || { printf '[brik plan] jq required for --explain\n' >&2; return 1; }

    jq -r '
        def pad(n): . + ((" " * (n - (. | length))));
        "Brik plan (\(.schemaVersion), brik \(.brikVersion))",
        "  context     : \(.context)",
        "  mode        : \(.mode)",
        "  workspace   : \(.workspace)",
        "  changes     : source=\(.changes.source)" +
                       (if (.changes.from_ref // "") != "" then " range=\(.changes.from_ref)..\(.changes.to_ref)" else "" end),
        "  fingerprint : \(.fingerprint)",
        "",
        "Stages:",
        (.stages[] | "  " +
            (if .decision == "run" then "[ RUN ]" else "[SKIP ]" end) +
            " " + (.id | pad(15)) +
            "  " + .reason +
            (if (.matched_globs | length) > 0 then "  (" + (.matched_globs | join(", ")) + ")" else "" end)
        )
    ' "$plan"
}

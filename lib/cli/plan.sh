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
#   --format <fmt>      output format (json; the default)
#   --with-release|--with-package|--with-deploy   opt-in gates

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_PLAN_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_PLAN_LOADED=1

cli.plan.run() {
    brik.use cli.helpers
    brik.use planning.plan_writer
    brik.use planning.plan_reader
    brik.use pipeline

    # Normalize platform CI variables to the BRIK_* contract the planner
    # reads (BRIK_COMMIT_TAG, BRIK_BRANCH, BRIK_COMMIT_SHA, ...). The
    # platform wrappers (gitlab-wrapper.sh, jenkins-wrapper.sh) set
    # BRIK_TAG / BRIK_BRANCH / BRIK_COMMIT_SHA but the canonical names
    # used by lib/planning/plan.sh include the COMMIT_ prefix; the
    # mapping was historically performed inside stage.dispatch, which
    # brik plan does NOT go through. Without this call here, a tag-push
    # pipeline resolved context=snapshot because BRIK_COMMIT_TAG was
    # empty even though BRIK_TAG was correctly set by the wrapper.
    if declare -f _pipeline.detect_metadata >/dev/null 2>&1; then
        _pipeline.detect_metadata
    fi

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
            mode="$(BRIK_CONFIG_FILE="$_cfg" config.get '.pipeline.selection.mode' 'safe' 2>/dev/null || printf 'safe')"
            BRIK_CONFIG_FILE="$_cfg" config.get '.pipeline.selection.stages' '' >/dev/null 2>&1 || true
        fi
        [[ -z "$mode" ]] && mode="safe"
    fi

    if [[ -n "$format" && "$format" != "json" ]]; then
        printf '[brik plan] --format=%s is not a known format (json)\n' \
            "$format" >&2
        return "$BRIK_EXIT_INVALID_INPUT"
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
        return "$BRIK_EXIT_INVALID_INPUT"
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
                return "$BRIK_EXIT_INVALID_INPUT"
            fi
        elif command -v check-jsonschema >/dev/null 2>&1; then
            if check-jsonschema --schemafile "$schema" "$tmp_json" >/dev/null 2>&1; then
                rm -f "$tmp_json"
                printf 'plan.json: valid against schema\n'
                return 0
            else
                rm -f "$tmp_json"
                return "$BRIK_EXIT_INVALID_INPUT"
            fi
        else
            rm -f "$tmp_json"
            printf '[brik plan] no JSON Schema validator available (install jv or check-jsonschema)\n' >&2
            return "$BRIK_EXIT_MISSING_DEP"
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
        cli.plan._render_explain "$out"
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
# *require* a plan to exist).
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

    # Render a one-line, user-facing skip message with a colored [SKIP]
    # status indicator and a concrete blocker (which flag, which context,
    # ...) instead of just the machine-readable reason code. The JSON
    # fragment above keeps the short code in business.reason for
    # downstream consumers.
    brik.use planning.plan 2>/dev/null || true     # for registry helpers
    brik.use transverse.render 2>/dev/null || true # for render.status
    local _plan_context _matched_globs _reason_text
    _plan_context="$(jq -r '.context // ""' "$plan_file" 2>/dev/null)"
    _matched_globs="$(jq -r --arg id "$stage_id" '.stages[] | select(.id == $id) | (.matched_globs // [] | join(","))' "$plan_file" 2>/dev/null || true)"
    _reason_text="$(cli.plan._reason_text "$stage_id" "${reason:-unknown}" "$_plan_context" "$_matched_globs")"
    printf '[brik plan] %s %s: %s\n' "$(render.status skipped)" "$stage_id" "$_reason_text"
    return 1
}

# Translate a plan reason code into a one-line, user-facing explanation.
# Names the concrete condition (which flag, which context, which globs)
# instead of just the machine-readable code. Shared by the per-stage gate
# message and the explain table.
#
# Args:
#   $1 stage_id
#   $2 reason_code   (context-match | context-mismatch | opt-in-flag-missing
#                     | no-impact | impacted | no-diff | no-impact-declared)
#   $3 context       (snapshot | release) from plan.json
#   $4 matched_globs (comma-separated, may be empty)
cli.plan._reason_text() {
    local stage_id="$1" reason="$2" context="${3:-}" matched_globs="${4:-}"

    case "$reason" in
        context-match)
            printf 'applicable to context [%s]' "$context"
            ;;
        context-mismatch)
            local req_contexts current_explain
            req_contexts="$(registry.stage.gate_contexts "$stage_id" 2>/dev/null \
                | tr '\n' ',' | sed -e 's/^,//' -e 's/,$//')"
            [[ -z "$req_contexts" ]] && req_contexts="unknown"
            case "$context" in
                snapshot) current_explain=" (BRIK_COMMIT_TAG is empty)" ;;
                release)  current_explain=" (BRIK_COMMIT_TAG is set)" ;;
                *)        current_explain="" ;;
            esac
            printf 'current context is [%s]%s; requires [%s]' \
                "$context" "$current_explain" "$req_contexts"
            ;;
        opt-in-flag-missing)
            local flag flag_target
            flag="$(registry.stage.gate_opt_in_flag "$stage_id" 2>/dev/null)"
            if [[ -n "$flag" ]]; then
                # --with-<x> activates stage <x>. When that target differs
                # from the current stage (e.g. container-scan opts in via
                # --with-package because it consumes the package livrable),
                # spell out the dependency so users don't search for a
                # --with-<stage_id> that does not exist.
                flag_target="${flag#--with-}"
                if [[ -n "$flag_target" && "$flag_target" != "$stage_id" ]]; then
                    printf 'depends on the %s stage (skipped: %s was not passed; both stages activate together)' \
                        "$flag_target" "$flag"
                else
                    printf 'the %s flag was not passed (this stage is opt-in)' "$flag"
                fi
            else
                printf 'the required opt-in flag was not passed'
            fi
            ;;
        no-impact)
            printf "no changed file matched this stage's impact patterns"
            ;;
        impacted)
            if [[ -n "$matched_globs" ]]; then
                printf 'changed files match: %s' "$matched_globs"
            else
                printf "changed files match this stage's impact patterns"
            fi
            ;;
        no-diff)
            printf 'no diff context available; running conservatively'
            ;;
        no-impact-declared)
            printf 'no impact patterns declared; runs by default'
            ;;
        *)
            printf '%s' "$reason"
            ;;
    esac
}

# Render a human-friendly summary of the plan to stdout.
# Delegates table rendering to transverse/render.sh, which handles
# ASCII box-drawing with computed column widths. The REASON column is
# computed via cli.plan._reason_text so it matches the per-stage gate
# message verbatim.
cli.plan._render_explain() {
    local plan="$1"
    command -v jq >/dev/null 2>&1 || { printf '[brik plan] jq required for --explain\n' >&2; return 1; }
    brik.use planning.plan 2>/dev/null || true   # for registry helpers
    brik.use transverse.render 2>/dev/null || true

    # Pull header data
    local schema brik_v context mode workspace
    local changes_src changes_from changes_to fingerprint
    schema=$(jq -r '.schemaVersion' "$plan")
    brik_v=$(jq -r '.brikVersion' "$plan")
    context=$(jq -r '.context' "$plan")
    mode=$(jq -r '.mode' "$plan")
    workspace=$(jq -r '.workspace' "$plan")
    changes_src=$(jq -r '.changes.source' "$plan")
    changes_from=$(jq -r '.changes.from_ref // ""' "$plan")
    changes_to=$(jq -r '.changes.to_ref // ""' "$plan")
    fingerprint=$(jq -r '.fingerprint' "$plan")

    # Plain-text header: title line + aligned key/value block.
    printf '\n'
    printf 'Brik plan (schema %s, brik %s)\n' "$schema" "$brik_v"
    render.kv "context"     "$context"   --key-width 11
    render.kv "mode"        "$mode"      --key-width 11
    render.kv "workspace"   "$workspace" --key-width 11
    if [[ -n "$changes_from" ]]; then
        render.kv "changes" "source=${changes_src} range=${changes_from}..${changes_to}" --key-width 11
    else
        render.kv "changes" "source=${changes_src}" --key-width 11
    fi
    render.kv "fingerprint" "$fingerprint" --key-width 11
    printf '\n'

    # Section heading + TSV table piped through render.table.
    # The REASON column is computed per-row via cli.plan._reason_text
    # so the same text appears here and in the per-stage gate message.
    # DECISION is emitted in uppercase (RUN/SKIP) so render.table can
    # color each row through --color-by DECISION via render.color_for_status.
    render.section "Stages"
    {
        printf 'ID\tDECISION\tGATE\tCODE\tREASON\n'
        local id decision gate_mode reason matched_globs reason_text
        while IFS=$'\t' read -r id decision gate_mode reason matched_globs; do
            reason_text=$(cli.plan._reason_text "$id" "$reason" "$context" "$matched_globs")
            printf '%s\t%s\t%s\t%s\t%s\n' \
                "$id" "${decision^^}" "$gate_mode" "$reason" "$reason_text"
        done < <(jq -r '.stages[] | [.id, .decision, .gate.mode, .reason, (.matched_globs // [] | join(","))] | @tsv' "$plan")
    } | render.table --color-by DECISION
}

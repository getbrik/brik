#!/usr/bin/env bash
# @module cli.integrate
# @description CLI entrypoint for "brik integrate". Runs the full CI flow
#   (the fixed integrate pipeline) via the local wrapper.

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_INTEGRATE_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_INTEGRATE_LOADED=1

# cli.integrate.run - execute the full CI pipeline via the local wrapper.
# Usage: cli.integrate.run [--config <path>] [--workspace <path>] [--dry-run]
#        [--continue-on-error] [--with-release] [--with-package] [--with-deploy]
#        [--plan <plan.json>] [--auto-select]
cli.integrate.run() {
    brik.use cli.helpers
    brik.use cli.local_runner

    local config_path=""
    local workspace=""
    local dry_run=""
    local plan_file=""
    local auto_select=false
    local release_mode=false
    local release_tag=""
    local -a pipeline_flags=()

    workspace="$(pwd)"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                brik_require_arg "--config" "${2-}" || return "$?"
                config_path="$2"
                shift 2
                ;;
            --workspace)
                brik_require_arg "--workspace" "${2-}" || return "$?"
                workspace="$2"
                shift 2
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            --plan)
                brik_require_arg "--plan" "${2-}" || return "$?"
                plan_file="$2"
                shift 2
                ;;
            --auto-select)
                auto_select=true
                shift
                ;;
            --release)
                release_mode=true
                shift
                ;;
            --tag)
                brik_require_arg "--tag" "${2-}" || return "$?"
                release_tag="$2"
                release_mode=true
                shift 2
                ;;
            --continue-on-error|--with-release|--with-package|--with-deploy)
                pipeline_flags+=("$1")
                shift
                ;;
            --platform)
                brik_require_arg "--platform" "${2-}" || return "$?"
                export BRIK_LOCAL_PLATFORM="$2"
                shift 2
                ;;
            --bind-mount)
                export BRIK_LOCAL_BIND_MOUNT=1
                shift
                ;;
            -h|--help)
                brik_print_verb_help integrate
                return 0
                ;;
            *)
                brik_usage_error "unknown option: $1" || return "$?"
                ;;
        esac
    done

    if [[ -z "$config_path" ]]; then
        config_path="${workspace}/${BRIK_DEFAULT_CONFIG}"
    fi

    # Release context. The CI adapters set BRIK_COMMIT_TAG from a tag-push
    # event; locally the operator asks for a release with --release (the tag
    # at HEAD) or --tag <version> (explicit). Exporting BRIK_COMMIT_TAG makes
    # the planner and every stage resolve context=release, and pulls in the
    # release + package stages so the run produces a publishable artifact.
    if [[ "$release_mode" == "true" ]]; then
        if [[ -z "$release_tag" ]]; then
            release_tag="$(git -C "$workspace" describe --tags --exact-match HEAD 2>/dev/null || true)"
            if [[ -z "$release_tag" ]]; then
                brik_error "--release requires a tag at HEAD; tag the commit or pass --tag <version>"
                return "${BRIK_EXIT_INVALID_INPUT}"
            fi
        fi
        export BRIK_COMMIT_TAG="$release_tag"
        pipeline_flags+=(--with-release --with-package)
    fi

    export BRIK_PROJECT_DIR="${workspace}"
    export BRIK_WORKSPACE="${workspace}"
    export BRIK_CONFIG_FILE="${config_path}"
    export BRIK_LOG_DIR="${BRIK_LOG_DIR:-${workspace}/.brik-logs}"
    mkdir -p "${BRIK_LOG_DIR}"

    # Activate dry-run only when the flag was passed. We never demote a
    # pre-existing BRIK_DRY_RUN=true exported by the caller's shell.
    [[ "$dry_run" == "true" ]] && export BRIK_DRY_RUN="true"

    if [[ -n "$plan_file" && ! -f "$plan_file" ]]; then
        brik_error "plan file not found: $plan_file"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi

    # Containerized local execution (the only local mode): on a bare host the
    # flow runs one runner-class container per stage, exactly like the CI
    # adapters -- the planner always runs (in its own container), so
    # --auto-select is implicit here. Inside a CI job or a brik container
    # the verb executes in-process: the caller IS the execution environment.
    if brik_host_local; then
        cli.local_runner.default_infra
        cli.local_runner.setup_docker_env || return "$?"
        local -a engine_flags=("${pipeline_flags[@]}")
        [[ -n "$plan_file" ]] && engine_flags+=(--plan "$plan_file")
        cli.local_runner.runtime brik.local.docker.run_pipeline "${engine_flags[@]}"
        return "$?"
    fi

    # Plan-driven mode.
    # --plan points pipeline.plan.gate at an existing plan.json.
    # --auto-select runs the planner first and points the gate at the
    # freshly-written file. --plan takes precedence when both are set.
    if [[ -n "$plan_file" ]]; then
        export BRIK_PLAN_FILE="$plan_file"
    elif [[ "$auto_select" == "true" ]]; then
        brik.use cli.plan
        local _auto_plan="${BRIK_LOG_DIR}/plan.json"
        # The planner inherits the workspace + opt-in flags so the plan
        # reflects what pipeline.run will be told to execute. Without
        # this, --auto-select + --with-deploy would still skip deploy
        # in the plan (opt-in-flag-missing).
        local -a _plan_pass=(--workspace "$workspace" --out "$_auto_plan")
        local _f
        for _f in "${pipeline_flags[@]}"; do
            case "$_f" in
                --with-release|--with-package|--with-deploy) _plan_pass+=("$_f") ;;
            esac
        done
        if ! cli.local_runner.runtime cli.plan.run "${_plan_pass[@]}"; then
            brik_error "auto-select planner failed; refusing to run pipeline blind"
            return "${BRIK_EXIT_FAILURE}"
        fi
        export BRIK_PLAN_FILE="$_auto_plan"
    fi

    cli.local_runner.setup_env || return "$?"

    cli.local_runner.runtime brik.local.run_integrate "${pipeline_flags[@]}"
}

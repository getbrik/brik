#!/usr/bin/env bash
# @module cli.init
# @description CLI entrypoint for "brik init". Scaffolds brik.yml and the
#   per-platform bootstrap file (GitLab/GitHub/Jenkins).

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_INIT_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_INIT_LOADED=1

# cli.init.run - parse CLI args and scaffold brik.yml + bootstrap.
# Usage: cli.init.run [--stack <s>] [--platform <p>] [--dir <d>] [--non-interactive]
cli.init.run() {
    brik.use cli.helpers

    local stack=""
    local platform="gitlab"
    local target_dir="."
    local non_interactive=false
    local project_name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --stack)
                brik_require_arg "--stack" "${2-}" || return "$?"
                stack="$2"
                shift 2
                ;;
            --platform)
                brik_require_arg "--platform" "${2-}" || return "$?"
                platform="$2"
                shift 2
                ;;
            --dir)
                brik_require_arg "--dir" "${2-}" || return "$?"
                target_dir="$2"
                shift 2
                ;;
            --non-interactive)
                non_interactive=true
                shift
                ;;
            *)
                brik_usage_error "unknown option: $1" || return "$?"
                ;;
        esac
    done

    pipeline.require_dir "${target_dir}" || return "$?"

    if [[ -f "${target_dir}/brik.yml" ]]; then
        brik_error "brik.yml already exists in ${target_dir}"
        return "${BRIK_EXIT_INVALID_INPUT}"
    fi

    if [[ -z "${stack}" ]]; then
        brik.use stacks._detect
        if ! stack="$(stacks.detect "${target_dir}" 2>/dev/null)"; then
            if [[ "${non_interactive}" == true ]]; then
                brik_error "could not detect stack and --stack was not specified"
                return "${BRIK_EXIT_INVALID_INPUT}"
            fi
            brik_error "could not detect stack - use --stack to specify one"
            return "${BRIK_EXIT_INVALID_INPUT}"
        fi
        brik_print "Detected stack: ${stack}"
    fi

    case "${stack}" in
        node|java|python|rust|dotnet) ;;
        *)
            brik_error "unsupported stack: ${stack}"
            brik_error "Supported stacks: node, java, python, rust, dotnet"
            return "${BRIK_EXIT_INVALID_INPUT}"
            ;;
    esac

    case "${platform}" in
        gitlab|github|jenkins) ;;
        *)
            brik_error "unsupported platform: ${platform}"
            brik_error "Supported platforms: gitlab, github, jenkins"
            return "${BRIK_EXIT_INVALID_INPUT}"
            ;;
    esac

    project_name="$(basename "$(cd "${target_dir}" && pwd)")"

    _cli.init._generate_config "${target_dir}" "${project_name}" "${stack}"
    _cli.init._generate_bootstrap "${target_dir}" "${platform}"

    brik_print "Created brik.yml and ${platform} bootstrap in ${target_dir}"
    return "${BRIK_EXIT_OK}"
}

_cli.init._generate_config() {
    local target_dir="$1"
    local project_name="$2"
    local stack="$3"

    # Honor a custom test script (node --test, vitest, mocha...) by pinning
    # test.framework: npm. The node stack default is jest, so without this the
    # scaffolded brik.yml fails the init stage's config-vs-project coherence
    # check on any non-jest project -- i.e. `brik init && brik integrate` would
    # break out of the box.
    local test_block=""
    if [[ "$stack" == "node" ]]; then
        local pkg="${target_dir}/package.json"
        if [[ -f "$pkg" ]] && command -v jq >/dev/null 2>&1 \
            && jq -e '.scripts.test // empty' "$pkg" >/dev/null 2>&1; then
            test_block=$'\n\ntest:\n  framework: npm'
        fi
    fi

    cat > "${target_dir}/brik.yml" <<YAML
version: 1

project:
  name: "${project_name}"
  stack: ${stack}${test_block}
YAML
}

_cli.init._generate_bootstrap() {
    local target_dir="$1"
    local platform="$2"

    case "${platform}" in
        gitlab)
            cat > "${target_dir}/.gitlab-ci.yml" <<YAML
include:
  - project: 'brik/gitlab-templates'
    ref: ${BRIK_REF}
    file: '/templates/brik-integrate.yml'
YAML
            ;;
        github)
            mkdir -p "${target_dir}/.github/workflows"
            cat > "${target_dir}/.github/workflows/ci.yml" <<YAML
name: Brik Pipeline
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  brik:
    uses: getbrik/brik/.github/workflows/brik-pipeline.yml@${BRIK_REF}
    with:
      config: brik.yml
YAML
            ;;
        jenkins)
            cat > "${target_dir}/Jenkinsfile" <<GROOVY
@Library('brik@${BRIK_REF}') _
brikIntegrate()
GROOVY
            ;;
    esac
}

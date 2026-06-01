#!/usr/bin/env bash
# @module cli.help
# @description CLI entrypoint for "brik help".

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_HELP_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_HELP_LOADED=1

# cli.help._stage_list - canonical, comma-separated pipeline stage list.
# Prefers the registry (registry.stage.list, the single source of truth) and
# falls back to the documented fixed flow so `brik help` still works when the
# registry cannot be loaded.
cli.help._stage_list() {
    brik.use registry.registry 2>/dev/null || true
    if declare -f registry.stage.list >/dev/null 2>&1; then
        local _ids
        if _ids="$(registry.stage.list 2>/dev/null)" && [[ -n "$_ids" ]]; then
            printf '%s' "$_ids" | paste -sd, - | sed 's/,/, /g'
            return 0
        fi
    fi
    printf '%s' "init, release, build, lint, sast, scan, test, package, container-scan, promote, deploy, notify"
}

# cli.help.run - print usage text.
cli.help.run() {
    local _stages
    _stages="$(cli.help._stage_list)"
    cat <<EOF
brik ${BRIK_VERSION} - Portable CI/CD pipeline CLI

Usage:
  brik <command> [options]

Commands:
  validate         Validate brik.yml against the JSON Schema
  doctor           Check prerequisites (tools, stack detection)
  init             Scaffold brik.yml and platform bootstrap file
  run stage        Execute a single pipeline stage locally
  run pipeline     Execute the full pipeline locally
  extension test   Validate an extension manifest+module against the contract
  self-update      Update brik to the latest version
  self-uninstall   Remove brik from your system
  version          Print brik version information
  help             Print this help message

Options for validate:
  --config <path>   Path to brik.yml (default: brik.yml in current directory)
  --schema <path>   Path to JSON Schema file (default: bundled schema)

Options for doctor:
  --workspace <path>   Path to project directory (default: current directory)

Options for init:
  --stack <name>       Stack: node, java, python, rust, dotnet (auto-detected if omitted)
  --platform <name>    Platform: gitlab (default), github, jenkins
  --dir <path>         Target directory (default: current directory)
  --non-interactive    Skip prompts, fail if stack cannot be auto-detected

Options for run stage:
  --config <path>      Path to brik.yml (default: brik.yml in workspace)
  --workspace <path>   Path to project workspace (default: current directory)
  --dry-run            Skip destructive deploy actions (compose up, k8s apply,
                       helm upgrade, argocd sync, rsync). Print what would run
                       instead. Exports BRIK_DRY_RUN=true.

Options for run pipeline:
  --config <path>         Path to brik.yml (default: brik.yml in workspace)
  --workspace <path>      Path to project workspace (default: current directory)
  --dry-run               Skip destructive deploy actions (compose up, k8s apply,
                          helm upgrade, argocd sync, rsync). Print what would run
                          instead. Exports BRIK_DRY_RUN=true.
  --continue-on-error     Continue pipeline despite stage failure
  --with-release          Include the release stage
  --with-package          Include the package stage
  --with-deploy           Include deploy and notify stages

Options for extension test:
  (positional)            Path to the extension directory (must contain
                          stacks/ or stages/ manifests, and lib/*.sh modules).

Options for self-update:
  --channel <name>        Update channel: stable (default), edge
  --version <tag>         Update to a specific version tag

Options for self-uninstall:
  --force                 Skip confirmation prompt

Options for version:
  --verbose               Show additional info (home, install method, commit)

Stages:
  ${_stages}

Examples:
  brik validate
  brik validate --config path/to/brik.yml
  brik doctor
  brik doctor --workspace ./my-project
  brik init
  brik init --stack node --platform gitlab
  brik run stage build
  brik run stage lint --workspace ./my-project
  brik run stage deploy --dry-run
  brik run pipeline
  brik run pipeline --with-package --continue-on-error
  brik run pipeline --with-deploy --dry-run
  brik extension test ./my-extension
  brik self-update
  brik self-update --channel edge
  brik self-update --version v0.6.0
  brik version
  brik version --verbose
EOF
}

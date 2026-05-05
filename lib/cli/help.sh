#!/usr/bin/env bash
# @module cli.help
# @description CLI entrypoint for "brik help".

# Guard against double-sourcing.
[[ -n "${_BRIK_MODULE_CLI_HELP_LOADED:-}" ]] && return 0
_BRIK_MODULE_CLI_HELP_LOADED=1

# cli.help.run - print usage text.
cli.help.run() {
    cat <<EOF
brik ${BRIK_VERSION} - Portable CI/CD pipeline CLI

Usage:
  brik <command> [options]

Commands:
  validate       Validate brik.yml against the JSON Schema
  doctor         Check prerequisites (tools, stack detection)
  init           Scaffold brik.yml and platform bootstrap file
  run stage      Execute a single pipeline stage locally
  run pipeline   Execute the full pipeline locally
  self-update    Update brik to the latest version
  self-uninstall Remove brik from your system
  version        Print brik version information
  help           Print this help message

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

Options for run pipeline:
  --config <path>         Path to brik.yml (default: brik.yml in workspace)
  --workspace <path>      Path to project workspace (default: current directory)
  --continue-on-error     Continue pipeline despite stage failure
  --with-release          Include the release stage
  --with-package          Include the package stage
  --with-deploy           Include deploy and notify stages

Options for self-update:
  --channel <name>        Update channel: stable (default), edge
  --version <tag>         Update to a specific version tag

Options for self-uninstall:
  --force                 Skip confirmation prompt

Options for version:
  --verbose               Show additional info (home, install method, commit)

Stages:
  init, release, build, lint, sast, scan, test, package, container-scan, deploy, notify

Examples:
  brik validate
  brik validate --config path/to/brik.yml
  brik doctor
  brik doctor --workspace ./my-project
  brik init
  brik init --stack node --platform gitlab
  brik run stage build
  brik run stage lint --workspace ./my-project
  brik run pipeline
  brik run pipeline --with-package --continue-on-error
  brik self-update
  brik self-update --channel edge
  brik self-update --version v0.4.0
  brik version
  brik version --verbose
EOF
}
